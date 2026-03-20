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

set error_filter = "$source_dir/script/rtg_oss_feint/oss/spg_dft_error_filter.txt"

set tile_count = `echo $tile_name |wc -w `
if ($tile_count == 0 ) then
    set tile_name = all
endif
    
set refdir_count = `echo $refdir_name |wc -w `
if ($refdir_count  == 0 ) then
    echo "refdir not defined , please include it"
endif

# Handle tile processing
if ($tile_name == all) then
    # Process all OSS tiles
    foreach ip1 (sdma0_gc osssys lsdma0 hdp)
        perl $source_dir/script/rtg_oss_feint/oss/static_check_summary.pl $refdir_name $ip1 $error_filter $refdir_name >> $source_dir/data/${tag}_spec
    end
else
    perl $source_dir/script/rtg_oss_feint/oss/static_check_summary.pl $refdir_name $tile_name $error_filter $refdir_name >> $source_dir/data/${tag}_spec
endif


cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
