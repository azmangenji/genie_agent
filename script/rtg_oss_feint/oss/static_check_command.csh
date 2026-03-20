#!/bin/tcsh
# Unified static check script for OSS - CDC/RDC, Lint, Spyglass DFT, Build RTL
# Called by static_check.csh after workspace setup
# Requires: $checktype_name, $tile_name, $source_dir, $tag, $ip_name

source /tool/pandora/etc/lsf/cshrc.lsf
source /tool/site-config/cshrc
source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh

# Determine command variant based on IP (Orion vs Arcadia)
set command_variant = ""
if ("$ip_name" == "oss7_2") then
    set command_variant = "_arcadia"
    echo "Using Arcadia command flow (oss7_2)"
else if ("$ip_name" == "oss8_0") then
    set command_variant = ""
    echo "Using Orion command flow (oss8_0)"
else
    echo "WARNING: Unknown OSS IP '${ip_name}', defaulting to Orion flow"
    set command_variant = ""
endif

# Save refdir for summary script
set refdir_name = `pwd`

# Notification script path
set notify_script = "$source_dir/script/rtg_oss_feint/oss/send_static_check_notification.csh"

# Read email override if exists (from --to flag in genie_cli.py)
set email_override = ""
if (-f "$source_dir/data/${tag}_email") then
    set email_content = `cat $source_dir/data/${tag}_email | head -1`
    if ("$email_content" != "" && "$email_content" != "default") then
        set email_override = "$email_content"
        echo "Email override detected: $email_override"
    endif
endif

# Route to appropriate check type
if ("$checktype_name" == "cdc_rdc") then
    echo "Running CDC/RDC checks..."
    source $source_dir/script/rtg_oss_feint/oss/command/run_cdc_rdc${command_variant}.csh
    source $source_dir/script/rtg_oss_feint/oss/static_check_analysis.csh

else if ("$checktype_name" == "lint") then
    echo "Running Lint checks..."
    source $source_dir/script/rtg_oss_feint/oss/command/run_lint${command_variant}.csh
    source $source_dir/script/rtg_oss_feint/oss/static_check_analysis.csh

else if ("$checktype_name" == "spg_dft") then
    echo "Running Spyglass DFT checks..."
    source $source_dir/script/rtg_oss_feint/oss/command/run_spg_dft${command_variant}.csh
    source $source_dir/script/rtg_oss_feint/oss/static_check_analysis.csh

else if ("$checktype_name" == "build_rtl") then
    echo "Running RTL build..."
    source $source_dir/script/rtg_oss_feint/oss/command/run_build_rtl${command_variant}.csh
    source $source_dir/script/rtg_oss_feint/oss/static_check_analysis.csh

