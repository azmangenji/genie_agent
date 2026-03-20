#!/bin/tcsh
# GMC Static Check - Main entry point
# Usage: static_check.csh <refDir> <ip> <tile> <CL> <tag> <p4File> <checkType>

set refDir = $1
set ip = $2
set tile = $3
set CL = $4
set tag = $5
set p4File = $6
set checkType = $7
set source_dir = `pwd`
touch $source_dir/data/${tag}_spec

# Parse parameters
set refdir_name = `echo $refDir | sed 's/:/ /g' | awk '{$1="";print $0}'`
set ip_name = `echo $ip | sed 's/:/ /g' | awk '{$1="";print $0}'`
set tile_name = `echo $tile | sed 's/:/ /g' | awk '{$1="";print $0}'`
set CL_name = `echo $CL | sed 's/:/ /g' | awk '{$1="";print $0}'`
set p4file_name = `echo $p4File | sed 's/:/ /g' | awk '{$1="";print $0}'`
set checktype_name = `echo $checkType | sed 's/:/ /g' | awk '{$1="";print $0}'`

# Note: GMC commands run both tiles (gmc_gmcch_t + gmc_gmcctrl_t) automatically via DROP_TOPS
# No default tile needed

# Extract branch from P4 path if provided
set branch_name = ""
set p4file_count = `echo $p4file_name | wc -w`
if ($p4file_count > 0) then
    set branch_name = `echo $p4file_name | grep -o 'branches/[^/]*' | sed 's/branches\///'`
    if ("$branch_name" != "") then
        echo "Detected branch from P4 path: $branch_name"
        echo "P4 file path: $p4file_name"
    endif
endif

# Determine project name from project.list
set project_list_file = "${source_dir}/script/rtg_oss_feint/project.list"
set project_name = ""

# Check if project.list exists
if (! -f $project_list_file) then
    echo "ERROR: Project list file not found: $project_list_file"
    cat >> $source_dir/data/${tag}_spec << EOF
#text#
 ERROR: Project list file not found
 Please create ${project_list_file} with format: <ip>,<project_name>
EOF
    exit 1
endif

# Check if IP name is provided
if ("$ip_name" == "") then
    echo "ERROR: IP name parameter is required"
    cat >> $source_dir/data/${tag}_spec << EOF
#text#
 ERROR: IP name parameter is required
 Please provide IP parameter (e.g., ip:gmc13_1a)
EOF
    exit 1
endif

# Look up project name based on IP in project.list
set project_name = `grep "^${ip_name}," $project_list_file | head -1 | awk -F',' '{print $2}' | sed 's/\r//g'`

if ("$project_name" == "") then
    echo "ERROR: IP '${ip_name}' not found in project.list"
    cat >> $source_dir/data/${tag}_spec << EOF
#text#
 ERROR: IP '${ip_name}' not found in project.list
 Please add entry to ${project_list_file} with format: ${ip_name},<project_name>
EOF
    exit 1
else
    echo "Using project name from project.list for ${ip_name}: $project_name"
endif

# Workspace creation logic
set refdir_count = `echo $refdir_name | wc -w`
if ($refdir_count == 0) then
    # No refdir - create new workspace
    set disk = `python3 $source_dir/script/read_csv.py --csv $source_dir/assignment.csv | grep "^disk," | awk -F "," '{print $2}' | sed 's/\r//g'`
    cd $disk
    setenv TZ 'Asia/Kuala_Lumpur'
    set date = `date | awk '{print $2 $3 $4 }' | sed 's/://g'`
    unsetenv TZ
    set path_work = "gmc_${project_name}_${date}"

    if (-d $path_work) then
        rm -rf $path_work
    endif
    mkdir $path_work
    cd $path_work
    source $source_dir/script/rtg_oss_feint/lsf.csh
    set CL_count = `echo $CL_name | wc -w`

    # GMC uses codeline umc4
    if ("$branch_name" != "") then
        echo "Using branch from P4 file: $branch_name"
        if ($CL_count == 0) then
            p4_mkwa -codeline umc4 -branch $branch_name -wacfg er
        else if ($CL_count == 1) then
            p4_mkwa -codeline umc4 -branch $branch_name -wacfg er -changelist $CL_name
        else
            echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
        endif
    else
        echo "Using default branch (trunk)"
        if ($CL_count == 0) then
            p4_mkwa -codeline umc4 -wacfg er
        else if ($CL_count == 1) then
            p4_mkwa -codeline umc4 -wacfg er -changelist $CL_name
        else
            echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
        endif
    endif

    set refdir_name = $disk/$path_work
