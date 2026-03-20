

if ($tile_name == umc_top) then
        bootenv -v $ip_name
        lsf_bsub -P rtg-mcip-ver -R  "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:umc_top_drop2cad).build(:rhea_drop)' -l ${tile_name}_rtl.log



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
