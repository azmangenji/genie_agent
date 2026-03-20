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

set tile_count = `echo $tile_name |wc -w `
if ($tile_count == 0 ) then
    set tile_name = all
    endif
    
set refdir_count = `echo $refdir_name |wc -w `
if ($refdir_count  == 0 ) then 
     set disk = `python3 $source_dir/script/read_csv.py --csv $source_dir/assignment.csv | grep "^disk," | awk -F "," '{print $2}' | sed 's/\r//g'`
     cd $disk
     setenv TZ 'Asia/Kuala_Lumpur'
     set date = `date | awk '{print $2 $3 $4 }' | sed  's/://g'`
     unsetenv TZ
     set assignment_file = "${source_dir}/assignment.csv"
     set project_name = `grep "^projectStaticCheck," $assignment_file | awk -F',' '{print $2}'`
     set path_work = "oss8_0_${project_name}_${date}"

        if (-d $path_work) then
            rm -rf $path_work
            endif 
                mkdir $path_work
                cd $path_work
                source $source_dir/script/rtg_oss_feint/lsf.csh
                set CL_count = `echo $CL_name | wc -w`
                    if ($CL_count == 0 ) then 
                        p4_mkwa -codeline oss8_0
                    else if ($CL_count == 1 ) then
                        p4_mkwa -codeline oss8_0 -changelist $CL_name
                    else 
                         echo "Something wrong with p4_mkwa command" >> $source_dir/data/${tag}_spec
                    endif

                        set refdir_name = $disk/$path_work
else
     # Refdir provided - check if it's a synced tree or empty directory
     echo "Checking provided directory: $refdir_name"
     
     if (! -d $refdir_name) then
         echo "ERROR: Directory not found: $refdir_name"
     endif
     
     # Check if directory is a synced tree (has configuration_id file)
     if (-f "${refdir_name}/configuration_id") then
         echo "Directory is a synced tree - using as-is"
     else
         # Not a synced tree - check if directory has content
         set dir_content = `ls -A $refdir_name | wc -l`
         
         if ($dir_content > 0) then
             # Directory has content - create subdirectory
             echo "Directory has content - creating subdirectory"
             cd $refdir_name
             setenv TZ 'Asia/Kuala_Lumpur'
             set date = `date | awk '{print $2 $3 $4 }' | sed 's/://g'`
             unsetenv TZ
             set assignment_file = "${source_dir}/assignment.csv"
             set project_name = `grep "^projectStaticCheck," $assignment_file | awk -F',' '{print $2}'`
             set path_work = "oss8_0_${project_name}_${date}"
             
             if (-d $path_work) then
                 rm -rf $path_work
             endif
             mkdir $path_work
             cd $path_work
             source $source_dir/script/rtg_oss_feint/lsf.csh
             set CL_count = `echo $CL_name | wc -w`
             if ($CL_count == 0 ) then 
                 p4_mkwa -codeline oss8_0
             else if ($CL_count == 1 ) then
                 p4_mkwa -codeline oss8_0 -changelist $CL_name
             else 
                 echo "Something wrong with p4_mkwa command" >> $source_dir/data/${tag}_spec
             endif
             
             set refdir_name = "${refdir_name}/${path_work}"
         else
             # Directory is empty - run p4_mkwa directly
             echo "Directory is empty - running p4_mkwa"
             cd $refdir_name
             source $source_dir/script/rtg_oss_feint/lsf.csh
             set CL_count = `echo $CL_name | wc -w`
             if ($CL_count == 0 ) then 
                 p4_mkwa -codeline oss8_0
             else if ($CL_count == 1 ) then
                 p4_mkwa -codeline oss8_0 -changelist $CL_name
             else 
                 echo "Something wrong with p4_mkwa command" >> $source_dir/data/${tag}_spec
             endif
         endif
     endif
endif

cd $refdir_name


source $source_dir/script/cdc_rdc.csh
source $source_dir/script/lint_command.csh
source $source_dir/script/spg_dft_command.csh



cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
