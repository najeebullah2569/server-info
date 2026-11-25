#!/bin/bash

echo "============================"
echo "MY FIRST DEVOPS SCRIPT"
echo "============================"

echo "Current User: $(whoami)"
echo "Hostname: $(hostname)"
echo "Date: $(date)"

echo "Disk Usage:"
df -h /

echo "Script completed successfully!"