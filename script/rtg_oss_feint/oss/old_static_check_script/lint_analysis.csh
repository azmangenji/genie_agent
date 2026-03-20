set report_path = "out/linux_3.10.0_64.VCS/*/config/*_dc_elab/pub/sim/publish/tiles/tile/*/cad/rhea_lint/report_vc_spyglass_lint.txt"


if ($tile_name == all) then

cat >> $source_dir/data/${tag}_spec << EOF
#text#
The lint run has finished.Please check for total error below.
EOF

    # Auto-discover tiles from lint reports
    set tile_list = `ls $report_path | awk -F'/tile/' '{print $2}' | awk -F'/cad' '{print $1}' | sort -u`
    echo "Auto-discovered tiles: $tile_list"
    
    foreach ip1 ($tile_list)
        set look_for_rpt_lint = `ls $report_path | grep $ip1 `
        set report_path_full = "$refdir_name/$look_for_rpt_lint"
        perl $source_dir/script/rtg_oss_feint/oss/lint_error_extract.pl $report_path_full $ip1 >> $source_dir/data/${tag}_spec 

        end

else


    set look_for_rpt_lint = `ls $report_path | grep $tile_name `
    set lint_report_path = "$refdir_name/$look_for_rpt_lint"


cat >> $source_dir/data/${tag}_spec << EOF
#text#
The lint run has finished.Please check for total error below.

EOF

    perl $source_dir/script/rtg_oss_feint/oss/lint_error_extract.pl $lint_report_path $tile_name >> $source_dir/data/${tag}_spec 


endif

