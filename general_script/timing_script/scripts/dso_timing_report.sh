#!/bin/bash
################################################################################
# DSO Timing Report Generator
# Extracts WNS/TNS metrics and permutons from DSO runs, generates HTML report
#
# Usage: ./dso_timing_report.sh <dso_run_dir> <baseline_dir> [pass_number] [output_file] [email]
#
# Author: DSO.ai Monitoring System
# Updated: 2026-03-29
# Changes: Use FxSynthesize.dat (totalCoreWNS/totalCoreTNS) instead of proc_qor.rpt.gz
################################################################################

# Parse arguments
DSO_RUN_DIR="${1:-}"
BASELINE_DIR="${2:-}"
PASS_NUM="${3:-3}"
OUTPUT_FILE_BASE="${4:-/tmp/dso_timing_report}"
EMAIL="${5:-}"

# Add date to output filename
DATE_SUFFIX=$(date +%Y%m%d)
if [[ -n "$OUTPUT_FILE_BASE" ]]; then
    # Remove .html extension if present, add date, then add .html back
    OUTPUT_FILE="${OUTPUT_FILE_BASE%.html}_${DATE_SUFFIX}.html"
else
    OUTPUT_FILE="/tmp/dso_timing_report_${DATE_SUFFIX}.html"
fi

if [[ -z "$DSO_RUN_DIR" ]] || [[ -z "$BASELINE_DIR" ]]; then
    echo "Usage: $0 <dso_run_dir> <baseline_dir> [pass_number] [output_file] [email]"
    exit 1
fi

# Validate
[[ ! -d "$DSO_RUN_DIR" ]] && echo "Error: DSO run directory not found" && exit 1
[[ ! -d "$BASELINE_DIR" ]] && echo "Error: Baseline directory not found" && exit 1
[[ -n "$EMAIL" ]] && [[ ! "$EMAIL" =~ @amd\.com$ ]] && echo "Error: Email must be @amd.com" && exit 1

# Config
RUN_NAME=$(basename "$DSO_RUN_DIR")
BASELINE_NAME=$(basename "$BASELINE_DIR")
DATE_GENERATED=$(date "+%d %b %Y %H:%M")

# Auto-detect permutons file based on run name
PERMUTONS_BASE="/proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/dso_timing_enhancement"
if [[ "$RUN_NAME" == *"4Mac"* ]]; then
    PERMUTONS_FILE="${PERMUTONS_BASE}/LINEAGE_PERMUTONS_4Mac40p.txt"
elif [[ "$RUN_NAME" == *"28Jan"* ]]; then
    PERMUTONS_FILE="${PERMUTONS_BASE}/LINEAGE_PERMUTONS.txt"
else
    # Try to find matching permutons file
    PERMUTONS_FILE="${PERMUTONS_BASE}/LINEAGE_PERMUTONS.txt"
fi
echo "Permutons file: $PERMUTONS_FILE"

echo "========================================"
echo "    DSO Timing Report Generator"
echo "========================================"
echo "DSO Run:  $RUN_NAME"
echo "Baseline: $BASELINE_NAME"
echo "Pass:     $PASS_NUM"
echo ""

# Extract baseline timing from FxSynthesize.dat (totalCoreWNS/totalCoreTNS)
echo "Extracting baseline timing..."
BASELINE_DAT="$BASELINE_DIR/rpts/FxSynthesize/FxSynthesize.dat"
TIMING_MODE="totalCore"
if [[ -f "$BASELINE_DAT" ]]; then
    BASELINE_WNS=$(grep "^totalCoreWNS:" "$BASELINE_DAT" | awk '{print $2}')
    BASELINE_TNS=$(grep "^totalCoreTNS:" "$BASELINE_DAT" | awk '{print $2}')
    BASELINE_NVP=$(grep "^totalCoreNVP:" "$BASELINE_DAT" | awk '{print $2}')
    if [[ -z "$BASELINE_WNS" ]]; then
        BASELINE_WNS="-149.35"
        BASELINE_TNS="-552291.89"
        BASELINE_NVP="0"
        echo "  Warning: totalCoreWNS not found in dat, using default"
    else
        echo "  Baseline WNS: $BASELINE_WNS ps (totalCore)"
        echo "  Baseline TNS: $BASELINE_TNS ps (totalCore)"
        echo "  Baseline NVP: $BASELINE_NVP"
    fi
