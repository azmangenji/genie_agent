#!/bin/tcsh
# OSS CDC/RDC execution wrapper
# Called by static_check_command.csh
# Requires: $tile_name, $source_dir

echo "========================================="
echo "Running CDC/RDC checks for OSS"
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

# Execute CDC/RDC checks based on tile
if ($tile_name == "osssys") then
    echo "Running CDC/RDC checks for osssys..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -x osssys_orion -e 'releaseflow::dropflow(:osssys_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='osssys' -l logs/osssys_cdc_agent.log

else if ($tile_name == "hdp") then
    echo "Running CDC/RDC checks for hdp..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -x hdp_orion -e 'releaseflow::dropflow(:hdp_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='hdp'

else if ($tile_name == "sdma0_gc") then
    echo "Running CDC/RDC checks for sdma0_gc..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -x sdma_orion -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='sdma0_gc'

else if ($tile_name == "sdma1_gc") then
    echo "Running CDC/RDC checks for sdma1_gc..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -x sdma_orion -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='sdma1_gc'

else if ($tile_name == "all") then
    echo "Running CDC/RDC checks for all tiles..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -x sdma_orion -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS="sdma1_gc"
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -x sdma_orion -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS="sdma0_gc"
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -x hdp_orion -e 'releaseflow::dropflow(:hdp_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='hdp'
    lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -x osssys_orion -e 'releaseflow::dropflow(:osssys_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='osssys' -l logs/osssys_cdc_agent.log

else
    echo "ERROR: Unknown tile name: $tile_name"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

echo "CDC/RDC execution completed"
