#!/bin/tcsh
# OSS Lint execution wrapper for Arcadia (oss7_2)
# Called by static_check_command.csh
# Requires: $tile_name, $source_dir

echo "========================================="
echo "Running Lint checks for OSS (Arcadia)"
echo "Tile: $tile_name"
echo "========================================="

# Execute Lint checks based on tile
if ($tile_name == "all") then
    echo "Running Lint checks for all tiles..."
    bootenv
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -m 8 -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop,:rhea_lint)' -DDROP_TOPS="ih_sem_share+ih_top+lsdma0_body" -DRHEA_LINT_OPTS='-keep_db -gui -no_swan -tcl_waiver_file -tcl_waiver_path=$STEM/src/meta/waivers/lint/variant/arcadia' -l oss_lint.log
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -m 8 -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop,:rhea_lint)' -DDROP_TOPS="dma_body_gc" -DRHEA_LINT_OPTS='-keep_db -gui -no_swan -tcl_waiver_file -tcl_waiver_path=$STEM/src/meta/waivers/lint/variant/arcadia' -l sdma_lint.log

else
    echo "Running Lint checks for ${tile_name}..."
    bootenv
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -m 8 -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop,:rhea_lint)' -DDROP_TOPS="$tile_name" -DRHEA_LINT_OPTS='-keep_db -gui -no_swan -tcl_waiver_file -tcl_waiver_path=$STEM/src/meta/waivers/lint/variant/arcadia' -l ${tile_name}_lint.log

endif

echo "Lint execution completed"