else
    echo "  Warning: FxSynthesize.dat not found, using default"
    BASELINE_WNS="-149.35"
    BASELINE_TNS="-552291.89"
    BASELINE_NVP="0"
fi

# Create temp file for data collection
TMPDATA="/tmp/dso_data_$$.txt"
> "$TMPDATA"

echo "Extracting DSO lineage data..."

# Process all lineages
for run_dir in "$DSO_RUN_DIR"/data/CrlFlow/work/.run_*/; do
    [[ ! -d "$run_dir" ]] && continue
    lineage=$(basename "$run_dir" | sed 's/\.run_//')
    dat_file="${run_dir}dso_input_dir/rpts/FxSynthesize/FxSynthesize.dat"

    if [[ -f "$dat_file" ]] && grep -q "^totalCoreWNS:" "$dat_file" 2>/dev/null; then
        wns=$(grep "^totalCoreWNS:" "$dat_file" | awk '{print $2}')
        tns=$(grep "^totalCoreTNS:" "$dat_file" | awk '{print $2}')

        # Get permutons (all 9 UMCCMD custom permutons)
        permutons=""
        if [[ -f "$PERMUTONS_FILE" ]]; then
            # Extract permutons for this specific lineage only (stop at next lineage or empty line)
            permutons=$(awk -v lin="lineage_${lineage}" '
                $0 ~ "--- "lin" ---" { found=1; next }
                found && /^---/ { exit }
                found && /^$/ { exit }
                found && /^\s+(control_buffer|dcq_arb|crit_groups|ctrl_iso|umc_id_didt|fanout_dup|timer_counter|arb_safe|pgt|arb_r2r|r2r_tns_weight|dcqarb_boundary_opt|clkgate_opt|dcqarb_fanout):/ {
                    gsub(/^[[:space:]]+/, "")
                    gsub(/: /, "=")
                    printf "%s;", $0
                }
            ' "$PERMUTONS_FILE" 2>/dev/null | sed 's/;$//')
        fi

        echo "$lineage|$wns|$tns|$permutons" >> "$TMPDATA"
    fi
done

TOTAL=$(find "$DSO_RUN_DIR/data/CrlFlow/work" -maxdepth 1 -name ".run_*" -type d 2>/dev/null | wc -l)
COMPLETED=$(wc -l < "$TMPDATA")
echo "  Completed: $COMPLETED / $TOTAL lineages"

# Find best (by WNS) - filter outliers where WNS < -500
BEST_LINE=$(awk -F'|' '$2 > -500' "$TMPDATA" | sort -t'|' -k2 -rn | head -1)
BEST_LINEAGE=$(echo "$BEST_LINE" | cut -d'|' -f1)
BEST_WNS=$(echo "$BEST_LINE" | cut -d'|' -f2)
BEST_TNS=$(echo "$BEST_LINE" | cut -d'|' -f3)
IMPROVEMENT_WNS=$(echo "$BEST_WNS - $BASELINE_WNS" | bc 2>/dev/null)
IMPROVEMENT_TNS=$(echo "$BEST_TNS - $BASELINE_TNS" | bc 2>/dev/null)

echo ""
echo "Best: $BEST_LINEAGE (WNS: $BEST_WNS, +${IMPROVEMENT_WNS}ps | TNS: $BEST_TNS, +${IMPROVEMENT_TNS}ps)"

# Count categories
BETTER=$(awk -F'|' -v base="$BASELINE_WNS" '$2 > base && $2 > -500 {count++} END {print count+0}' "$TMPDATA")
WORSE=$(awk -F'|' -v base="$BASELINE_WNS" '$2 <= base && $2 > -500 {count++} END {print count+0}' "$TMPDATA")
OUTLIERS=$(awk -F'|' '$2 <= -500 {count++} END {print count+0}' "$TMPDATA")

echo "Better: $BETTER, Worse: $WORSE, Outliers: $OUTLIERS"

#-------------------------------------------------------------------------------
# Generate HTML
#-------------------------------------------------------------------------------
echo ""
echo "Generating HTML report..."

cat > "$OUTPUT_FILE" << EOF
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>DSO Timing Report</title></head>
<body style="font-family: Arial, sans-serif; background-color: #f5f5f5; padding: 20px; margin: 0;">
<table width="100%" cellpadding="0" cellspacing="0" style="max-width: 1200px; margin: 0 auto; background-color: #ffffff; border: 1px solid #dddddd;">
<tr><td style="padding: 30px;">

<!-- Header -->
<table width="100%" cellpadding="0" cellspacing="0">
<tr><td style="background-color: #2c3e50; color: #ffffff; padding: 20px; text-align: center; font-size: 24px; font-weight: bold;">
DSO.ai totalCore Timing Results - ${RUN_NAME}
</td></tr>
<tr><td style="text-align: center; padding: 10px; color: #666666;">Generated: ${DATE_GENERATED}</td></tr>
</table>

<!-- Baseline -->
<table width="100%" cellpadding="15" cellspacing="0" style="margin: 20px 0;">
<tr><td style="background-color: #8e44ad; color: #ffffff; text-align: center; font-size: 16px; border-radius: 5px;">
<strong>BASELINE (${BASELINE_NAME}):</strong><br>
WNS = <span style="font-size: 24px; font-weight: bold;">${BASELINE_WNS} ps</span> &nbsp;|&nbsp;
TNS = <span style="font-size: 24px; font-weight: bold;">${BASELINE_TNS} ps</span>
</td></tr>
</table>

<!-- Summary Cards -->
<table width="100%" cellpadding="0" cellspacing="10" style="margin: 20px 0;">
<tr>
<td width="20%" style="background-color: #3498db; color: #ffffff; text-align: center; padding: 15px; border-radius: 5px;">
<div style="font-size: 12px;">Best WNS</div>
<div style="font-size: 22px; font-weight: bold; margin: 5px 0;">${BEST_WNS}ps</div>
<div style="font-size: 11px;">+${IMPROVEMENT_WNS}ps</div>
</td>
<td width="20%" style="background-color: #16a085; color: #ffffff; text-align: center; padding: 15px; border-radius: 5px;">
<div style="font-size: 12px;">Best TNS</div>
<div style="font-size: 18px; font-weight: bold; margin: 5px 0;">${BEST_TNS}ps</div>
<div style="font-size: 11px;">+${IMPROVEMENT_TNS}ps</div>
</td>
<td width="20%" style="background-color: #27ae60; color: #ffffff; text-align: center; padding: 15px; border-radius: 5px;">
<div style="font-size: 12px;">Better than Baseline</div>
<div style="font-size: 22px; font-weight: bold; margin: 5px 0;">${BETTER}/${COMPLETED}</div>
<div style="font-size: 11px;">lineages</div>
</td>
<td width="20%" style="background-color: #e67e22; color: #ffffff; text-align: center; padding: 15px; border-radius: 5px;">
<div style="font-size: 12px;">Progress</div>
<div style="font-size: 22px; font-weight: bold; margin: 5px 0;">${COMPLETED}/${TOTAL}</div>
<div style="font-size: 11px;">dat complete</div>
</td>
<td width="20%" style="background-color: #9b59b6; color: #ffffff; text-align: center; padding: 15px; border-radius: 5px;">
<div style="font-size: 12px;">Best Lineage</div>
<div style="font-size: 16px; font-weight: bold; margin: 5px 0;">${BEST_LINEAGE}</div>
</td>
</tr>
</table>

<!-- Better than Baseline -->
<table width="100%" cellpadding="0" cellspacing="0" style="margin-top: 30px;">
<tr><td style="background-color: #27ae60; color: #ffffff; padding: 12px 15px; font-size: 18px; font-weight: bold;">
Better than Baseline (${BETTER} lineages)
</td></tr>
</table>
<table width="100%" cellpadding="10" cellspacing="0" border="1" style="border-collapse: collapse; margin-bottom: 20px; border-color: #cccccc;">
<tr style="background-color: #34495e; color: #ffffff;">
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">Lineage</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">WNS (ps)</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">WNS Imp.</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">TNS (ps)</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">TNS Imp.</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">Key Permutons</th>
</tr>
EOF

# Add better rows
sort -t'|' -k2 -rn "$TMPDATA" | awk -F'|' -v base="$BASELINE_WNS" -v basetns="$BASELINE_TNS" -v best="$BEST_LINEAGE" '
$2 > base && $2 > -500 {
    wns_diff = $2 - base
    tns_diff = $3 - basetns

    if ($1 == best) {
        bg = "#d5f4e6"
        badge = " <span style=\"background-color: #27ae60; color: white; padding: 2px 6px; border-radius: 3px; font-size: 10px;\">BEST</span>"
    } else if (NR % 2 == 0) {
        bg = "#f9f9f9"
        badge = ""
    } else {
        bg = "#ffffff"
        badge = ""
    }

    gsub(/;/, ", ", $4)
    printf "<tr style=\"background-color: %s;\">\n", bg
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc;\"><strong>%s</strong>%s</td>\n", $1, badge
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc;\">%s</td>\n", $2
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc; color: #27ae60;\"><strong>+%.2fps</strong></td>\n", wns_diff
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc;\">%.2f</td>\n", $3
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc; color: %s;\"><strong>%s%.2fps</strong></td>\n", (tns_diff > 0 ? "#27ae60" : "#e74c3c"), (tns_diff > 0 ? "+" : ""), tns_diff
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc; font-family: monospace; font-size: 11px;\">%s</td>\n", $4
    printf "</tr>\n"
}' >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << EOF
</table>

<!-- Worse than Baseline -->
<table width="100%" cellpadding="0" cellspacing="0" style="margin-top: 30px;">
<tr><td style="background-color: #e74c3c; color: #ffffff; padding: 12px 15px; font-size: 18px; font-weight: bold;">
Worse than Baseline (${WORSE} lineages)
</td></tr>
</table>
<table width="100%" cellpadding="10" cellspacing="0" border="1" style="border-collapse: collapse; margin-bottom: 20px; border-color: #cccccc;">
<tr style="background-color: #34495e; color: #ffffff;">
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">Lineage</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">WNS (ps)</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">WNS Diff</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">TNS (ps)</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">TNS Diff</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">Key Permutons</th>
</tr>
EOF

# Add worse rows
sort -t'|' -k2 -rn "$TMPDATA" | awk -F'|' -v base="$BASELINE_WNS" -v basetns="$BASELINE_TNS" '
$2 <= base && $2 > -500 {
    wns_diff = $2 - base
    tns_diff = $3 - basetns
    gsub(/;/, ", ", $4)
    printf "<tr style=\"background-color: #fdeaea;\">\n"
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc;\">%s</td>\n", $1
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc;\">%s</td>\n", $2
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc; color: #e74c3c;\">%.2fps</td>\n", wns_diff
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc;\">%.2f</td>\n", $3
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc; color: %s;\">%s%.2fps</td>\n", (tns_diff > 0 ? "#27ae60" : "#e74c3c"), (tns_diff > 0 ? "+" : ""), tns_diff
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc; font-family: monospace; font-size: 11px;\">%s</td>\n", $4
    printf "</tr>\n"
}' >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << EOF
</table>

<!-- Outliers -->
<table width="100%" cellpadding="0" cellspacing="0" style="margin-top: 30px;">
<tr><td style="background-color: #f39c12; color: #ffffff; padding: 12px 15px; font-size: 18px; font-weight: bold;">
Timing Outliers (${OUTLIERS} lineages)
</td></tr>
</table>
<table width="100%" cellpadding="10" cellspacing="0" border="1" style="border-collapse: collapse; margin-bottom: 20px; border-color: #cccccc;">
<tr style="background-color: #34495e; color: #ffffff;">
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">Lineage</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">WNS (ps)</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">TNS (ps)</th>
<th style="padding: 12px; text-align: left; border: 1px solid #2c3e50;">Key Permutons</th>
</tr>
EOF

# Add outlier rows
awk -F'|' '$2 <= -500 {
    gsub(/;/, ", ", $4)
    printf "<tr style=\"background-color: #fff3cd;\">\n"
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc;\">%s</td>\n", $1
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc;\">%s</td>\n", $2
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc;\">%s</td>\n", $3
    printf "<td style=\"padding: 10px; border: 1px solid #cccccc; font-family: monospace; font-size: 11px;\">%s</td>\n", $4
    printf "</tr>\n"
}' "$TMPDATA" >> "$OUTPUT_FILE"

# Get best lineage permutons (field 4 now, after adding TNS)
BEST_PERMUTONS=$(grep "^${BEST_LINEAGE}|" "$TMPDATA" | cut -d'|' -f4 | tr ';' '\n')

cat >> "$OUTPUT_FILE" << EOF
</table>

<!-- Winner Box -->
<table width="100%" cellpadding="20" cellspacing="0" style="margin: 30px 0; background-color: #1abc9c; border-radius: 5px;">
<tr><td style="color: #ffffff;">
<div style="font-size: 20px; font-weight: bold; margin-bottom: 15px;">Winning Permuton Combination (${BEST_LINEAGE})</div>
<table width="100%" cellpadding="8" cellspacing="0" border="1" style="border-collapse: collapse; border-color: rgba(255,255,255,0.3);">
<tr>
<th style="padding: 10px; text-align: left; border: 1px solid rgba(255,255,255,0.3); color: #ffffff; background-color: rgba(0,0,0,0.1);">Permuton</th>
<th style="padding: 10px; text-align: left; border: 1px solid rgba(255,255,255,0.3); color: #ffffff; background-color: rgba(0,0,0,0.1);">Value</th>
</tr>
EOF

# Add permuton rows
echo "$BEST_PERMUTONS" | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    pname=$(echo "$line" | awk '{print $1}')
    pval=$(echo "$line" | awk '{print $2}')
    cat >> "$OUTPUT_FILE" << EOF
<tr>
<td style="padding: 8px; border: 1px solid rgba(255,255,255,0.3); color: #ffffff;">$pname</td>
<td style="padding: 8px; border: 1px solid rgba(255,255,255,0.3); color: #ffffff;"><strong>$pval</strong></td>
</tr>
EOF
done

cat >> "$OUTPUT_FILE" << EOF
</table>
<div style="margin-top: 15px;">
<strong>WNS:</strong> ${BEST_WNS} ps (+${IMPROVEMENT_WNS} ps) &nbsp;|&nbsp;
<strong>TNS:</strong> ${BEST_TNS} ps (+${IMPROVEMENT_TNS} ps)
</div>
</td></tr>
</table>

<!-- Footer -->
<table width="100%" cellpadding="15" cellspacing="0" style="margin-top: 20px;">
<tr><td style="text-align: center; color: #999999; font-size: 12px; border-top: 1px solid #eeeeee;">
Generated by DSO Timing Report Script | ${DATE_GENERATED}
</td></tr>
</table>

</td></tr>
</table>
</body>
</html>
EOF

#-------------------------------------------------------------------------------
# Generate Text Report
#-------------------------------------------------------------------------------
TEXT_FILE="${OUTPUT_FILE%.html}.txt"

cat > "$TEXT_FILE" << EOF
================================================================================
                    DSO.ai Pass_${PASS_NUM} Timing Report
