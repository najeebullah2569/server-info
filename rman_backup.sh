#!/usr/bin/env bash
# rman_backup.sh - Oracle RMAN incremental backup (level 0 or level 1).
#
# Usage:
#   ./rman_backup.sh 0     # level 0: full baseline backup of every data block
#   ./rman_backup.sh 1     # level 1: only blocks changed since the last backup
#   ./rman_backup.sh       # no argument: level 0 on Sunday, level 1 other days
#
# Run as the "oracle" OS user (the script connects with "target /").
#
# Example crontab for the oracle user (one entry covers both levels):
#   30 1 * * * /home/oracle/scripts/rman_backup.sh >/dev/null 2>&1

set -u

# ---------------------------------------------------------------------------
# Settings - change these to match your server
# ---------------------------------------------------------------------------
export ORACLE_SID="${ORACLE_SID:-ORCL}"                                   # database to back up
export ORACLE_HOME="${ORACLE_HOME:-/u01/app/oracle/product/19.0.0/dbhome_1}"
export PATH="${ORACLE_HOME}/bin:${PATH}"
export NLS_DATE_FORMAT="YYYY-MM-DD HH24:MI:SS"                            # readable times in the RMAN log

BACKUP_DIR="/backup/rman/${ORACLE_SID}"   # where backup pieces are written
LOG_DIR="/backup/rman/logs"               # where log files are written
PARALLELISM=2                             # number of disk channels used at once
RECOVERY_WINDOW_DAYS=7                    # keep backups needed to restore to any point in the last N days
LOG_KEEP_DAYS=30                          # delete log files older than N days
LEVEL0_DAY=7                              # day for automatic level 0 (1=Monday ... 7=Sunday)
CUMULATIVE="no"                           # "yes" = level 1 cumulative, "no" = level 1 differential
ARCHIVELOG_KEEP_HOURS=24                  # archivelogs already backed up and older than this are deleted from disk

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Print a message with a timestamp to the screen and the log file.
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" | tee -a "$LOG_FILE"
}

# Print an error, then stop with a failure exit code.
die() {
    local msg="$1"
    log "ERROR: ${msg}"
    exit 1
}

# ---------------------------------------------------------------------------
# Choose the backup level
# ---------------------------------------------------------------------------

# Use the first argument if one was given, otherwise decide from the weekday.
if [ $# -ge 1 ]; then
    LEVEL="$1"
elif [ "$(date +%u)" -eq "$LEVEL0_DAY" ]; then
    LEVEL=0
else
    LEVEL=1
fi

# Only 0 and 1 are valid levels.
if [ "$LEVEL" != "0" ] && [ "$LEVEL" != "1" ]; then
    echo "Usage: $0 [0|1]" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Prepare folders, log file and lock
# ---------------------------------------------------------------------------

# Create the backup and log folders if they do not exist yet.
mkdir -p "$BACKUP_DIR" "$LOG_DIR" || { echo "Cannot create $BACKUP_DIR or $LOG_DIR" >&2; exit 1; }

# One log file per run, e.g. rman_ORCL_L0_20261113_013000.log
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/rman_${ORACLE_SID}_L${LEVEL}_${TIMESTAMP}.log"

# Lock: mkdir is atomic, so only one copy of the script can hold the lock.
# This stops a slow level 0 from overlapping with the next scheduled run.
LOCK_DIR="/tmp/rman_backup_${ORACLE_SID}.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    die "Another backup for ${ORACLE_SID} is already running (lock: ${LOCK_DIR})."
fi
# Remove the lock when the script exits, whether it succeeds or fails.
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# Make sure the RMAN program exists in ORACLE_HOME.
[ -x "${ORACLE_HOME}/bin/rman" ] || die "rman not found in ${ORACLE_HOME}/bin"

# ---------------------------------------------------------------------------
# Build the RMAN commands
# ---------------------------------------------------------------------------

# Level 1 can be differential (changes since the last level 0 or 1)
# or cumulative (all changes since the last level 0).
if [ "$LEVEL" = "1" ] && [ "$CUMULATIVE" = "yes" ]; then
    LEVEL_CLAUSE="INCREMENTAL LEVEL 1 CUMULATIVE"
else
    LEVEL_CLAUSE="INCREMENTAL LEVEL ${LEVEL}"
fi

# Allocate one disk channel per PARALLELISM. Channels are allocated inside
# the RUN block, so the database's saved RMAN configuration is not changed.
CHANNELS=""
RELEASES=""
for i in $(seq 1 "$PARALLELISM"); do
    CHANNELS+="  ALLOCATE CHANNEL d${i} DEVICE TYPE DISK;"$'\n'
    RELEASES+="  RELEASE CHANNEL d${i};"$'\n'
done

# File name pattern for backup pieces:
#   %d = database name, %T = date (YYYYMMDD), %U = unique name.
FMT="${BACKUP_DIR}/%d_L${LEVEL}_%T_%U.bkp"

log "Starting RMAN level ${LEVEL} backup of ${ORACLE_SID} (log: ${LOG_FILE})"

# ---------------------------------------------------------------------------
# Run RMAN
# ---------------------------------------------------------------------------
# The heredoc sends the commands below to RMAN. Bash fills in the ${...}
# variables before RMAN sees them.
rman target / log="$LOG_FILE" append <<EOF
RUN {
${CHANNELS}
  # Back up archived redo logs that have not been backed up yet.
  BACKUP AS COMPRESSED BACKUPSET ARCHIVELOG ALL NOT BACKED UP 1 TIMES
    FORMAT '${BACKUP_DIR}/%d_ARC_%T_%U.bkp';

  # The main incremental backup of all datafiles (level 0 or level 1).
  BACKUP AS COMPRESSED BACKUPSET ${LEVEL_CLAUSE} DATABASE
    FORMAT '${FMT}' TAG 'LEVEL${LEVEL}_${TIMESTAMP}';

  # Switch to a new redo log so the changes made during the backup are archived.
  SQL 'ALTER SYSTEM ARCHIVE LOG CURRENT';

  # Back up the archived logs created during the backup.
  BACKUP AS COMPRESSED BACKUPSET ARCHIVELOG ALL NOT BACKED UP 1 TIMES
    FORMAT '${BACKUP_DIR}/%d_ARC_%T_%U.bkp';

  # Back up the control file and spfile; these are needed for any restore.
  BACKUP CURRENT CONTROLFILE FORMAT '${BACKUP_DIR}/%d_CTL_%T_%U.bkp';
  BACKUP SPFILE FORMAT '${BACKUP_DIR}/%d_SPF_%T_%U.bkp';
${RELEASES}}

# Mark backup files that were deleted outside RMAN as EXPIRED.
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;

# Delete archived logs from disk only after they are backed up and older than the limit.
DELETE NOPROMPT ARCHIVELOG ALL BACKED UP 1 TIMES TO DEVICE TYPE DISK
  COMPLETED BEFORE 'SYSDATE - ${ARCHIVELOG_KEEP_HOURS}/24';

# Delete backups that are no longer needed for the recovery window.
DELETE NOPROMPT OBSOLETE RECOVERY WINDOW OF ${RECOVERY_WINDOW_DAYS} DAYS;

# Remove catalog records of files that no longer exist.
DELETE NOPROMPT EXPIRED BACKUP;

EXIT;
EOF
RMAN_STATUS=$?

# ---------------------------------------------------------------------------
# Check the result
# ---------------------------------------------------------------------------

# RMAN returns a non-zero exit code on failure; also scan the log for
# "RMAN-00569", the banner RMAN prints above every error stack.
if [ "$RMAN_STATUS" -ne 0 ] || grep -q "RMAN-00569" "$LOG_FILE"; then
    die "RMAN level ${LEVEL} backup FAILED (exit code ${RMAN_STATUS}). See ${LOG_FILE}"
fi

log "RMAN level ${LEVEL} backup completed successfully."

# Remove old log files so the log folder does not grow forever.
find "$LOG_DIR" -name "rman_${ORACLE_SID}_*.log" -type f -mtime +"$LOG_KEEP_DAYS" -delete 2>/dev/null

exit 0
