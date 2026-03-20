#!/bin/tcsh
# OSS Spyglass DFT execution wrapper
# Called by static_check_command.csh
# Requires: $tile_name, $source_dir

echo "========================================="
echo "Running Spyglass DFT checks for OSS"
echo "Tile: $tile_name"
echo "========================================="

# Get RHEL version for LSF resource selection
set uname_result = `uname -r`
if ("$uname_result" =~ *el8*) then
    set RHEL_TYPE = "RHEL8_64"
else
    set RHEL_TYPE = "RHEL7_64"
endif
echo "Using RHEL type: $RHEL_TYPE"

# Set OSS-specific environment
bootenv -v orion

# Execute Spyglass DFT checks based on tile
if ($tile_name == "osssys") then
    echo "Running Spyglass DFT checks for osssys..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -x osssys_orion -e 'oss.top.osssys_spg_dft' -l logs/osssys_spg_dft.log

else if ($tile_name == "hdp") then
    echo "Running Spyglass DFT checks for hdp..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -x hdp_orion -e 'oss.top.hdp_spg_dft' -l logs/hdp_spg_dft.log

else if ($tile_name == "sdma0_gc" || $tile_name == "sdma1_gc") then
    echo "Running Spyglass DFT checks for sdma..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -m 5 -x sdma_orion -e 'oss.top.sdma_spg_dft' -l logs/sdma_spg_dft_agent.log

else if ($tile_name == "all") then
    echo "Running Spyglass DFT checks for all tiles..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -m 5 -x osssys_orion -e 'oss.top.osssys_spg_dft' -x hdp_orion -e 'oss.top.hdp_spg_dft' -l logs/oss_spg_dft_agent.log
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -m 5 -x sdma_orion -e 'oss.top.sdma_spg_dft' -l logs/sdma_spg_dft_agent.log

else
    echo "ERROR: Unknown tile name: $tile_name"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

echo "Spyglass DFT execution completed"