================================================================================
Run:      ${RUN_NAME}
Baseline: ${BASELINE_NAME}
Generated: ${DATE_GENERATED}

--------------------------------------------------------------------------------
BASELINE TIMING (${TIMING_MODE})
--------------------------------------------------------------------------------
  WNS: ${BASELINE_WNS} ps
  TNS: ${BASELINE_TNS} ps

--------------------------------------------------------------------------------
SUMMARY
--------------------------------------------------------------------------------
  Best Lineage:     ${BEST_LINEAGE}
  Best WNS:         ${BEST_WNS} ps (+${IMPROVEMENT_WNS} ps)
  Best TNS:         ${BEST_TNS} ps (+${IMPROVEMENT_TNS} ps)
  Progress:         ${COMPLETED}/${TOTAL} lineages complete
  Better/Worse:     ${BETTER} better, ${WORSE} worse, ${OUTLIERS} outliers

--------------------------------------------------------------------------------
BETTER THAN BASELINE (${BETTER} lineages)
--------------------------------------------------------------------------------
EOF

printf "%-12s %12s %12s %16s %14s  %-s\n" "LINEAGE" "WNS(ps)" "WNS_IMP" "TNS(ps)" "TNS_IMP" "PERMUTONS" >> "$TEXT_FILE"
printf "%-12s %12s %12s %16s %14s  %-s\n" "--------" "--------" "--------" "------------" "----------" "----------" >> "$TEXT_FILE"

