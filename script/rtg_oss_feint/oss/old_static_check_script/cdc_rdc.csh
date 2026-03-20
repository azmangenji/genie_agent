source /tool/pandora/etc/lsf/cshrc.lsf
source /tool/site-config/cshrc
source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh



if ($tile_name == osssys) then
    bootenv -v orion
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x osssys_orion -e 'releaseflow::dropflow(:osssys_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='osssys' -l logs/osssys_cdc_agent.log
source $source_dir/script/rtg_oss_feint/oss/cdc_rdc_analysis.csh

else if ($tile_name == hdp) then
    bootenv -v orion
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x hdp_orion    -e 'releaseflow::dropflow(:hdp_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='hdp'
source $source_dir/script/rtg_oss_feint/oss/cdc_rdc_analysis.csh

else if ($tile_name == sdma0_gc) then
    bootenv -v orion
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x sdma_orion   -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='sdma0_gc'
source $source_dir/script/rtg_oss_feint/oss/cdc_rdc_analysis.csh

else if ($tile_name == sdma1_gc) then
    bootenv -v orion
    lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x sdma_orion   -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='sdma1_gc' 
source $source_dir/script/rtg_oss_feint/oss/cdc_rdc_analysis.csh


else if ($tile_name == all) then  
   bootenv -v orion
   lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x sdma_orion   -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS="sdma1_gc"
   lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x sdma_orion   -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS="sdma0_gc"
  lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x hdp_orion    -e 'releaseflow::dropflow(:hdp_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='hdp'
   lsf_bsub -P rtg-mcip-ver -R "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -x osssys_orion -e 'releaseflow::dropflow(:osssys_dc_elab).build(:rhea_drop,:rhea_cdc)' -DDROP_TOPS='osssys' -l logs/osssys_cdc_agent.log
source $source_dir/script/rtg_oss_feint/oss/cdc_rdc_analysis.csh


endif

