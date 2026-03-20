source /tool/pandora/etc/lsf/cshrc.lsf
source /tool/site-config/cshrc
source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh




if ($tile_name == umc_top) then
    bootenv -x $ip_name
   lsf_bsub -P rtg-mcip-ver -R  "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:umc_top_drop2cad).build(:rhea_drop,:rhea_lint)' -l lint.log
    source $source_dir/script/rtg_oss_feint/umc/lint_analysis.csh
endif
