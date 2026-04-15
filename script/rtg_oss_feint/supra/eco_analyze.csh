#!/bin/tcsh
# Validate ECO TileBuilder directory and emit ECO_ANALYZE_MODE_ENABLED signal
# Parameters: refDir tag tile integer(jira_number)
# Called by genie_cli.py — runs synchronously (thin wrapper, seconds)

set refDir    = $1
set tag       = $2
set tile      = $3
set jira_raw  = $4
set source_dir = `pwd`

# Extract JIRA number (strip integer: prefix if present)
set jira_num = `echo $jira_raw | sed 's/integer://' | sed 's/^://g' | xargs`

# Validate JIRA number
if ("$jira_num" == "" || "$jira_num" == " ") then
    echo "#text#" >> $source_dir/data/${tag}_spec
    echo "ERROR: JIRA ticket number is required. Usage: run eco analysis at <dir> for <tile> <jira_number>" >> $source_dir/data/${tag}_spec
    echo "Example: run eco analysis at /proj/xxx/tiles/... for umccmd 9874" >> $source_dir/data/${tag}_spec
    echo "#text end#" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

touch $source_dir/data/${tag}_spec

# Strip prefixes
set refdir_name = `echo $refDir | sed 's/refDir://' | sed 's/^://g'`
set tile_name   = `echo $tile   | sed 's/tile://'   | sed 's/^://g' | xargs`

echo "ECO Analyze: validating $tile_name at $refdir_name (JIRA: $jira_num)"

# --- Validation: refDir ---

if ("$refdir_name" == "" || "$refdir_name" == " ") then
    echo "#text#" >> $source_dir/data/${tag}_spec
    echo "ERROR: refDir is empty or invalid" >> $source_dir/data/${tag}_spec
    echo "#text end#" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

if (! -d $refdir_name) then
    echo "#text#" >> $source_dir/data/${tag}_spec
    echo "ERROR: Directory not found: $refdir_name" >> $source_dir/data/${tag}_spec
    echo "#text end#" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

if (! -f "$refdir_name/revrc.main") then
    echo "#text#" >> $source_dir/data/${tag}_spec
    echo "ERROR: Not a TileBuilder directory (revrc.main not found): $refdir_name" >> $source_dir/data/${tag}_spec
    echo "#text end#" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# --- Validation: RTL directories ---

foreach rtl_dir ("data/PreEco/SynRtl" "data/SynRtl")
    if (! -d "$refdir_name/$rtl_dir") then
        echo "#text#" >> $source_dir/data/${tag}_spec
        echo "ERROR: RTL directory not found: $refdir_name/$rtl_dir" >> $source_dir/data/${tag}_spec
        echo "#text end#" >> $source_dir/data/${tag}_spec
        set run_status = "failed"
        source $source_dir/script/rtg_oss_feint/finishing_task.csh
        exit 1
    endif
end

# --- Validation: PreEco netlists (mandatory — fail if missing) ---

foreach stage ("Synthesize" "PrePlace" "Route")
    if (! -f "$refdir_name/data/PreEco/${stage}.v.gz") then
        echo "#text#" >> $source_dir/data/${tag}_spec
        echo "ERROR: Required PreEco netlist not found: $refdir_name/data/PreEco/${stage}.v.gz" >> $source_dir/data/${tag}_spec
        echo "#text end#" >> $source_dir/data/${tag}_spec
        set run_status = "failed"
        source $source_dir/script/rtg_oss_feint/finishing_task.csh
        exit 1
    endif
end

# --- Validation: PostEco netlists (auto-copy from PreEco if missing) ---

if (! -d "$refdir_name/data/PostEco") then
    echo "#text#" >> $source_dir/data/${tag}_spec
    echo "ERROR: PostEco directory not found: $refdir_name/data/PostEco" >> $source_dir/data/${tag}_spec
    echo "#text end#" >> $source_dir/data/${tag}_spec
    set run_status = "failed"
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

foreach stage ("Synthesize" "PrePlace" "Route")
    if (! -f "$refdir_name/data/PostEco/${stage}.v.gz") then
        echo "#text#" >> $source_dir/data/${tag}_spec
        echo "INFO: PostEco/${stage}.v.gz not found — copying from PreEco as baseline" >> $source_dir/data/${tag}_spec
        echo "#text end#" >> $source_dir/data/${tag}_spec
        cp "$refdir_name/data/PreEco/${stage}.v.gz" "$refdir_name/data/PostEco/${stage}.v.gz"
        if ($status != 0) then
            echo "#text#" >> $source_dir/data/${tag}_spec
            echo "ERROR: Failed to copy PreEco/${stage}.v.gz to PostEco/" >> $source_dir/data/${tag}_spec
            echo "#text end#" >> $source_dir/data/${tag}_spec
            set run_status = "failed"
            source $source_dir/script/rtg_oss_feint/finishing_task.csh
            exit 1
        endif
    endif
end

# --- All validation passed — write summary ---

echo "#table#" >> $source_dir/data/${tag}_spec
echo "Field,Value" >> $source_dir/data/${tag}_spec
echo "Tile,$tile_name" >> $source_dir/data/${tag}_spec
echo "JIRA,$jira_num" >> $source_dir/data/${tag}_spec
echo "TileBuilder Dir,$refdir_name" >> $source_dir/data/${tag}_spec
echo "PreEco RTL,$refdir_name/data/PreEco/SynRtl" >> $source_dir/data/${tag}_spec
echo "PostEco RTL,$refdir_name/data/SynRtl" >> $source_dir/data/${tag}_spec
echo "PreEco Netlists,Synthesize.v.gz + PrePlace.v.gz + Route.v.gz (verified)" >> $source_dir/data/${tag}_spec
echo "PostEco Netlists,Synthesize.v.gz + PrePlace.v.gz + Route.v.gz (verified or copied from PreEco)" >> $source_dir/data/${tag}_spec
echo "Status,Validation PASSED — ECO orchestrator launching" >> $source_dir/data/${tag}_spec
echo "#table end#" >> $source_dir/data/${tag}_spec

# --- Emit signal (captured by genie_cli.py) ---

echo ""
echo "========================================================================"
echo "ECO_ANALYZE_MODE_ENABLED"
echo "TAG=$tag"
echo "REF_DIR=$refdir_name"
echo "TILE=$tile_name"
echo "JIRA=$jira_num"
echo "LOG_FILE=$source_dir/runs/${tag}.log"
echo "SPEC_FILE=$source_dir/data/${tag}_spec"
echo "========================================================================"
echo ""

# Record task as finished (for task tracking)
cd $source_dir
set run_status = "finished"
source csh/env.csh
source csh/updateTask.csh
