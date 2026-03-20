#!/bin/tcsh
# Get RHEL version and set environment variable
# Usage: source get_rhel_version.csh
# Sets: $RHEL_TYPE (e.g., "RHEL7_64" or "RHEL8_64")

# Extract RHEL version from kernel string (e.g., el7, el8)
set kernel_str = `uname -r`
set rhel_ver = `echo $kernel_str | grep -oE 'el[0-9]+'`

if ("$rhel_ver" == "el8") then
    set RHEL_TYPE = "RHEL8_64"
else if ("$rhel_ver" == "el7") then
    set RHEL_TYPE = "RHEL7_64"
else
    # Default to RHEL8 if unable to detect
    echo "WARNING: Unable to detect RHEL version from kernel ($kernel_str), defaulting to RHEL8_64"
    set RHEL_TYPE = "RHEL8_64"
endif

echo "Detected RHEL type: $RHEL_TYPE"
