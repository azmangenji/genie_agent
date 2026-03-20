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

set error_filter = "$source_dir/script/rtg_oss_feint/umc/spg_dft_error_filter.txt"

set tile_count = `echo $tile_name |wc -w `
if ($tile_count == 0 ) then
    set tile_name = umc_top
    endif
    
set refdir_count = `echo $refdir_name |wc -w `
if ($refdir_count  == 0 ) then
  echo "refdir not defined , please include it"
  endif

  perl $source_dir/script/rtg_oss_feint/umc/static_check_summary.pl $refdir_name $tile_name $error_filter $refdir_name $ip_name >> $source_dir/data/${tag}_spec


cd $source_dir
set run_status = "finished"
source csh/env.csh
# updateTask.csh requires target_run_dir (set by TileBuilder scripts only)
# Skip it in CLI flow (tasksModelCLI.csv) to avoid "Undefined variable" crash
if ($tasksModelFile != "tasksModelCLI.csv") then
    source csh/updateTask.csh
endif

