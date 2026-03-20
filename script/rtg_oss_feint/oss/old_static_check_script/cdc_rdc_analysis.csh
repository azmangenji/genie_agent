set report_path_cdc = "out/linux_3.10.0_64.VCS/*/config/*_dc_elab/pub/sim/publish/tiles/tile/*/cad/rhea_cdc/cdc_*_output/cdc_report.rpt"
set report_path_rdc = "out/linux_3.10.0_64.VCS/*/config/*_dc_elab/pub/sim/publish/tiles/tile/*/cad/rhea_cdc/rdc_*_output/rdc_report.rpt"

if ($tile_name == all) then


cat >> $source_dir/data/${tag}_spec << EOF
#text#
The cdc/rdc run has finished.Please check violation/inferred clock below.
EOF


 # Auto-discover tiles from CDC reports
 set tile_list = `ls $report_path_cdc | sed 's/.*\/tile\///' | sed 's/\/cad.*//' | sort -u`
 echo "Auto-discovered tiles: $tile_list"
 
 foreach ip1 ($tile_list)
    set look_for_rpt_cdc = `ls $report_path_cdc |grep $ip1`
    set look_for_rpt_rdc = `ls $report_path_rdc |grep $ip1`
    set cdc_rpt_path = "$refdir_name/$look_for_rpt_cdc"
    set rdc_rpt_path = "$refdir_name/$look_for_rpt_rdc"
    perl $source_dir/script/rtg_oss_feint/oss/cdc_rdc_extract_violation.pl $cdc_rpt_path $rdc_rpt_path $ip1 >> $source_dir/data/${tag}_spec

end

else

cat >> $source_dir/data/${tag}_spec << EOF
#text#
The cdc/rdc run has finished.Please check violation/inferred clock below.
EOF


    set look_for_rpt_cdc = `ls $report_path_cdc |grep $tile_name`
    set look_for_rpt_rdc = `ls $report_path_rdc |grep $tile_name`
    set cdc_rpt_path = "$refdir_name/$look_for_rpt_cdc"
    set rdc_rpt_path = "$refdir_name/$look_for_rpt_rdc"
 perl $source_dir/script/rtg_oss_feint/oss/cdc_rdc_extract_violation.pl $cdc_rpt_path $rdc_rpt_path $tile_name >> $source_dir/data/${tag}_spec

endif
