#!/bin/tcsh
# OSS Spyglass DFT execution wrapper for Arcadia (oss7_2)
# Called by static_check_command.csh
# Requires: $tile_name, $source_dir

echo "========================================="
echo "Running Spyglass DFT checks for OSS (Arcadia)"
echo "Tile: $tile_name"
echo "========================================="

# Execute Spyglass DFT checks based on tile
if ($tile_name == "all") then
    echo "Running Spyglass DFT checks for all tiles..."
    bootenv
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop, :spg_dft)' -DDROP_TOPS="osssys+lsdma0" -l oss_spg_dft.log
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop, :spg_dft)' -DDROP_TOPS="sdma0_gc+sdma1_gc" -l sdma_spg_dft.log

else
    echo "Running Spyglass DFT checks for ${tile_name}..."
    bootenv
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop, :spg_dft)' -DDROP_TOPS="$tile_name" -l ${tile_name}_spg_dft.log

endif

echo "Spyglass DFT execution completed"
