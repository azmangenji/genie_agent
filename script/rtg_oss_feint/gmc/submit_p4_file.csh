#!/bin/tcsh
# GMC: Submit P4 files with custom description
# Usage: submit_p4_file.csh <refDir> <ip> <tile> <tag>
# Reads file paths from data/<tag>.p4_files
# Reads description from data/<tag>.p4_description

set refDir = $1
set ip = $2
set tile = $3
set tag = $4
set source_dir = `pwd`
touch $source_dir/data/${tag}_spec

# Parse parameters
set refdir_name = `echo $refDir | sed 's/:/ /g' | awk '{$1="";print $0}'`
set ip_name = `echo $ip | sed 's/:/ /g' | awk '{$1="";print $0}'`

# Validate inputs
set refdir_count = `echo $refdir_name | wc -w`
if ($refdir_count == 0) then
    echo "ERROR: Missing refDir" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Read file list from data/{tag}.p4_files
set file_list_path = "$source_dir/data/${tag}.p4_files"
if (! -f $file_list_path) then
    echo "ERROR: File list not found: $file_list_path" >> $source_dir/data/${tag}_spec
    echo "Please specify files to submit in email" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Read description from data/{tag}.p4_description
set description_path = "$source_dir/data/${tag}.p4_description"
if (-f $description_path) then
    set cl_description = `cat $description_path | head -1`
else
    set cl_description = "Update files (Task: $tag)"
endif

# Navigate to workspace
cd $refdir_name

# Report submit operation
echo "#text#" >> $source_dir/data/${tag}_spec
echo "========================================" >> $source_dir/data/${tag}_spec
echo "P4 Submit Operation" >> $source_dir/data/${tag}_spec
echo "========================================" >> $source_dir/data/${tag}_spec
echo "Workspace: $refdir_name" >> $source_dir/data/${tag}_spec
echo "Description: $cl_description" >> $source_dir/data/${tag}_spec
echo "" >> $source_dir/data/${tag}_spec
echo "Files to submit:" >> $source_dir/data/${tag}_spec

# Process each file
set submit_success = 0
set submit_failed = 0
set submitted_files = ""

foreach file_path (`cat $file_list_path`)
    echo "  - $file_path" >> $source_dir/data/${tag}_spec

    # Check if file exists
    if (! -f $file_path) then
        echo "    ERROR: File not found" >> $source_dir/data/${tag}_spec
        set submit_failed = `expr $submit_failed + 1`
        continue
    endif

    # Check if file is in P4 or is a new file
    set p4_opened = `p4 opened $file_path |& grep -v "not opened"`

    if ("$p4_opened" == "") then
        # File not opened - check if it's a new file or needs to be added
        set p4_fstat = `p4 fstat $file_path |& grep -c "no such file"`

        if ($p4_fstat > 0) then
            # New file - add to P4
            echo "    New file - adding to P4..." >> $source_dir/data/${tag}_spec
            p4 add $file_path
            if ($status != 0) then
                echo "    ERROR: Failed to add file to P4" >> $source_dir/data/${tag}_spec
                continue
            endif
            echo "    File added to P4" >> $source_dir/data/${tag}_spec
        else
            # File exists in P4 but not opened - try to open it
            echo "    Opening file for edit..." >> $source_dir/data/${tag}_spec
            p4 edit $file_path
            if ($status != 0) then
                echo "    ERROR: Failed to open file for edit" >> $source_dir/data/${tag}_spec
                continue
            endif
            echo "    File opened for edit" >> $source_dir/data/${tag}_spec
        endif
    endif

    # Add to submit list
    if ("$submitted_files" == "") then
        set submitted_files = "$file_path"
    else
        set submitted_files = "$submitted_files $file_path"
    endif
end

# Submit all files together
if ("$submitted_files" != "") then
    echo "" >> $source_dir/data/${tag}_spec
    echo "Submitting files to P4..." >> $source_dir/data/${tag}_spec

    # Ensure description is not empty
    if ("$cl_description" == "") then
        set cl_description = "Update files (Task: $tag)"
    endif

    p4 submit -d "$cl_description" $submitted_files

    if ($status == 0) then
        # Get the submitted changelist number
        set submitted_cl = `p4 changes -m 1 | awk '{print $2}'`

        # Report success
        echo "" >> $source_dir/data/${tag}_spec
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "P4 Submit Summary" >> $source_dir/data/${tag}_spec
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "Status: SUCCESS" >> $source_dir/data/${tag}_spec
        echo "Changelist: $submitted_cl" >> $source_dir/data/${tag}_spec
        echo "Description: $cl_description" >> $source_dir/data/${tag}_spec
        set file_count = `echo $submitted_files | wc -w`
        echo "Files Submitted: $file_count" >> $source_dir/data/${tag}_spec
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "" >> $source_dir/data/${tag}_spec
        echo "Submitted Files:" >> $source_dir/data/${tag}_spec
        foreach file ($submitted_files)
            echo "  - $file" >> $source_dir/data/${tag}_spec
        end
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "" >> $source_dir/data/${tag}_spec

        echo "Files submitted successfully as CL $submitted_cl"
        set submit_success = 1
    else
        # Report failure
        echo "" >> $source_dir/data/${tag}_spec
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "P4 Submit Summary" >> $source_dir/data/${tag}_spec
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "Status: FAILED" >> $source_dir/data/${tag}_spec
        echo "Error: P4 submit command failed" >> $source_dir/data/${tag}_spec
        echo "Please check P4 permissions and file status" >> $source_dir/data/${tag}_spec
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "" >> $source_dir/data/${tag}_spec

        echo "ERROR: P4 submit failed"
        set run_status = "failed"
        source $source_dir/script/rtg_oss_feint/finishing_task.csh
        exit 1
    endif
else
    echo "" >> $source_dir/data/${tag}_spec
    echo "ERROR: No files ready for submit" >> $source_dir/data/${tag}_spec
    echo "Please ensure files are opened for edit first" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Cleanup and finish
cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
