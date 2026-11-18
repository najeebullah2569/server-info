# Managed MySQL 8.4 (same major version as the README) - Multi-AZ standby, encrypted,
# automated backups. Replaces the single "01-MySQL" server from the README.
# The app creates its own schema + seed data on first start (spring.sql.init.mode=always).

resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "-_" # safe inside a JDBC env file
}

resource "aws_db_instance" "mysql" {
  identifier     = "${local.name}-mysql"
  engine         = "mysql"
  engine_version = "8.4"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "roboshop"
  username = "roboshop"
  password = random_password.db.result

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period    = 7
  backup_window              = "03:00-04:00"
  maintenance_window         = "sun:04:30-sun:05:30"
  auto_minor_version_upgrade = true

  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = !var.db_deletion_protection
  final_snapshot_identifier = "${local.name}-mysql-final"
}

# Ansible reads the password from here at deploy time - it is never written to the repo.
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project}/${var.environment}/db/password"
  type  = "SecureString"
  value = random_password.db.result
}
