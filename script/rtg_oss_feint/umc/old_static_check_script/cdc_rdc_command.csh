# Created on Fri May 25 13:30:23 2023 @author: Simon Chen simon1.chen@amd.com
set refDir = $1
set ip = $2
set tile = $3
set CL = $4
set tag = $5
set p4File = $6
set source_dir = `pwd`
touch $source_dir/data/${tag}_spec


set refdir_name = `echo $refDir | sed 's/:/ /g' | awk '{$1="";print $0}'`
set ip_name = `echo $ip | sed 's/:/ /g' | awk '{$1="";print $0}'`
set tile_name = `echo $tile | sed 's/:/ /g' | awk '{$1="";print $0}'`
set CL_name = `echo $CL | sed 's/:/ /g' | awk '{$1="";print $0}'`
set p4file_name = `echo $p4File | sed 's/:/ /g' | awk '{$1="";print $0}'`

set tile_count = `echo $tile_name |wc -w `
if ($tile_count == 0 ) then
    set tile_name = umc_top
    endif

# Extract branch from P4 path if provided
set branch_name = ""
set p4file_count = `echo $p4file_name | wc -w`
if ($p4file_count > 0) then
    # Example: //depot/umc_ip/branches/UMC_14_2_WHLP_BRANCH/...
    # Extract: UMC_14_2_WHLP_BRANCH
    set branch_name = `echo $p4file_name | grep -o 'branches/[^/]*' | sed 's/branches\///'`
    
    if ("$branch_name" != "") then
        echo "Detected branch from P4 path: $branch_name"
        echo "P4 file path: $p4file_name"
    endif
endif
    
set refdir_count = `echo $refdir_name |wc -w `
if ($refdir_count  == 0 ) then 
     # No refdir provided - create new work directory
     set disk = `python3 $source_dir/script/read_csv.py --csv $source_dir/assignment.csv | grep "^disk," | awk -F "," '{print $2}' | sed 's/\r//g'`
     cd $disk
     setenv TZ 'Asia/Kuala_Lumpur'
     set date = `date | awk '{print $2 $3 $4 }' | sed  's/://g'`
    unsetenv TZ
     set assignment_file = "${source_dir}/assignment.csv"
     set project_name = `grep "^projectStaticCheck," $assignment_file | awk -F',' '{print $2}'`
     set path_work = "umc_${project_name}_${date}"

        if (-d $path_work) then
            rm -rf $path_work
            endif 
                mkdir $path_work
                cd $path_work
                source $source_dir/script/rtg_oss_feint/lsf.csh
                set CL_count = `echo $CL_name | wc -w`
                    
                    # Priority 1: Use branch from p4File if provided
                    if ("$branch_name" != "") then
                        echo "Using branch from P4 file: $branch_name"
                        if ($CL_count == 0 ) then 
                            p4_mkwa -codeline umc_ip -branch $branch_name -wacfg er
                        else if ($CL_count == 1 ) then
                            p4_mkwa -codeline umc_ip -branch $branch_name -wacfg er -changelist $CL_name
                        else 
                            echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                        endif
                    
                    # Priority 2: Special handling for umc9_2 IP
                    else if ("$ip_name" == "umc9_2") then
                        echo "Using UMC 9.2 default branch"
                        if ($CL_count == 0 ) then 
                            p4_mkwa -codeline umc_ip -wacfg er -branch UMC_9_2_WEISSHORN_TRUNK
                        else if ($CL_count == 1 ) then
                            p4_mkwa -codeline umc_ip -wacfg er -branch UMC_9_2_WEISSHORN_TRUNK -changelist $CL_name
                        else 
                            echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                        endif
                    
                    # Priority 3: Default (no branch specified)
                    else
                        echo "Using default branch"
                        if ($CL_count == 0 ) then 
                            p4_mkwa -codeline umc_ip -wacfg er
                        else if ($CL_count == 1 ) then
                            p4_mkwa -codeline umc_ip -wacfg er -changelist $CL_name
                        else 
                            echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                        endif
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
         # Already synced, use it
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
             set path_work = "umc_${project_name}_${date}"
             
             if (-d $path_work) then
                 rm -rf $path_work
             endif
             mkdir $path_work
             cd $path_work
             source $source_dir/script/rtg_oss_feint/lsf.csh
             set CL_count = `echo $CL_name | wc -w`
             
             # Priority 1: Use branch from p4File if provided
             if ("$branch_name" != "") then
                 echo "Using branch from P4 file: $branch_name"
                 if ($CL_count == 0 ) then 
                     p4_mkwa -codeline umc_ip -branch $branch_name -wacfg er
                 else if ($CL_count == 1 ) then
                     p4_mkwa -codeline umc_ip -branch $branch_name -wacfg er -changelist $CL_name
                 else 
                     echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                 endif
             
             # Priority 2: Special handling for umc9_2 IP
             else if ("$ip_name" == "umc9_2") then
                 echo "Using UMC 9.2 default branch"
                 if ($CL_count == 0 ) then 
                     p4_mkwa -codeline umc_ip -wacfg er -branch UMC_9_2_WEISSHORN_TRUNK
                 else if ($CL_count == 1 ) then
                     p4_mkwa -codeline umc_ip -wacfg er -branch UMC_9_2_WEISSHORN_TRUNK -changelist $CL_name
                 else 
                     echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                 endif
             
             # Priority 3: Default (no branch specified)
             else
                 echo "Using default branch"
                 if ($CL_count == 0 ) then 
                     p4_mkwa -codeline umc_ip -wacfg er
                 else if ($CL_count == 1 ) then
                     p4_mkwa -codeline umc_ip -wacfg er -changelist $CL_name
                 else 
                     echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                 endif
             endif
             
             set refdir_name = "${refdir_name}/${path_work}"
         else
             # Directory is empty - run p4_mkwa directly
             echo "Directory is empty - running p4_mkwa"
             cd $refdir_name
             source $source_dir/script/rtg_oss_feint/lsf.csh
             set CL_count = `echo $CL_name | wc -w`
             
             # Priority 1: Use branch from p4File if provided
             if ("$branch_name" != "") then
                 echo "Using branch from P4 file: $branch_name"
                 if ($CL_count == 0 ) then 
                     p4_mkwa -codeline umc_ip -branch $branch_name -wacfg er
                 else if ($CL_count == 1 ) then
                     p4_mkwa -codeline umc_ip -branch $branch_name -wacfg er -changelist $CL_name
                 else 
                     echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                 endif
             
             # Priority 2: Special handling for umc9_2 IP
             else if ("$ip_name" == "umc9_2") then
                 echo "Using UMC 9.2 default branch"
                 if ($CL_count == 0 ) then 
                     p4_mkwa -codeline umc_ip -wacfg er -branch UMC_9_2_WEISSHORN_TRUNK
                 else if ($CL_count == 1 ) then
                     p4_mkwa -codeline umc_ip -wacfg er -branch UMC_9_2_WEISSHORN_TRUNK -changelist $CL_name
                 else 
                     echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                 endif
             
             # Priority 3: Default (no branch specified)
             else
                 echo "Using default branch"
                 if ($CL_count == 0 ) then 
                     p4_mkwa -codeline umc_ip -wacfg er
                 else if ($CL_count == 1 ) then
                     p4_mkwa -codeline umc_ip -wacfg er -changelist $CL_name
                 else 
                     echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                 endif
             endif
         endif
     endif
endif

cd $refdir_name


source $source_dir/script/rtg_oss_feint/umc/cdc_rdc.csh
echo "CDC_RDC is running"



cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
