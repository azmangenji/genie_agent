#!/bin/tcsh
# CDC/RDC static check command

# Get RHEL version for LSF resource selection (inline)
set uname_result = `uname -r`
if ("$uname_result" =~ *el8*) then
    set RHEL_TYPE = "RHEL8_64"
else
    set RHEL_TYPE = "RHEL7_64"
endif

echo "CDC/RDC execution started at `date`"
echo "Using RHEL type: $RHEL_TYPE"
lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=30000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:umc_top_drop2cad).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS="umc_top" -DRHEA_CDC_OPTS='-CDC_RDC' -l logs/cdc_rdc.log
echo "CDC/RDC execution completed at `date`"
