#!/bin/tcsh
# GMC CDC/RDC static check command
# Command: bdji -e 'releaseflow::dropflow(:gmc_cdc).build(:rhea_drop, :rhea_cdc)' -J lsf -l gmc_cdc.log -DRHEA_CDC_OPTS='-cdc_yml $STEMS/src/meta/tools/cdc0in/variant/gmc13_1a/cdc.yml'

# Get RHEL version for LSF resource selection
set uname_result = `uname -r`
if ("$uname_result" =~ *el8*) then
    set RHEL_TYPE = "RHEL8_64"
else
    set RHEL_TYPE = "RHEL7_64"
endif

echo "GMC CDC/RDC execution started at `date`"
echo "Using RHEL type: $RHEL_TYPE"

# GMC uses bdji with gmc_cdc dropflow
# -J lsf handles LSF submission internally
bdji -e 'releaseflow::dropflow(:gmc_cdc).build(:rhea_drop, :rhea_cdc)' -J lsf -l logs/gmc_cdc_rdc.log -DRHEA_CDC_OPTS='-cdc_yml $STEMS/src/meta/tools/cdc0in/variant/gmc13_1a/cdc.yml'

echo "GMC CDC/RDC execution completed at `date`"
