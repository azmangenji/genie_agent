set refDir = $1
set ip = $2
set tile = $3
set tag = $4
set source_dir = `pwd`
set waiver_path = src/meta/tools/cdc0in/oss.0in_waiver.tcl
touch $source_dir/data/${tag}_spec

##flow to update constraint >> rerun cdc_rdc

set refdir_name = `echo $refDir | sed 's/:/ /g' | awk '{$1="";print $0}'`
set ip_name = `echo $ip | sed 's/:/ /g' | awk '{$1="";print $0}'`
set tile_name = `echo $tile | sed 's/:/ /g' | awk '{$1="";print $0}'`

set tile_count = `echo $tile_name |wc -w `
set ip_count = `echo $ip_name |wc -w `
set refdir_count = `echo $refdir_name |wc -w `
    if ($tile_count == 0  && $ip_count == 0 && $refdir_count == 0 ) then
        echo "You didnt specified tiles and ip and the path to update ,Please specify before continuing " >> $source_dir/data/${tag}_spec
        set run_status = "failed"
    endif 


set full_waiver_path = $refdir_name/$waiver_path
cd $refdir_name
p4 edit $waiver_path

echo "# found param file: $source_dir/data/$tag.params"
    set n_constraint = `cat $source_dir/data/$tag.params | wc -w`
    if ($n_constraint > 0) then
        sed -i 's;CDC_WAIVER = ;;g' $source_dir/data/$tag.params
        sed -i 's;RDC_WAIVER = ;;g' $source_dir/data/$tag.params
        cat $source_dir/data/$tag.params >> $full_waiver_path
        set update_params = `cat $source_dir/data/$tag.params | sed 's/\\//g' | sed 's/{//g' | sed 's/}//g'`
cat >> $source_dir/data/${tag}_spec << EOF
#list#
The waiver has been updated:
#table#
Directory,waiver
EOF

echo "$full_waiver_path,$update_params" >> $source_dir/data/${tag}_spec
echo "#table end#" >> $source_dir/data/${tag}_spec


        else 
        echo "Update params failed"
        set run_status = "failed"
    endif



source $source_dir/script/rtg_oss_feint/oss/cdc_rdc.csh
echo "CDC_RDC is running"




cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
