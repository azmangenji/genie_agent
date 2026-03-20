source /tool/pandora/etc/lsf/cshrc.lsf
source /tool/site-config/cshrc
source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh



if ($tile_name == ih_top) then
    bootenv -v osssys_orion
    lsf_bsub -P rtg-mcip-ver -R  "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop, :rhea_lint)' -DDROP_TOPS="ih_top" -l logs/ih_top_lint_agent.log -DRHEA_LINT_OPTS='-keep_db -gui -no_swan -tcl_waiver_file -tcl_waiver_path=$STEM/src/meta/waivers/lint/variant/orion' -m 8 -x ih_top
    source $source_dir/script/rtg_oss_feint/oss/lint_analysis.csh

else if ($tile_name == ih_sem_share) then
    bootenv -v osssys_orion
    lsf_bsub -P rtg-mcip-ver -R  "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop, :rhea_lint)' -DDROP_TOPS="ih_sem_share" -l sg_lint.log -DRHEA_LINT_OPTS='-keep_db -gui -no_swan -tcl_waiver_file -tcl_waiver_path=$STEM/src/meta/waivers/lint/variant/orion' -m 8 -x ih_sem_share
    source $source_dir/script/rtg_oss_feint/oss/lint_analysis.csh

else if ($tile_name == hdp) then
    bootenv -v hdp_orion
    lsf_bsub -P rtg-mcip-ver -R  "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop, :rhea_lint)' -DDROP_TOPS="hdp_core" -l sg_lint.log -DRHEA_LINT_OPTS='-keep_db -gui -no_swan -tcl_waiver_file -tcl_waiver_path=$STEM/src/meta/waivers/lint/variant/orion' -m 8 -x hdp_core
    source $source_dir/script/rtg_oss_feint/oss/lint_analysis.csh


else if ($tile_name == sdma0_gc) then
    bootenv -v orion
    lsf_bsub -P rtg-mcip-ver -R  "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop, :rhea_lint)' -DDROP_TOPS="sdma0_gc" -l sdma_lint.log -DRHEA_LINT_OPTS='-keep_db -gui -no_swan -tcl_waiver_file -tcl_waiver_path=$STEM/src/meta/waivers/lint/variant/orion' -m 8 
    source $source_dir/script/rtg_oss_feint/oss/lint_analysis.csh

else if ($tile_name == all) then
    bootenv -v osssys_orion
    lsf_bsub -P rtg-mcip-ver -R  "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop, :rhea_lint)' -DDROP_TOPS="ih_top" -l sg_lint.log -DRHEA_LINT_OPTS='-keep_db -gui -no_swan -tcl_waiver_file -tcl_waiver_path=$STEM/src/meta/waivers/lint/variant/orion' -m 8 -x ih_top
   bootenv -v osssys_orion    
   lsf_bsub -P rtg-mcip-ver -R  "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop, :rhea_lint)' -DDROP_TOPS="ih_sem_share" -l sg_lint.log -DRHEA_LINT_OPTS='-keep_db -gui -no_swan -tcl_waiver_file -tcl_waiver_path=$STEM/src/meta/waivers/lint/variant/orion' -m 8 -x ih_sem_share
    bootenv -v hdp_orion
    lsf_bsub -P rtg-mcip-ver -R  "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:oss_dc_elab).build(:rhea_drop, :rhea_lint)' -DDROP_TOPS="hdp_core" -l sg_lint.log -DRHEA_LINT_OPTS='-keep_db -gui -no_swan -tcl_waiver_file -tcl_waiver_path=$STEM/src/meta/waivers/lint/variant/orion' -m 8 -x hdp_core
    bootenv -v orion
    lsf_bsub -P rtg-mcip-ver -R  "select[type==RHEL7_64] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:sdma_dc_elab).build(:rhea_drop, :rhea_lint)' -DDROP_TOPS="sdma0_gc" -l sdma_lint.log -DRHEA_LINT_OPTS='-keep_db -gui -no_swan -tcl_waiver_file -tcl_waiver_path=$STEM/src/meta/waivers/lint/variant/orion' -m 8
    source $source_dir/script/rtg_oss_feint/oss/lint_analysis.csh
endif
