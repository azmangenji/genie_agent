#!/bin/tcsh
# OSS RTL build execution wrapper for Arcadia (oss7_2)
# Called by static_check_command.csh
# Requires: $tile_name, $source_dir, $tag

echo "========================================="
echo "Running RTL build for OSS (Arcadia)"
echo "Tile: $tile_name"
echo "========================================="

# Execute RTL build based on tile
if ($tile_name == "all") then
    echo "Running RTL build for all tiles..."
    bootenv
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop)' -DDROP_TOPS="osssys+lsdma0" -l oss_all_rtl.log
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop)' -DDROP_TOPS="sdma0_gc+sdma1_gc" -l sdma_all_rtl.log

    # Combine logs and check status
    if (-d all_tiles_rtl.log) then
        rm -rf all_tiles_rtl.log
    endif
    cat oss_all_rtl.log >> all_tiles_rtl.log
    cat sdma_all_rtl.log >> all_tiles_rtl.log

    set failpass = `grep -A1 "Execution Summary" all_tiles_rtl.log | grep -v "Execution Summary" | grep rhea_drop | awk '{print $4}' | sort -u`
    if ($failpass == "PASSED") then
        echo "The RTL build is PASSED"
    else
        echo "The RTL build is FAILED, please debug"
    endif

else
    echo "Running RTL build for ${tile_name}..."
    bootenv
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop)' -DDROP_TOPS="$tile_name" -l ${tile_name}_rtl.log

    # Check status
    set logfile = `ls ${tile_name}_rtl.log`
    set failpass = `grep -A1 "Execution Summary" $logfile | grep -v "Execution Summary" | grep rhea_drop | awk '{print $4}' | sort -u`
    if ($failpass == "PASSED") then
        echo "The RTL build is PASSED"
    else
        echo "The RTL build is FAILED, please debug"
    endif

endif

echo "RTL build execution completed"
