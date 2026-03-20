set report_path = "out/linux_3.10.0_64.VCS/*/config/*/pub/sim/publish/tiles/tile/*/cad/rhea_lint/leda_waiver.log"
set look_for_rpt_lint = `ls $report_path | grep $tile_name `
set lint_report_path = "$refdir_name/$look_for_rpt_lint"

perl $source_dir/script/rtg_oss_feint/umc/lint_error_extract.pl $lint_report_path $tile_name >> $source_dir/data/${tag}_spec



