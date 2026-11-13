#!/usr/bin/env bash
# student-grade.sh - Ask for a student's name and exam score, then print the grade.
#
# Grading scale:
#   90-100 = A
#   80-89  = B
#   70-79  = C
#   60-69  = D
#   0-59   = F

# Ask the user for the student's name and store it in "name".
read -r -p "Enter the student's name: " name

# Ask the user for the exam score and store it in "score".
read -r -p "Enter the exam score (0-100): " score

# Check that the score contains only digits (a whole number, no letters or signs).
if ! [[ "$score" =~ ^[0-9]+$ ]]; then
    echo "Error: the score must be a whole number." >&2
    exit 1
fi

# Remove any leading zeros (e.g. "085") so bash does not read it as an octal number.
score=$((10#$score))

# Check that the score is inside the allowed range.
if (( score > 100 )); then
    echo "Error: the score must be between 0 and 100." >&2
    exit 1
fi

# Pick the grade: check from the highest band down, so the first match wins.
if (( score >= 90 )); then
    grade="A"
elif (( score >= 80 )); then
    grade="B"
elif (( score >= 70 )); then
    grade="C"
elif (( score >= 60 )); then
    grade="D"
else
    grade="F"
fi

# Print the result.
echo "${name:-Student} scored ${score} and got grade ${grade}."
