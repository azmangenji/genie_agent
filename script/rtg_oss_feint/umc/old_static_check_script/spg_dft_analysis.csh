
set report_path = "out/linux_3.10.0_64.VCS/*/config/*/pub/sim/publish/tiles/tile/*/cad/spg_dft/*/moresimple.rpt"
set error_extract_pl = "$source_dir/script/rtg_oss_feint/umc/spg_dft_error_extract.pl"
set error_filter = "$source_dir/script/rtg_oss_feint/umc/spg_dft_error_filter.txt"

if ($tile_name == umc_top ) then
    set look_for_rpt_spg_dft = `ls $report_path | grep $tile_name |grep -v bck`
    set spg_rpt_path = "$refdir_name/$look_for_rpt_spg_dft"
    perl $error_extract_pl $spg_rpt_path $error_filter $tile_name >> $source_dir/data/${tag}_spec
endif

