#!/bin/tcsh
# GMC Spyglass DFT static check command
# Command: lsf_bsub -q regr_high -R rusage[mem=79000] -R select[type==RHEL8_64] -P rtg-mcip-ver -W 1000 be_dj -x gmc13_1a -m 16000 -e "gmc.rhea_dc_dft.build" -DABV_OFF -DRHEA_DC_OPTS="--timing_check" -l gmc13_1a_rhea_dc_dft_gmc_w_phy.log

# Get RHEL version for LSF resource selection
set uname_result = `uname -r`
if ("$uname_result" =~ *el8*) then
    set RHEL_TYPE = "RHEL8_64"
else
    set RHEL_TYPE = "RHEL7_64"
endif

echo "GMC Spyglass DFT execution started at `date`"
echo "Using RHEL type: $RHEL_TYPE"

# GMC SPG_DFT uses lsf_bsub with be_dj
# Note: GMC explicitly requires RHEL8_64
lsf_bsub -q regr_high -R "rusage[mem=79000]" -R "select[type==RHEL8_64]" -P rtg-mcip-ver -W 1000 be_dj -x gmc13_1a -m 16000 -e "gmc.rhea_dc_dft.build" -DABV_OFF -DRHEA_DC_OPTS="--timing_check" -l logs/gmc13_1a_rhea_dc_dft_gmc_w_phy.log

echo "GMC Spyglass DFT execution completed at `date`"