else
    # Refdir provided - check if synced/has content/empty
    echo "Checking provided directory: $refdir_name"

    if (! -d $refdir_name) then
        echo "ERROR: Directory not found: $refdir_name"
    endif

    if (-f "${refdir_name}/configuration_id") then
        echo "Directory is a synced tree - using as-is"
    else
        set dir_content = `ls -A $refdir_name | wc -l`

        if ($dir_content > 0) then
            # Has content - create subdirectory
            echo "Directory has content - creating subdirectory"
            cd $refdir_name
            setenv TZ 'Asia/Kuala_Lumpur'
            set date = `date | awk '{print $2 $3 $4 }' | sed 's/://g'`
            unsetenv TZ
            set path_work = "gmc_${project_name}_${date}"

            if (-d $path_work) then
                rm -rf $path_work
            endif
            mkdir $path_work
            cd $path_work
            source $source_dir/script/rtg_oss_feint/lsf.csh
            set CL_count = `echo $CL_name | wc -w`

            # GMC uses codeline umc4
            if ("$branch_name" != "") then
                echo "Using branch from P4 file: $branch_name"
                if ($CL_count == 0) then
                    p4_mkwa -codeline umc4 -branch $branch_name -wacfg er
                else if ($CL_count == 1) then
                    p4_mkwa -codeline umc4 -branch $branch_name -wacfg er -changelist $CL_name
                else
                    echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                endif
            else
                echo "Using default branch (trunk)"
                if ($CL_count == 0) then
                    p4_mkwa -codeline umc4 -wacfg er
                else if ($CL_count == 1) then
                    p4_mkwa -codeline umc4 -wacfg er -changelist $CL_name
                else
                    echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                endif
            endif

            set refdir_name = "${refdir_name}/${path_work}"
        else
            # Empty directory
            echo "Directory is empty - running p4_mkwa"
            cd $refdir_name
            source $source_dir/script/rtg_oss_feint/lsf.csh
            set CL_count = `echo $CL_name | wc -w`

            # GMC uses codeline umc4
            if ("$branch_name" != "") then
                echo "Using branch from P4 file: $branch_name"
                if ($CL_count == 0) then
                    p4_mkwa -codeline umc4 -branch $branch_name -wacfg er
                else if ($CL_count == 1) then
                    p4_mkwa -codeline umc4 -branch $branch_name -wacfg er -changelist $CL_name
                else
                    echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                endif
            else
                echo "Using default branch (trunk)"
                if ($CL_count == 0) then
                    p4_mkwa -codeline umc4 -wacfg er
                else if ($CL_count == 1) then
                    p4_mkwa -codeline umc4 -wacfg er -changelist $CL_name
                else
                    echo "ERROR: Multiple changelists provided" >> $source_dir/data/${tag}_spec
                endif
            endif
        endif
    endif
endif

# Verify sync success
echo "========================================="
echo "Verifying workspace sync..."
echo "========================================="

set sync_success = 0
set p4_mkwa_ok = 0
set config_id_ok = 0

# Check if P4_MKWA.log exists and contains "All syncs OK!"
if (-f "${refdir_name}/P4_MKWA.log") then
    set sync_ok_check = `grep -c "All syncs OK!" "${refdir_name}/P4_MKWA.log"`
    if ($sync_ok_check > 0) then
        set p4_mkwa_ok = 1
    endif
endif

# Check if configuration_id file exists
if (-f "${refdir_name}/configuration_id") then
    set config_id_ok = 1
endif

# Both must pass for sync success
if ($p4_mkwa_ok == 1 && $config_id_ok == 1) then
    set sync_success = 1
    echo "Workspace sync verification PASSED"
else
    echo "========================================="
    echo "Workspace sync verification FAILED"
    echo "========================================="

    # Report specific failures
    if ($p4_mkwa_ok == 0) then
        if (! -f "${refdir_name}/P4_MKWA.log") then
            echo "ERROR: P4_MKWA.log not found"
        else
            echo "ERROR: 'All syncs OK!' not found in P4_MKWA.log"
        endif
    endif

    if ($config_id_ok == 0) then
        echo "ERROR: configuration_id file not found"
    endif

    echo "ERROR: Cannot proceed with static checks - sync verification failed"

    # Extract failed component syncs from P4_MKWA.log
    set failed_count = 0
    if (-f "${refdir_name}/P4_MKWA.log") then
        set failed_count = `grep -c "ERROR: sync of component" "${refdir_name}/P4_MKWA.log"`
        if ($failed_count > 0) then
            echo ""
            echo "Failed component syncs ($failed_count):"
            grep "ERROR: sync of component" "${refdir_name}/P4_MKWA.log" | head -20
        endif
    endif

    # Write detailed error to data spec
    cat >> $source_dir/data/${tag}_spec << EOF
#text#
Workspace sync verification: FAILED
Directory: $refdir_name

EOF

    # Add failed components to spec
    if ($failed_count > 0) then
        echo "Failed Component Syncs ($failed_count):" >> $source_dir/data/${tag}_spec
        echo "----------------------------------------" >> $source_dir/data/${tag}_spec
        grep "ERROR: sync of component" "${refdir_name}/P4_MKWA.log" >> $source_dir/data/${tag}_spec
        echo "" >> $source_dir/data/${tag}_spec
        echo "Check detailed logs at: ${refdir_name}/_env/.<component>.sync.log" >> $source_dir/data/${tag}_spec
    else
        echo "No component sync errors found in P4_MKWA.log" >> $source_dir/data/${tag}_spec
        echo "Please check ${refdir_name}/P4_MKWA.log for details" >> $source_dir/data/${tag}_spec
    endif

    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

cd $refdir_name

# Run GMC static check command script
echo "Check type: $checktype_name"
source $source_dir/script/rtg_oss_feint/gmc/static_check_command.csh

if ($status != 0) then
    echo "ERROR: Static check failed" >> $source_dir/data/${tag}_spec
endif

echo "Static check completed successfully"

cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
