set refDir = $1
set ip = $2
set tile = $3
set CL = $4
set tag = $5
set source_dir = `pwd`
touch $source_dir/data/${tag}_spec

set refdir_name = `echo $refDir | sed 's/:/ /g' | awk '{$1="";print $0}'`

set cl_number = `cat $refdir_name/configuration_id | sed 's;@; ;g' | awk '{print $2}'`

cat >> $source_dir/data/${tag}_spec << EOF
#text#

The configuration id/changelist number is $cl_number .

EOF

cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