sort -t'|' -k2 -rn "$TMPDATA" | awk -F'|' -v base="$BASELINE_WNS" -v basetns="$BASELINE_TNS" -v best="$BEST_LINEAGE" '
$2 > base && $2 > -500 {
    wns_diff = $2 - base
    tns_diff = $3 - basetns
    tag = ($1 == best) ? "*" : " "
    gsub(/;/, ", ", $4)
    permutons = substr($4, 1, 50)
    if (length($4) > 50) permutons = permutons "..."
    printf "%s%-11s %12.2f %+12.2f %16.2f %+14.2f  %s\n", tag, $1, $2, wns_diff, $3, tns_diff, permutons
}' >> "$TEXT_FILE"

cat >> "$TEXT_FILE" << EOF

--------------------------------------------------------------------------------
WORSE THAN BASELINE (${WORSE} lineages)
--------------------------------------------------------------------------------
EOF

printf "%-12s %12s %12s %16s %14s  %-s\n" "LINEAGE" "WNS(ps)" "WNS_DIFF" "TNS(ps)" "TNS_DIFF" "PERMUTONS" >> "$TEXT_FILE"
printf "%-12s %12s %12s %16s %14s  %-s\n" "--------" "--------" "--------" "------------" "----------" "----------" >> "$TEXT_FILE"

sort -t'|' -k2 -rn "$TMPDATA" | awk -F'|' -v base="$BASELINE_WNS" -v basetns="$BASELINE_TNS" '
$2 <= base && $2 > -500 {
    wns_diff = $2 - base
    tns_diff = $3 - basetns
    gsub(/;/, ", ", $4)
    permutons = substr($4, 1, 50)
    if (length($4) > 50) permutons = permutons "..."
    printf " %-11s %12.2f %+12.2f %16.2f %+14.2f  %s\n", $1, $2, wns_diff, $3, tns_diff, permutons
}' >> "$TEXT_FILE"

cat >> "$TEXT_FILE" << EOF

--------------------------------------------------------------------------------
TIMING OUTLIERS (${OUTLIERS} lineages)
--------------------------------------------------------------------------------
EOF

printf "%-12s %12s %16s  %-s\n" "LINEAGE" "WNS(ps)" "TNS(ps)" "PERMUTONS" >> "$TEXT_FILE"
printf "%-12s %12s %16s  %-s\n" "--------" "--------" "------------" "----------" >> "$TEXT_FILE"

awk -F'|' '$2 <= -500 {
    gsub(/;/, ", ", $4)
    permutons = substr($4, 1, 50)
    if (length($4) > 50) permutons = permutons "..."
    printf " %-11s %12s %16s  %s\n", $1, $2, $3, permutons
}' "$TMPDATA" >> "$TEXT_FILE"

cat >> "$TEXT_FILE" << EOF

--------------------------------------------------------------------------------
WINNING PERMUTON COMBINATION (${BEST_LINEAGE})
--------------------------------------------------------------------------------
EOF

echo "$BEST_PERMUTONS" | while IFS= read -r line; do
    [[ -n "$line" ]] && echo "  $line" >> "$TEXT_FILE"
done

cat >> "$TEXT_FILE" << EOF

  Results: WNS ${BEST_WNS} ps (+${IMPROVEMENT_WNS} ps) | TNS ${BEST_TNS} ps (+${IMPROVEMENT_TNS} ps)

================================================================================
                         Generated by DSO Timing Report Script
================================================================================
EOF

# Cleanup
rm -f "$TMPDATA"

echo "Report saved: $OUTPUT_FILE"
echo "Text report:  $TEXT_FILE"

# Send email if requested
if [[ -n "$EMAIL" ]]; then
    echo "Sending email to $EMAIL..."
    SUBJECT="DSO.ai $RUN_NAME pass_$PASS_NUM Report - $(date '+%d %b %Y')"
    (
    echo "To: $EMAIL"
    echo "Subject: $SUBJECT"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=UTF-8"
    echo ""
    cat "$OUTPUT_FILE"
    ) | /usr/sbin/sendmail -t
    echo "Email sent!"
fi

echo ""
echo "========================================"
echo "Summary: Best=$BEST_LINEAGE WNS=$BEST_WNS (+${IMPROVEMENT_WNS}ps)"
echo "========================================"
