#!/bin/bash
################################################################################
# DSO Error Check Script (One-shot)
# Checks for DSO errors and sends email notification once
# Usage: ./dso_error_check.sh <tile_dir>
################################################################################

EMAIL="Azman.BinBabah@amd.com"
ERROR_CODES="DSO-6804|CMD-010|CMD-012"

# Parse arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <tile_dir>"
    exit 1
fi

TILE_DIR="$1"
LOG_DIR="${TILE_DIR}/data/CrlFlow/work"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

echo "=============================================="
echo "DSO Error Check - ${TIMESTAMP}"
echo "Tile: ${TILE_DIR}"
echo "=============================================="

# Check if log directory exists
if [ ! -d "${LOG_DIR}" ]; then
    echo "Error: Log directory not found: ${LOG_DIR}"
    exit 1
fi

# Count lineages
TOTAL_LINEAGES=$(ls -d ${LOG_DIR}/.run_*/ 2>/dev/null | wc -l)
echo "Total lineages: ${TOTAL_LINEAGES}"

if [ "$TOTAL_LINEAGES" -eq 0 ]; then
    echo "No lineages found."
    exit 0
fi

# Check for errors
ERROR_FILE="/tmp/dso_errors_$$.txt"
grep -l -E "${ERROR_CODES}" ${LOG_DIR}/.run_*/FxSynthesize_*.log > ${ERROR_FILE} 2>/dev/null
ERROR_LINEAGES=$(cat ${ERROR_FILE} | wc -l)

# Get error counts per type
DSO_6804_COUNT=$(grep -h "DSO-6804" ${LOG_DIR}/.run_*/FxSynthesize_*.log 2>/dev/null | wc -l)
CMD_010_COUNT=$(grep -h "CMD-010" ${LOG_DIR}/.run_*/FxSynthesize_*.log 2>/dev/null | wc -l)
CMD_012_COUNT=$(grep -h "CMD-012" ${LOG_DIR}/.run_*/FxSynthesize_*.log 2>/dev/null | wc -l)
TOTAL_ERRORS=$((DSO_6804_COUNT + CMD_010_COUNT + CMD_012_COUNT))

echo "Lineages with errors: ${ERROR_LINEAGES}"
echo "DSO-6804: ${DSO_6804_COUNT}"
echo "CMD-010: ${CMD_010_COUNT}"
echo "CMD-012: ${CMD_012_COUNT}"
echo "Total errors: ${TOTAL_ERRORS}"

if [ "$TOTAL_ERRORS" -gt 0 ]; then
    echo ""
    echo "Sending email to ${EMAIL}..."

    # Create HTML email body
    EMAIL_HTML="/tmp/dso_email_$$.html"
    TILE_NAME=$(basename ${TILE_DIR})

    # Get affected lineages
    AFFECTED_LINEAGES=$(cat ${ERROR_FILE} | xargs -I{} dirname {} | xargs -I{} basename {} | tr '\n' '<br>')

    # Get sample errors
    SAMPLE_ERRORS=$(grep -h -E "${ERROR_CODES}" ${LOG_DIR}/.run_*/FxSynthesize_*.log 2>/dev/null | head -10 | sed 's/</\&lt;/g; s/>/\&gt;/g' | tr '\n' '#' | sed 's/#/<br>/g')

    cat > ${EMAIL_HTML} << EOF
<!DOCTYPE html>
<html>
<head>
<style>
body { font-family: Arial, sans-serif; font-size: 14px; }
h2 { color: #cc0000; }
table { border-collapse: collapse; margin: 10px 0; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background-color: #4472c4; color: white; }
tr:nth-child(even) { background-color: #f2f2f2; }
.error { color: #cc0000; font-weight: bold; }
.ok { color: #00aa00; }
pre { background-color: #f5f5f5; padding: 10px; border: 1px solid #ddd; overflow-x: auto; }
</style>
</head>
<body>

<h2>⚠️ DSO Error Alert</h2>

<p><strong>Time:</strong> ${TIMESTAMP}<br>
<strong>Tile:</strong> ${TILE_DIR}</p>

<h3>Error Summary</h3>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Total Lineages</td><td>${TOTAL_LINEAGES}</td></tr>
<tr><td>Lineages with Errors</td><td class="error">${ERROR_LINEAGES}</td></tr>
</table>

<h3>Error Counts</h3>
<table>
<tr><th>Error Code</th><th>Count</th><th>Description</th></tr>
<tr><td>DSO-6804</td><td class="error">${DSO_6804_COUNT}</td><td>Proc failure during before/after evaluation</td></tr>
<tr><td>CMD-010</td><td class="error">${CMD_010_COUNT}</td><td>Unknown option in command</td></tr>
<tr><td>CMD-012</td><td class="error">${CMD_012_COUNT}</td><td>Extra positional option</td></tr>
<tr><td><strong>TOTAL</strong></td><td class="error"><strong>${TOTAL_ERRORS}</strong></td><td></td></tr>
</table>

<h3>Affected Lineages</h3>
<p>${AFFECTED_LINEAGES}</p>

<h3>Sample Errors</h3>
<pre>${SAMPLE_ERRORS}</pre>

<h3>Quick Fix Reference</h3>
<table>
<tr><th>Error</th><th>Fix</th></tr>
<tr><td>DSO-6804</td><td>Use {args} + parse_proc_arguments + define_proc_attributes</td></tr>
<tr><td>CMD-010</td><td>Check command syntax (e.g., set_boundary_optimization \$cells all)</td></tr>
<tr><td>CMD-012</td><td>Remove deprecated options</td></tr>
</table>

<p>See: <code>dso_timing_enhancement/DSO_ERRORS.txt</code> for detailed fixes.</p>

<hr>
<p style="color: #888; font-size: 12px;">This is an automated message from DSO Error Monitor</p>

</body>
</html>
EOF

    # Send email using formail + sendmail (same method as timing notification)
    SUBJECT="[DSO Alert] ${TILE_NAME}: ${ERROR_LINEAGES}/${TOTAL_LINEAGES} lineages with ${TOTAL_ERRORS} errors"

    cat ${EMAIL_HTML} | formail \
        -I "To: ${EMAIL}" \
        -I "From: DSO Error Monitor <noreply@amd.com>" \
        -I "MIME-Version: 1.0" \
        -I "Content-type: text/html; charset=utf-8" \
        -I "Subject: ${SUBJECT}" \
        | /sbin/sendmail -oi ${EMAIL}

    MAIL_STATUS=$?
    if [ $MAIL_STATUS -eq 0 ]; then
        echo "Email sent successfully!"
    else
        echo "Failed to send email (exit code: $MAIL_STATUS)"
    fi

    rm -f ${EMAIL_HTML}
else
    echo ""
    echo "No DSO errors found. All clean!"
fi

rm -f ${ERROR_FILE}
