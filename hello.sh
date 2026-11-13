#!/usr/bin/env bash
# The line above (shebang) tells the system to run this script with bash.

# Define a function named print_name that takes two arguments.
print_name() {
    # Store the first argument passed to the function as the first name.
    local first_name="$1"
    # Store the second argument passed to the function as the last name.
    local last_name="$2"
    # Print a greeting that includes both names.
    echo "Hello, ${first_name} ${last_name}!"
}

# Prompt the user and read their first name into the variable first.
read -r -p "Enter your first name: " first

# Prompt the user and read their last name into the variable last.
read -r -p "Enter your last name: " last

# Call the function, passing the first and last name as arguments.
print_name "$first" "$last"
