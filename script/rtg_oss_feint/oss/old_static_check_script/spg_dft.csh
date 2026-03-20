source /tool/pandora/etc/lsf/cshrc.lsf
source /tool/site-config/cshrc
source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh


if ($tile_name == osssys) then
    bootenv -v orion
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x osssys_orion  -e 'oss.top.osssys_spg_dft '  -l logs/osssys_spg_dft.log
    source $source_dir/script/rtg_oss_feint/oss/spg_dft_analysis.csh
endif 

if ($tile_name == hdp) then
    bootenv -v orion
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x hdp_orion -e 'oss.top.hdp_spg_dft ' -l logs/hdp_spg_dft.log
    source $source_dir/script/rtg_oss_feint/oss/spg_dft_analysis.csh
endif 


if ($tile_name == sdma0_gc || $tile_name == sdma1_gc ) then
    bootenv -v orion
   lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -m 5 -x sdma_orion -e 'oss.top.sdma_spg_dft ' -l logs/sdma_spg_dft_agent.log
    source $source_dir/script/rtg_oss_feint/oss/spg_dft_analysis.csh
endif 

if ($tile_name == all ) then
    bootenv -v orion
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -m 5 -x osssys_orion  -e 'oss.top.osssys_spg_dft ' -x hdp_orion -e 'oss.top.hdp_spg_dft ' -l logs/oss_spg_dft_agent.log
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -m 5 -x sdma_orion -e 'oss.top.sdma_spg_dft ' -l logs/sdma_spg_dft_agent.log
    source $source_dir/script/rtg_oss_feint/oss/spg_dft_analysis.csh
endif
