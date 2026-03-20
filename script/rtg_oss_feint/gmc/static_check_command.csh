#!/bin/tcsh
# GMC static check command dispatcher
# Called by static_check.csh after workspace setup
# Requires: $checktype_name, $ip_name, $source_dir, $tag

source /tool/pandora/etc/lsf/cshrc.lsf
source /tool/site-config/cshrc
source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh

# GMC runs both tiles (gmc_gmcch_t + gmc_gmcctrl_t) automatically via DROP_TOPS
# No tile check needed

# GMC uses bootenv -v (not -x)
bootenv -v $ip_name

# Save refdir for summary script
set refdir_name = `pwd`

# Notification script path
set notify_script = "$source_dir/script/rtg_oss_feint/gmc/send_static_check_notification.csh"

# Read email override if exists
set email_override = ""
if (-f "$source_dir/data/${tag}_email") then
    set email_content = `cat $source_dir/data/${tag}_email | head -1`
    if ("$email_content" != "" && "$email_content" != "default") then
        set email_override = "$email_content"
        echo "Email override detected: $email_override"
    endif
endif

# Run appropriate static check based on checktype_name
if ("$checktype_name" == "cdc_rdc") then
    echo "Running GMC CDC/RDC checks..."
    source $source_dir/script/rtg_oss_feint/gmc/command/run_cdc_rdc.csh
    source $source_dir/script/rtg_oss_feint/gmc/static_check_analysis.csh

else if ("$checktype_name" == "lint") then
    echo "Running GMC Lint checks..."
    source $source_dir/script/rtg_oss_feint/gmc/command/run_lint.csh
    source $source_dir/script/rtg_oss_feint/gmc/static_check_analysis.csh

else if ("$checktype_name" == "spg_dft") then
    echo "Running GMC Spyglass DFT checks..."
    source $source_dir/script/rtg_oss_feint/gmc/command/run_spg_dft.csh
    source $source_dir/script/rtg_oss_feint/gmc/static_check_analysis.csh

else if ("$checktype_name" == "full_static_check") then
    echo "Running GMC full static check suite..."

    # ========================================
    # Step 1: Run Lint
    # ========================================
    echo "Step 1/3: Running Lint checks..."
    source $source_dir/script/rtg_oss_feint/gmc/command/run_lint.csh

    # Analyze Lint and send notification
    echo "Analyzing Lint results and sending notification..."
    set checktype_name = "lint"

    set backup_spec = "$source_dir/data/${tag}_spec.backup"
    set temp_lint_spec = "/tmp/${tag}_lint_analysis.tmp"
    cp $source_dir/data/${tag}_spec $backup_spec
    rm -f $temp_lint_spec

    rm -f $source_dir/data/${tag}_spec
    touch $source_dir/data/${tag}_spec
    cd $refdir_name
    source $source_dir/script/rtg_oss_feint/gmc/static_check_analysis.csh
    cd $source_dir

    mv $source_dir/data/${tag}_spec $temp_lint_spec
    mv $backup_spec $source_dir/data/${tag}_spec

    if (-f $notify_script) then
        $notify_script "$source_dir" "$tag" "gmc" "lint" "$temp_lint_spec" "$ip_name" "$email_override" >& /tmp/lint_notify_${tag}_$$.log &
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
    source $source_dir/script/rtg_oss_feint/gmc/command/run_cdc_rdc.csh

    # Analyze CDC/RDC and send notification
    echo "Analyzing CDC/RDC results and sending notification..."
    set checktype_name = "cdc_rdc"

    set temp_cdc_spec = "/tmp/${tag}_cdc_rdc_analysis.tmp"
    set backup_spec = "$source_dir/data/${tag}_spec.backup"
    cp $source_dir/data/${tag}_spec $backup_spec
    rm -f $temp_cdc_spec

    rm -f $source_dir/data/${tag}_spec
    touch $source_dir/data/${tag}_spec
    cd $refdir_name
    source $source_dir/script/rtg_oss_feint/gmc/static_check_analysis.csh
    cd $source_dir

    mv $source_dir/data/${tag}_spec $temp_cdc_spec
    mv $backup_spec $source_dir/data/${tag}_spec

    if (-f $notify_script) then
        $notify_script "$source_dir" "$tag" "gmc" "cdc_rdc" "$temp_cdc_spec" "$ip_name" "$email_override" >& /tmp/cdc_rdc_notify_${tag}_$$.log &
        echo "CDC/RDC notification sent in background (PID: $!)"
    else
        rm -f $temp_cdc_spec
    endif

    set checktype_name = "full_static_check"
    echo "CDC/RDC completed"

    # ========================================
    # Step 3: Run Spyglass DFT
    # ========================================
    echo "Step 3/3: Running Spyglass DFT checks..."
    cd $refdir_name
    source $source_dir/script/rtg_oss_feint/gmc/command/run_spg_dft.csh

    # Analyze Spyglass DFT and send notification
    echo "Analyzing Spyglass DFT results and sending notification..."
    set checktype_name = "spg_dft"

    set temp_spg_spec = "/tmp/${tag}_spg_dft_analysis.tmp"
    set backup_spec = "$source_dir/data/${tag}_spec.backup"
    cp $source_dir/data/${tag}_spec $backup_spec
    rm -f $temp_spg_spec

    rm -f $source_dir/data/${tag}_spec
    touch $source_dir/data/${tag}_spec
    cd $refdir_name
    source $source_dir/script/rtg_oss_feint/gmc/static_check_analysis.csh
    cd $source_dir

    mv $source_dir/data/${tag}_spec $temp_spg_spec
    mv $backup_spec $source_dir/data/${tag}_spec

    if (-f $notify_script) then
        $notify_script "$source_dir" "$tag" "gmc" "spg_dft" "$temp_spg_spec" "$ip_name" "$email_override" >& /tmp/spg_dft_notify_${tag}_$$.log &
        echo "Spyglass DFT notification sent in background (PID: $!)"
    else
        rm -f $temp_spg_spec
    endif

    set checktype_name = "full_static_check"
    echo "Spyglass DFT completed"

    # ========================================
    # Generate final summary
    # ========================================
    echo "Generating final summary..."
    set error_filter = "$source_dir/script/rtg_oss_feint/gmc/spg_dft_error_filter.txt"
    perl $source_dir/script/rtg_oss_feint/gmc/static_check_summary.pl $refdir_name "gmc" $error_filter $refdir_name $ip_name >> $source_dir/data/${tag}_spec

    echo "GMC full static check suite completed successfully"

else
    echo "ERROR: Unknown check type: $checktype_name"
    echo "Valid check types: cdc_rdc, lint, spg_dft, full_static_check"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif
