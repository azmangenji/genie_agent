
set report_path = "out/linux_3.10.0_64.VCS/*/config/*_dc_elab/pub/sim/publish/tiles/tile/*/cad/spg_dft/*/moresimple.rpt"
set error_extract_pl = "$source_dir/script/rtg_oss_feint/oss/spg_dft_error_extract.pl"
set error_filter = "$source_dir/script/rtg_oss_feint/oss/spg_dft_error_filter.txt"

if ($tile_name == all ) then
cat >> $source_dir/data/${tag}_spec << EOF
#text#
The spg_dft run has finished.Please check for error at logfile below.

EOF

 # Auto-discover tiles from DFT reports
 set tile_list = `ls $report_path | awk -F'/tile/' '{print $2}' | awk -F'/cad' '{print $1}' | sort -u`
 echo "Auto-discovered tiles: $tile_list"
 
 foreach ip1 ($tile_list)
    set look_for_rpt_spg_dft = `ls $report_path | grep $ip1 `
    set spg_rpt_path = "$refdir_name/$look_for_rpt_spg_dft"
    perl $error_extract_pl $spg_rpt_path $error_filter $ip1 >> $source_dir/data/${tag}_spec

    end


else 
    set look_for_rpt_spg_dft = `ls $report_path | grep $tile_name `
    set spg_rpt_path = "$refdir_name/$look_for_rpt_spg_dft"
cat >> $source_dir/data/${tag}_spec << EOF
#text#
The spg_dft run has finished.Please check for error at logfile below.

EOF

    perl $error_extract_pl $spg_rpt_path $error_filter $tile_name >> $source_dir/data/${tag}_spec


endif