else if ("$checktype_name" == "full_static_check") then
    echo "Running full static check suite..."

    # ========================================
    # Step 1: Run Lint
    # ========================================
    echo "Step 1/3: Running Lint checks..."
    source $source_dir/script/rtg_oss_feint/oss/command/run_lint${command_variant}.csh

    # Analyze Lint and send notification
    echo "Analyzing Lint results and sending notification..."
    set checktype_name = "lint"

    # Backup current data spec and create temp spec for lint analysis
    set backup_spec = "$source_dir/data/${tag}_spec.backup"
    set temp_lint_spec = "/tmp/${tag}_lint_analysis.tmp"
    cp $source_dir/data/${tag}_spec $backup_spec
    rm -f $temp_lint_spec

    # Temporarily redirect tag_spec to capture lint analysis output
    rm -f $source_dir/data/${tag}_spec
    touch $source_dir/data/${tag}_spec
    cd $refdir_name
    source $source_dir/script/rtg_oss_feint/oss/static_check_analysis.csh
    cd $source_dir

    # Save analysis output to temp file for email
    mv $source_dir/data/${tag}_spec $temp_lint_spec

    # Restore original spec
    mv $backup_spec $source_dir/data/${tag}_spec

    # Send notification in background
    if (-f $notify_script) then
        $notify_script "$source_dir" "$tag" "$tile_name" "lint" "$temp_lint_spec" "$ip_name" "$email_override" >& /tmp/lint_notify_${tag}_$$.log &
        echo "Lint notification sent in background (PID: $!)"
    else
        echo "WARNING: Notification script not found: $notify_script"
        rm -f $temp_lint_spec
    endif

    set checktype_name = "full_static_check"
    echo "Lint completed"

    # ========================================
    # Step 2: Run CDC/RDC
    # ========================================
    echo "Step 2/3: Running CDC/RDC checks..."
    cd $refdir_name
    source $source_dir/script/rtg_oss_feint/oss/command/run_cdc_rdc${command_variant}.csh

    # Analyze CDC/RDC and send notification
    echo "Analyzing CDC/RDC results and sending notification..."
    set checktype_name = "cdc_rdc"

    # Create temp spec for CDC/RDC analysis
    set temp_cdc_spec = "/tmp/${tag}_cdc_rdc_analysis.tmp"
    set backup_spec = "$source_dir/data/${tag}_spec.backup"
    cp $source_dir/data/${tag}_spec $backup_spec
    rm -f $temp_cdc_spec

    # Temporarily redirect tag_spec to capture CDC/RDC analysis output
    rm -f $source_dir/data/${tag}_spec
    touch $source_dir/data/${tag}_spec
    cd $refdir_name
    source $source_dir/script/rtg_oss_feint/oss/static_check_analysis.csh
    cd $source_dir

    # Save analysis output to temp file for email
    mv $source_dir/data/${tag}_spec $temp_cdc_spec

    # Restore original spec
    mv $backup_spec $source_dir/data/${tag}_spec

    # Send notification in background
    if (-f $notify_script) then
        $notify_script "$source_dir" "$tag" "$tile_name" "cdc_rdc" "$temp_cdc_spec" "$ip_name" "$email_override" >& /tmp/cdc_rdc_notify_${tag}_$$.log &
        echo "CDC/RDC notification sent in background (PID: $!)"
    else
        echo "WARNING: Notification script not found: $notify_script"
        rm -f $temp_cdc_spec
    endif

    set checktype_name = "full_static_check"
    echo "CDC/RDC completed"

    # ========================================
    # Step 3: Run Spyglass DFT
    # ========================================
    echo "Step 3/3: Running Spyglass DFT checks..."
    cd $refdir_name
    source $source_dir/script/rtg_oss_feint/oss/command/run_spg_dft${command_variant}.csh

    # Analyze Spyglass DFT and send notification
    echo "Analyzing Spyglass DFT results and sending notification..."
    set checktype_name = "spg_dft"

    # Create temp spec for Spyglass DFT analysis
    set temp_spg_spec = "/tmp/${tag}_spg_dft_analysis.tmp"
    set backup_spec = "$source_dir/data/${tag}_spec.backup"
    cp $source_dir/data/${tag}_spec $backup_spec
    rm -f $temp_spg_spec

    # Temporarily redirect tag_spec to capture Spyglass DFT analysis output
    rm -f $source_dir/data/${tag}_spec
    touch $source_dir/data/${tag}_spec
    cd $refdir_name
    source $source_dir/script/rtg_oss_feint/oss/static_check_analysis.csh
    cd $source_dir

    # Save analysis output to temp file for email
    mv $source_dir/data/${tag}_spec $temp_spg_spec

    # Restore original spec
    mv $backup_spec $source_dir/data/${tag}_spec

    # Send notification in background
    if (-f $notify_script) then
        $notify_script "$source_dir" "$tag" "$tile_name" "spg_dft" "$temp_spg_spec" "$ip_name" "$email_override" >& /tmp/spg_dft_notify_${tag}_$$.log &
        echo "Spyglass DFT notification sent in background (PID: $!)"
    else
        echo "WARNING: Notification script not found: $notify_script"
        rm -f $temp_spg_spec
    endif

    set checktype_name = "full_static_check"
    echo "Spyglass DFT completed"

    # ========================================
    # Generate final summary
    # ========================================
    echo "Generating final summary..."
    set error_filter = "$source_dir/script/rtg_oss_feint/oss/spg_dft_error_filter.txt"

    # Handle tile processing for summary
    if ($tile_name == all || $tile_name == "") then
        # Process all OSS tiles
        foreach tile_iter (sdma0_gc osssys lsdma0 hdp)
            perl $source_dir/script/rtg_oss_feint/oss/static_check_summary.pl $refdir_name $tile_iter $error_filter $refdir_name >> $source_dir/data/${tag}_spec
        end
    else
        perl $source_dir/script/rtg_oss_feint/oss/static_check_summary.pl $refdir_name $tile_name $error_filter $refdir_name >> $source_dir/data/${tag}_spec
    endif

    echo "Full static check suite completed successfully"

else
    echo "ERROR: Unknown check type: $checktype_name"
    echo "Valid check types: cdc_rdc, lint, spg_dft, build_rtl, full_static_check"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif
