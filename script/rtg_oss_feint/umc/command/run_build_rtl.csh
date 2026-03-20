#!/bin/tcsh
# RTL build command

# Get RHEL version for LSF resource selection
source $source_dir/script/rtg_oss_feint/get_rhel_version.csh

lsf_bsub -P rtg-mcip-ver -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" -q normal -I dj -c -v -e 'releaseflow::dropflow(:umc_top_drop2cad).build(:rhea_drop)' -l ${tile_name}_rtl.log
