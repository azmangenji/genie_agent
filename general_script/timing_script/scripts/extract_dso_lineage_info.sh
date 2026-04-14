#!/bin/bash
#===============================================================================
# Script: extract_dso_lineage_info.sh
# Description: Extract timing information and permutons used from all DSO lineages
# Usage: ./extract_dso_lineage_info.sh <dso_run_directory> [output_file]
# Example: ./extract_dso_lineage_info.sh /path/to/umccmd_DSO_28Jan_40p
#===============================================================================

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <dso_run_directory> [output_file]"
    echo "Example: $0 /proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/umccmd_DSO_28Jan_40p"
    exit 1
fi

DSO_DIR="$1"

# Validate directory
if [ ! -d "$DSO_DIR" ]; then
    echo "Error: Directory not found: $DSO_DIR"
    exit 1
fi

WORK_DIR="$DSO_DIR/data/CrlFlow/work"
if [ ! -d "$WORK_DIR" ]; then
    echo "Error: Work directory not found: $WORK_DIR"
    exit 1
fi

# Get run name from directory
RUN_NAME=$(basename "$DSO_DIR")

# Temporary files
TMP_DIR=$(mktemp -d)
TMP_ALL="$TMP_DIR/all_lineages.txt"
TMP_ERROR_FREE="$TMP_DIR/error_free.txt"
TMP_ERRORED="$TMP_DIR/errored.txt"
TMP_PERMUTON_COUNT="$TMP_DIR/permuton_count.txt"
TMP_BROKEN_COUNT="$TMP_DIR/broken_count.txt"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Progress messages go to stderr so they don't mix with report output
echo "Processing DSO run: $DSO_DIR" >&2
echo "" >&2

# Find all lineage directories
LINEAGES=$(find "$WORK_DIR" -maxdepth 1 -type d -name ".run_*" 2>/dev/null | sort)
TOTAL_LINEAGES=$(echo "$LINEAGES" | grep -c "run_" || echo "0")

echo "Found $TOTAL_LINEAGES lineages" >&2
echo "" >&2

# Initialize counters
ERROR_COUNT=0
NO_ERROR_COUNT=0

# Process each lineage
for lineage_dir in $LINEAGES; do
    lineage=$(basename "$lineage_dir")
    echo "Processing: $lineage" >&2

    # Find FxSynthesize log file
    log_file=$(find "$lineage_dir" -maxdepth 1 -name "FxSynthesize_*.log" 2>/dev/null | grep -v "dso_" | head -1)

    # Find status_xls.rpt
    status_file="$lineage_dir/dso_input_dir/rpts/FxSynthesize/status_xls.rpt"

    # Find click.qor.rpt
    qor_file="$lineage_dir/click/click.qor.rpt"

    # Get permutons from log
    permutons=""
    if [ -f "$log_file" ]; then
        permutons=$(grep "DSO-6124" "$log_file" 2>/dev/null | \
            grep "is being evaluated" | \
            sed -n "s/.*The code for '\([^']*\)'.*/\1/p" | \
            grep -v "report_performance" | \
            sort -u | \
            tr '\n' ',' | \
            sed 's/,$//' | \
            sed 's/,/, /g')
    fi

    # Check for errors
    has_error="N/A"
    broken_proc=""
    if [ -f "$log_file" ]; then
        if grep -q "DSO-6804" "$log_file" 2>/dev/null; then
            has_error="YES"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            # Get broken proc name
            broken_proc=$(grep "DSO-6804" "$log_file" 2>/dev/null | head -1 | sed -n 's/.*DSO::PERMUTONS::\([a-zA-Z_]*\).*/\1/p')
        else
            has_error="NO"
            NO_ERROR_COUNT=$((NO_ERROR_COUNT + 1))
        fi
    fi

    # Get timing from status_xls.rpt
    wns_s="-"
    tns_s="-"
    nve_s="-"
    if [ -f "$status_file" ]; then
        line2=$(sed -n '2p' "$status_file")
        wns_s=$(echo "$line2" | awk '{print $1}')
        tns_s=$(echo "$line2" | awk '{print $2}')
        nve_s=$(echo "$line2" | awk '{print $3}')
    fi

    # Get Vt percentages
    lvtll_pct="-"
    lvt_pct="-"
    ulvtll_pct="-"
    ulvt_pct="-"
    if [ -f "$status_file" ]; then
        pct_line=$(grep -A1 "lvtll %" "$status_file" 2>/dev/null | tail -1)
        if [ -n "$pct_line" ]; then
            lvtll_pct=$(echo "$pct_line" | awk '{print $2}')
            lvt_pct=$(echo "$pct_line" | awk '{print $4}')
            ulvtll_pct=$(echo "$pct_line" | awk '{print $6}')
            ulvt_pct=$(echo "$pct_line" | awk '{print $8}')
        fi
    fi

    # Get status from click.qor.rpt
    status="Unknown"
    if [ -f "$qor_file" ]; then
        if grep -q "^DSO_final" "$qor_file" 2>/dev/null; then
            status="COMPLETED"
        else
            last_cp=$(tail -5 "$qor_file" | grep -v "^$" | tail -1 | awk '{print $1}')
            status="Running ($last_cp)"
        fi
    fi

    # Write to all lineages file
    echo "$lineage|$has_error|$wns_s|$tns_s|$nve_s|$lvtll_pct|$lvt_pct|$ulvtll_pct|$ulvt_pct|$status|$permutons|$broken_proc" >> "$TMP_ALL"

    # Collect permuton names for statistics
    if [ -n "$permutons" ]; then
        echo "$permutons" | tr ',' '\n' | sed 's/^ *//' >> "$TMP_PERMUTON_COUNT"
    fi

    # Collect broken proc names
    if [ -n "$broken_proc" ]; then
        echo "$broken_proc" >> "$TMP_BROKEN_COUNT"
    fi
