#!/bin/tcsh
# GMC Static Check Summary wrapper script
# Usage: static_check_summary.csh <refDir> <ip> <tile> <CL> <tag>

set refDir = $1
set ip = $2
set tile = $3
set CL = $4
set tag = $5
set source_dir = `pwd`
touch $source_dir/data/${tag}_spec

set refdir_name = `echo $refDir | sed 's/:/ /g' | awk '{$1="";print $0}'`
set ip_name = `echo $ip | sed 's/:/ /g' | awk '{$1="";print $0}'`
set tile_name = `echo $tile | sed 's/:/ /g' | awk '{$1="";print $0}'`
set CL_name = `echo $CL | sed 's/:/ /g' | awk '{$1="";print $0}'`

set error_filter = "$source_dir/script/rtg_oss_feint/gmc/spg_dft_error_filter.txt"

# Handle tile parameter - supports:
#   - Empty/not specified: defaults to "all" (both gmc_gmcctrl_t + gmc_gmcch_t)
#   - "all": both tiles
#   - Single tile: "gmc_gmcctrl_t" or "gmc_gmcch_t"
#   - Both tiles: "gmc_gmcctrl_t+gmc_gmcch_t" or "gmc_gmcctrl_t gmc_gmcch_t"
set tile_count = `echo $tile_name | wc -w`
if ($tile_count == 0) then
    set tile_name = "all"
    echo "No tile specified - defaulting to both tiles (gmc_gmcctrl_t + gmc_gmcch_t)"
else
    echo "Using specified tile(s): $tile_name"
endif

set refdir_count = `echo $refdir_name | wc -w`
if ($refdir_count == 0) then
    echo "ERROR: refdir not defined, please include it" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

perl $source_dir/script/rtg_oss_feint/gmc/static_check_summary.pl $refdir_name $tile_name $error_filter $refdir_name $ip_name >> $source_dir/data/${tag}_spec

cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
