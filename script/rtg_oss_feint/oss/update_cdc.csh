#!/bin/tcsh
# Unified CDC/RDC waiver, constraint, config, and version update script for OSS
# Usage: update_cdc.csh <refDir> <ip> <tile> <tag> <updateType>

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

# Validate inputs - OSS: if no tile specified, default to "all"
set tile_count = `echo $tile_name | wc -w`
set refdir_count = `echo $refdir_name | wc -w`

# OSS: No tile specified means all tiles
if ($tile_count == 0) then
    set tile_name = "all"
    echo "# No tile specified, defaulting to all tiles"
endif

# Validate refDir is provided
if ($refdir_count == 0) then
    echo "You didn't specify the path to update. Please specify before continuing" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Route based on updateType
if ("$updatetype_name" == "waiver") then
    set target_file = "src/meta/tools/cdc0in/oss.0in_waiver.tcl"
    set update_label = "waiver"
    echo "Updating OSS CDC/RDC waivers..."
    
else if ("$updatetype_name" == "constraint") then
    set target_file = "src/meta/tools/cdc0in/project.0in_ctrl.v"
    set update_label = "constraint"
    echo "Updating OSS CDC/RDC constraints..."
    
else if ("$updatetype_name" == "config") then
    set target_file = "src/meta/tools/cdc0in/cdc.yml"
    set update_label = "config"
    echo "Updating OSS CDC/RDC config settings..."
    
else if ("$updatetype_name" == "version") then
    set target_file = "_env/local/env.cfg"
    set update_label = "version"
    echo "Updating OSS CDC/RDC tool versions..."
    
else
    echo "ERROR: Unknown update type: $updatetype_name" >> $source_dir/data/${tag}_spec
    echo "Valid types: waiver, constraint, config, version" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Set full path to target file
set full_target_path = $refdir_name/$target_file

# Navigate to workspace and edit file
cd $refdir_name

# Check if file exists before editing
if (! -f $target_file) then
    echo "ERROR: Target file not found: $target_file" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Open file for P4 edit
p4 edit $target_file

# Read content from specific file based on updateType
if ("$updatetype_name" == "waiver") then
    set content_file = "$source_dir/data/$tag.cdc_rdc_waiver"
else if ("$updatetype_name" == "constraint") then
    set content_file = "$source_dir/data/$tag.cdc_rdc_constraint"
else if ("$updatetype_name" == "config") then
    set content_file = "$source_dir/data/$tag.cdc_rdc_config"
else if ("$updatetype_name" == "version") then
    set content_file = "$source_dir/data/$tag.cdc_rdc_version"
endif

echo "# Checking content file: $content_file"

if (-f $content_file) then
    set n_items = `cat $content_file | wc -l`
    
    if ($n_items > 0) then
        # For config, use Python script to update YAML with proper indentation
        if ("$updatetype_name" == "config") then
            echo "# Using Python script to update YAML config..."
            python $source_dir/script/rtg_oss_feint/oss/update_config_yaml.py $full_target_path $content_file
        else if ("$updatetype_name" == "version") then
            # For version, replace tool versions in XML env.cfg
            echo "# Updating tool versions in env.cfg..."
            foreach version_line (`cat $content_file`)
                set tool_name = `echo $version_line | awk -F/ '{print $1}'`
                set tool_version = `echo $version_line | awk -F/ '{print $2}'`
                echo "# Processing tool: $tool_name with version: $tool_version"
                
                # Update XML format: <name>tool_name</name><ver>version</ver>
                # Find the line with <name>tool_name</name> and update the next <ver> line
                set line_num = `grep -n "<name>${tool_name}</name>" $full_target_path | head -1 | cut -d: -f1`
                if ("$line_num" != "") then
                    @ ver_line = $line_num + 1
                    sed -i "${ver_line}s|<ver>.*</ver>|<ver>${tool_version}</ver>|" $full_target_path
                    echo "# Replaced $tool_name version to $tool_version"
                else
                    echo "# Warning: Tool $tool_name not found in env.cfg"
                endif
            end
        else
            # For waiver and constraint, append to end of file
            cat $content_file >> $full_target_path
        endif
        
        # Get content for reporting
        set update_content = `cat $content_file`
    
    # Report update
    cat >> $source_dir/data/${tag}_spec << EOF
#list#
The $update_label has been updated:
#table#
Directory,$update_label
EOF
    
    echo "$full_target_path,$update_content" >> $source_dir/data/${tag}_spec
    echo "#table end#" >> $source_dir/data/${tag}_spec
    
else
    echo "ERROR: Content file not found: $content_file" >> $source_dir/data/${tag}_spec
    echo "Update failed: No $update_label content found in email" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Rerun CDC/RDC checks to verify the update
echo "Rerunning CDC/RDC checks to verify $update_label..."
set checktype_name = cdc_rdc
source $source_dir/script/rtg_oss_feint/oss/static_check_command.csh
echo "CDC/RDC verification completed"

# Cleanup and finish
cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
