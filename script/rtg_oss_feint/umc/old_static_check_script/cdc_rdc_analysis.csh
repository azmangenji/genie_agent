set report_path_cdc = "out/linux_3.10.0_64.VCS/*/config/*/pub/sim/publish/tiles/tile/*/cad/rhea_cdc/cdc_*_output/cdc_report.rpt"
set report_path_rdc = "out/linux_3.10.0_64.VCS/*/config/*/pub/sim/publish/tiles/tile/*/cad/rhea_cdc/rdc_*_output/rdc_report.rpt"

if ($tile_name == umc_top) then
    set look_for_rpt_cdc = `ls $report_path_cdc |grep $tile_name|grep -v bck`
    set look_for_rpt_rdc = `ls $report_path_rdc |grep $tile_name|grep -v bck`
    set cdc_rpt_path = "$refdir_name/$look_for_rpt_cdc"
    set rdc_rpt_path = "$refdir_name/$look_for_rpt_rdc"
    perl $source_dir/script/rtg_oss_feint/umc/cdc_rdc_extract_violation.pl $cdc_rpt_path $rdc_rpt_path $tile_name >> $source_dir/data/${tag}_spec
endif