done

echo "" >&2
echo "Processing complete. Generating report..." >&2
echo "" >&2

#===============================================================================
# Generate Output (to stdout)
#===============================================================================

echo "================================================================================"
echo "DSO LINEAGE ANALYSIS REPORT - $RUN_NAME"
echo "Generated: $(date)"
echo "Source: $DSO_DIR"
echo "================================================================================"
echo ""
echo "SUMMARY"
echo "-------"
echo "Total lineages:           $TOTAL_LINEAGES"
echo "Lineages with errors:     $ERROR_COUNT"
echo "Lineages without errors:  $NO_ERROR_COUNT"
echo ""
echo "================================================================================"
echo "ALL LINEAGES - PERMUTONS & ERROR STATUS"
echo "================================================================================"
echo ""
printf "%-16s | %-5s | %s\n" "LINEAGE" "ERROR" "PERMUTONS"
printf "%-16s-|-%-5s-|-%s\n" "----------------" "-----" "----------------------------------------------------------------------------------------------------"

sort "$TMP_ALL" | while IFS='|' read -r lineage has_error wns_s tns_s nve_s lvtll lvt ulvtll ulvt status permutons broken_proc; do
    printf "%-16s | %-5s | %s\n" "$lineage" "$has_error" "$permutons"
done

echo ""
echo "================================================================================"
echo "ERROR-FREE LINEAGES - DETAILED TIMING"
echo "================================================================================"
echo ""
printf "%-16s | %-12s | %-14s | %-8s | %-8s | %-8s | %-22s | %s\n" \
    "LINEAGE" "WNS(R_R) ps" "TNS(R_R) ps" "NVE(R_R)" "LVTLL %" "LVT %" "STATUS" "PERMUTONS"
printf "%-16s-|-%-12s-|-%-14s-|-%-8s-|-%-8s-|-%-8s-|-%-22s-|-%s\n" \
    "----------------" "------------" "--------------" "--------" "--------" "--------" "----------------------" "--------------------"

sort "$TMP_ALL" | while IFS='|' read -r lineage has_error wns_s tns_s nve_s lvtll lvt ulvtll ulvt status permutons broken_proc; do
    if [ "$has_error" = "NO" ]; then
        printf "%-16s | %-12s | %-14s | %-8s | %-8s | %-8s | %-22s | %s\n" \
            "$lineage" "$wns_s" "$tns_s" "$nve_s" "$lvtll" "$lvt" "$status" "$permutons"
    fi
done

echo ""
echo "================================================================================"
echo "ERRORED LINEAGES - BROKEN PERMUTONS"
echo "================================================================================"
echo ""
printf "%-16s | %-40s | %s\n" "LINEAGE" "BROKEN PROC" "PERMUTONS"
printf "%-16s-|-%-40s-|-%s\n" "----------------" "----------------------------------------" "--------------------"

sort "$TMP_ALL" | while IFS='|' read -r lineage has_error wns_s tns_s nve_s lvtll lvt ulvtll ulvt status permutons broken_proc; do
    if [ "$has_error" = "YES" ]; then
        printf "%-16s | %-40s | %s\n" "$lineage" "$broken_proc" "$permutons"
    fi
done

echo ""
echo "================================================================================"
echo "PERMUTON STATISTICS"
echo "================================================================================"
echo ""
echo "PERMUTON USAGE COUNT:"
echo "---------------------"
if [ -f "$TMP_PERMUTON_COUNT" ]; then
    sort "$TMP_PERMUTON_COUNT" | uniq -c | sort -rn
fi

echo ""
echo "BROKEN PERMUTON COUNT:"
echo "----------------------"
if [ -f "$TMP_BROKEN_COUNT" ]; then
    sort "$TMP_BROKEN_COUNT" | uniq -c | sort -rn
fi

echo ""
echo "================================================================================"
echo "END OF REPORT"
echo "================================================================================"
