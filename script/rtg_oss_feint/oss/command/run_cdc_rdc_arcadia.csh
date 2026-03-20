#!/bin/tcsh
# OSS CDC/RDC execution wrapper for Arcadia (oss7_2)
# Called by static_check_command.csh
# Requires: $tile_name, $source_dir

echo "========================================="
echo "Running CDC/RDC checks for OSS (Arcadia)"
echo "Tile: $tile_name"
echo "========================================="

# Set Arcadia-specific environment
bootenv

# Execute CDC/RDC checks based on tile
if ($tile_name == "all") then
    echo "Running CDC/RDC checks for all tiles..."
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS="sdma0_gc+sdma1_gc" -l sdma_all_cdc_rdc.log
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS="osssys+lsdma0" -l oss1_all_cdc_rdc.log

else
    echo "Running CDC/RDC checks for ${tile_name}..."
    bootenv
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS="$tile_name" -l ${tile_name}_cdc_rdc.log

endif

echo "CDC/RDC execution completed"
