

if ($tile_name == all) then
    bootenv -v orion
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -m 5 -x osssys_orion -e 'releaseflow::dropflow(:osssys_dc_elab).build(:rhea_drop)' -x hdp_orion -e 'releaseflow::dropflow(:hdp_dc_elab).build(:rhea_drop)' -l oss_all_rtl.log
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x sdma_orion -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop)' -DDROP_TOPS='sdma0_gc+sdma1_gc' -l sdma_all_rtl.log

cat >> $source_dir/data/${tag}_spec << EOF
#text#
 The rtl run for $tile_name tiles are done.
EOF
    
    if (-d all_tiles_rtl.log ) then
            rm -rf all_tiles_rtl.log
            endif
    cat oss_all_rtl.log >> all_tiles_rtl.log
    cat sdma_all_rtl.log >> all_tiles_rtl.log
    set failpass = `grep -A1 "Execution Summary" all_tiles_rtl.log | grep -v "Execution Summary" | grep rhea_drop|awk '{print $4}'|sort -u `
    if ($failpass == "PASSED") then
        echo "The RTL build at $refdir_name is PASSED"  >> $source_dir/data/${tag}_spec
    else 
        echo "The RTL build at $refdir_name is FAILED, please debug"  >> $source_dir/data/${tag}_spec
    endif
    
else

    if ($tile_name == sdma0_gc || $tile_name == sdma1_gc) then    
        bootenv -v orion
        lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x sdma_orion -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop)' -DDROP_TOPS="$tile_name" -l ${tile_name}_rtl.log
    else if ($tile_name == hdp) then 
        bootenv -v orion
        lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x hdp_orion -e 'releaseflow::dropflow(:hdp_dc_elab).build(:rhea_drop)' -DDROP_TOPS='hdp' -l hdp_rtl.log
    else if ($tile_name == osssys) then 
        bootenv -v orion
        lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x osssys_orion -e 'releaseflow::dropflow(:osssys_dc_elab).build(:rhea_drop)' -DDROP_TOPS='osssys' -l osssys_rtl.log
    endif



cat >> $source_dir/data/${tag}_spec << EOF
#text#
    The rtl run for $tile_name tiles are done.
EOF

    set logfile = `ls ${tile_name}_rtl.log`
    set failpass = `grep -A1 "Execution Summary" $logfile | grep -v "Execution Summary" | grep rhea_drop|awk '{print $4}'|sort -u`
    if ($failpass == "PASSED") then
        echo "The RTL build at $refdir_name is PASSED"  >> $source_dir/data/${tag}_spec
    else 
        echo "The RTL build at $refdir_name is FAILED, please debug"  >> $source_dir/data/${tag}_spec
    endif

endif
