source /tool/pandora/etc/lsf/cshrc.lsf
source /tool/site-config/cshrc
source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh


if ($tile_name == umc_top) then
    bootenv -x $ip_name
    setenv SPGDFT_CONFIG $STEM/src/meta/tools/spgdft/variant/$ip_name
    cd out/linux_3.10.0_64.VCS/$ip_name/config/umc_top_drop2cad/pub/sim/
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I compile_sglib.pl ; lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I run_spg_dft.pl
    cd $STEM
    source $source_dir/script/rtg_oss_feint/umc/spg_dft_analysis.csh
endif 

