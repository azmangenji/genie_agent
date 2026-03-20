#!/bin/tcsh
# OSS RTL build execution wrapper
# Called by static_check_command.csh
# Requires: $tile_name, $source_dir, $tag

echo "========================================="
echo "Running RTL build for OSS"
echo "Tile: $tile_name"
echo "========================================="

# Set OSS-specific environment
bootenv -v orion

# Execute RTL build based on tile
if ($tile_name == "osssys") then
    echo "Running RTL build for osssys..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:osssys_dc_elab).build(:rhea_drop)' -l osssys_rtl.log
    
else if ($tile_name == "hdp") then
    echo "Running RTL build for hdp..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:hdp_dc_elab).build(:rhea_drop)' -l hdp_rtl.log
    
else if ($tile_name == "sdma0_gc") then
    echo "Running RTL build for sdma0_gc..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop)' -l sdma0_gc_rtl.log
    
else if ($tile_name == "sdma1_gc") then
    echo "Running RTL build for sdma1_gc..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop)' -l sdma1_gc_rtl.log
    
else if ($tile_name == "all") then
    echo "Running RTL build for all tiles..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:osssys_dc_elab).build(:rhea_drop)' -l osssys_rtl.log
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:hdp_dc_elab).build(:rhea_drop)' -l hdp_rtl.log
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop)' -l sdma_rtl.log

else
    echo "ERROR: Unknown tile name: $tile_name"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

echo "RTL build execution completed"
