#!/bin/tcsh
# Submit P4 files that were updated by update_cdc.csh
# Usage: submit_cdc_update.csh <refDir> <ip> <tile> <tag> <updateType>

set refDir = $1
set ip = $2
set tile = $3
set tag = $4
set updateType = $5
set source_dir = `pwd`
touch $source_dir/data/${tag}_spec

# Parse parameters
set refdir_name = `echo $refDir | sed 's/:/ /g' | awk '{$1="";print $0}'`
set ip_name = `echo $ip | sed 's/:/ /g' | awk '{$1="";print $0}'`
set tile_name = `echo $tile | sed 's/:/ /g' | awk '{$1="";print $0}'`
set updatetype_name = `echo $updateType | sed 's/:/ /g' | awk '{$1="";print $0}'`

# Validate inputs
set ip_count = `echo $ip_name | wc -w`
set refdir_count = `echo $refdir_name | wc -w`

if ($ip_count == 0 || $refdir_count == 0) then
    echo "ERROR: Missing IP name or refDir" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Determine which file was updated based on updateType
if ("$updatetype_name" == "waiver") then
    set target_file = "src/meta/tools/cdc0in/variant/$ip_name/umc.0in_waiver"
    set update_label = "CDC/RDC Waiver"
    
else if ("$updatetype_name" == "constraint") then
    set target_file = "src/meta/tools/cdc0in/variant/$ip_name/project.0in_ctrl.v.tcl"
    set update_label = "CDC/RDC Constraint"
    
else if ("$updatetype_name" == "config") then
    set target_file = "src/meta/tools/cdc0in/cdc.yml"
    set update_label = "CDC/RDC Config"
    
else if ("$updatetype_name" == "version") then
    set target_file = "_env/local/${ip_name}_modulefile"
    set update_label = "CDC/RDC Tool Version"
    
else
    echo "ERROR: Unknown update type: $updatetype_name" >> $source_dir/data/${tag}_spec
    echo "Valid types: waiver, constraint, config, version" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Navigate to workspace
cd $refdir_name

# Check if file exists
if (! -f $target_file) then
    echo "ERROR: Target file not found: $target_file" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Check if file is opened for edit
set p4_opened = `p4 opened $target_file |& grep -v "not opened"`
if ("$p4_opened" == "") then
    echo "ERROR: File is not opened for edit in P4: $target_file" >> $source_dir/data/${tag}_spec
    echo "Please run update_cdc.csh first to edit the file" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Create changelist description
set cl_description = "Update $update_label for $ip_name (Task: $tag)"

# Submit the file
echo "Submitting $target_file to P4..."
p4 submit -d "$cl_description" $target_file

if ($status == 0) then
    # Get the submitted changelist number
    set submitted_cl = `p4 changes -m 1 $target_file | awk '{print $2}'`
    
    # Report success
    cat >> $source_dir/data/${tag}_spec << EOF
#text#
========================================
P4 Submit Summary
========================================
Status: SUCCESS
File Submitted: $target_file
Changelist: $submitted_cl
Description: $cl_description
Update Type: $update_label
IP: $ip_name
========================================

EOF
    
    echo "File submitted successfully as CL $submitted_cl"
else
    # Report failure
    cat >> $source_dir/data/${tag}_spec << EOF
#text#
========================================
P4 Submit Summary
========================================
Status: FAILED
File: $target_file
Error: P4 submit command failed
Please check P4 permissions and file status
========================================

EOF
    
    echo "ERROR: P4 submit failed"
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Cleanup and finish
cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
