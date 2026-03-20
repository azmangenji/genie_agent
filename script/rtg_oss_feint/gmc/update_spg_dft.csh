#!/bin/tcsh
# GMC Spyglass DFT parameter update script
# Usage: update_spg_dft.csh <refDir> <ip> <tile> <tag>

set refDir = $1
set ip = $2
set tile = $3
set tag = $4
set source_dir = `pwd`
touch $source_dir/data/${tag}_spec

# Parse parameters
set refdir_name = `echo $refDir | sed 's/:/ /g' | awk '{$1="";print $0}'`
set ip_name = `echo $ip | sed 's/:/ /g' | awk '{$1="";print $0}'`
set tile_name = `echo $tile | sed 's/:/ /g' | awk '{$1="";print $0}'`

# Validate inputs - GMC requires IP name (gmc13_1a, etc.) and refDir
set ip_count = `echo $ip_name | wc -w`
set refdir_count = `echo $refdir_name | wc -w`

if ($ip_count == 0 || $refdir_count == 0) then
    echo "You didn't specify IP name (gmc13_1a, etc.) and the path to update. Please specify before continuing" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# GMC SPG_DFT params file path:
# src/meta/tools/spgdft/variant/$ip_name/project.params
set target_file = "src/meta/tools/spgdft/variant/$ip_name/project.params"
set full_target_path = $refdir_name/$target_file

echo "Updating Spyglass DFT parameters for $ip_name..."

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

# Read content from spg_dft parameter file
set content_file = "$source_dir/data/$tag.spg_dft_params"

echo "# Checking content file: $content_file"

if (-f $content_file) then
    set n_items = `cat $content_file | wc -l`

    if ($n_items > 0) then
        # Append parameters to end of file
        cat $content_file >> $full_target_path

        # Report update summary
        echo "#text#" >> $source_dir/data/${tag}_spec
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "Spyglass DFT Parameter Update Summary" >> $source_dir/data/${tag}_spec
        echo "========================================" >> $source_dir/data/${tag}_spec
        echo "Status: SUCCESS" >> $source_dir/data/${tag}_spec
        echo "File Edited: $target_file" >> $source_dir/data/${tag}_spec
        echo "Full Path: $full_target_path" >> $source_dir/data/${tag}_spec
        echo "Lines Added: $n_items" >> $source_dir/data/${tag}_spec
        echo "" >> $source_dir/data/${tag}_spec
        echo "Parameters Added:" >> $source_dir/data/${tag}_spec
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
    echo "Update failed: No Spyglass DFT parameters found in email" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Rerun Spyglass DFT checks to verify the update
echo "Rerunning Spyglass DFT checks to verify parameters..."
set checktype_name = spg_dft
# GMC uses gmc_w_phy for SPG_DFT
set tile_name = "gmc_w_phy"
source $source_dir/script/rtg_oss_feint/gmc/static_check_command.csh
echo "Spyglass DFT verification completed"

# Cleanup and finish
cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
