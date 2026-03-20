#!/bin/tcsh
# GMC CDC/RDC waiver and constraint update script
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

# Validate inputs - GMC requires IP name (gmc13_1a, etc.) and refDir
set ip_count = `echo $ip_name | wc -w`
set refdir_count = `echo $refdir_name | wc -w`

if ($ip_count == 0 || $refdir_count == 0) then
    echo "You didn't specify IP name (gmc13_1a, etc.) and the path to update. Please specify before continuing" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Route based on updateType
# GMC uses different file paths than UMC:
# - CDC waiver: src/meta/tools/cdc0in/variant/$ip_name/gmc.0in_waiver.tcl
# - CDC constraint: src/meta/tools/cdc0in/variant/$ip_name/CDC.0in_ctrl.v.tcl
# - RDC constraint: src/meta/tools/cdc0in/variant/$ip_name/RDC.0in_ctrl.v.tcl
# - Config: src/meta/tools/cdc0in/variant/$ip_name/cdc.yml
# - Version: _env/local/env.cfg

if ("$updatetype_name" == "waiver") then
    set target_file = "src/meta/tools/cdc0in/variant/$ip_name/gmc.0in_waiver.tcl"
    set update_label = "waiver"
    echo "Updating CDC/RDC waivers..."

else if ("$updatetype_name" == "constraint") then
    # For constraint, we may need to update both CDC and RDC constraint files
    # Default to CDC constraint, but check content for RDC-specific entries
    set target_file = "src/meta/tools/cdc0in/variant/$ip_name/CDC.0in_ctrl.v.tcl"
    set update_label = "constraint"
    echo "Updating CDC constraints..."

else if ("$updatetype_name" == "rdc_constraint") then
    set target_file = "src/meta/tools/cdc0in/variant/$ip_name/RDC.0in_ctrl.v.tcl"
    set update_label = "rdc_constraint"
    echo "Updating RDC constraints..."

else if ("$updatetype_name" == "config") then
    set target_file = "src/meta/tools/cdc0in/variant/$ip_name/cdc.yml"
    set update_label = "config"
    echo "Updating CDC/RDC config settings..."

else if ("$updatetype_name" == "version") then
    set target_file = "_env/local/env.cfg"
    set update_label = "version"
    echo "Updating CDC/RDC tool versions..."

else
    echo "ERROR: Unknown update type: $updatetype_name" >> $source_dir/data/${tag}_spec
    echo "Valid types: waiver, constraint, rdc_constraint, config, version" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source script/rtg_oss_feint/finishing_task.csh
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
else if ("$updatetype_name" == "constraint" || "$updatetype_name" == "rdc_constraint") then
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
            python $source_dir/script/rtg_oss_feint/gmc/update_config_yaml.py $full_target_path $content_file
        # For version, replace CDC_Verif and 0in lines in env.cfg
        else if ("$updatetype_name" == "version") then
            foreach version_line (`cat $content_file`)
                set tool_name = `echo $version_line | awk -F/ '{print $1}'`

                if ("$tool_name" == "CDC_Verif") then
                    # GMC uses env.cfg with different format - grep for CDC_Verif/0in pattern
                    sed -i "s|CDC_Verif/[0-9._]*|$version_line|g" $full_target_path
                else if ("$tool_name" == "0in") then
                    sed -i "s|0in/[0-9._]*|$version_line|g" $full_target_path
                endif
            end
        else
            # For waiver and constraint - append to end of file
            cat $content_file >> $full_target_path
        endif

        # Report update summary using echo commands (avoid here-document issues)
        echo "#text#" >> $source_dir/data/${tag}_spec
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "Update Summary" >> $source_dir/data/${tag}_spec
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "Status: SUCCESS" >> $source_dir/data/${tag}_spec
        echo "File Edited: $target_file" >> $source_dir/data/${tag}_spec
        echo "Full Path: $full_target_path" >> $source_dir/data/${tag}_spec
        echo "Update Type: $update_label" >> $source_dir/data/${tag}_spec
        echo "Lines Added/Modified: $n_items" >> $source_dir/data/${tag}_spec
        echo "" >> $source_dir/data/${tag}_spec
        echo "Changes Applied:" >> $source_dir/data/${tag}_spec
        echo "----------------------------------------" >> $source_dir/data/${tag}_spec
        cat $content_file >> $source_dir/data/${tag}_spec
        echo "----------------------------------------" >> $source_dir/data/${tag}_spec
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "" >> $source_dir/data/${tag}_spec

    else
        echo "WARNING: Content file is empty" >> $source_dir/data/${tag}_spec
        set run_status = "failed"
        source $source_dir/script/rtg_oss_feint/finishing_task.csh
        exit 1
    endif
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
# GMC uses DROP_TOPS for tiles
set tile_name = "gmc_gmcctrl_t+gmc_gmcch_t"
source $source_dir/script/rtg_oss_feint/gmc/static_check_command.csh
echo "CDC/RDC verification completed"

# Cleanup and finish
cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
