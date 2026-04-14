#!/bin/bash
################################################################################
# DSO Error Monitor Script (Continuous)
# Checks for DSO errors every N minutes and sends HTML email notification
# Usage: ./dso_error_monitor.sh <tile_dir> [interval_minutes]
# Example: nohup ./dso_error_monitor.sh /proj/.../tile 30 &
################################################################################

EMAIL="Azman.BinBabah@amd.com"
ERROR_CODES="DSO-6804|CMD-010|CMD-012"

# Parse arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <tile_dir> [interval_minutes]"
    echo "Example: $0 /proj/.../umccmd_DSO_28Jan_40p 30"
    exit 1
fi

TILE_DIR="$1"
INTERVAL=${2:-30}
LOG_DIR="${TILE_DIR}/data/CrlFlow/work"
STATE_FILE="/tmp/dso_monitor_$(basename ${TILE_DIR}).state"
TILE_NAME=$(basename ${TILE_DIR})

echo "=============================================="
echo "DSO Error Monitor Started"
echo "Tile: ${TILE_DIR}"
echo "Interval: ${INTERVAL} minutes"
echo "Email: ${EMAIL}"
echo "=============================================="

# Main monitoring loop
while true; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo ""
    echo "[$TIMESTAMP] Checking for DSO errors..."

    # Check if log directory exists
    if [ ! -d "${LOG_DIR}" ]; then
        echo "  Warning: Log directory not found: ${LOG_DIR}"
        echo "  Waiting for DSO run to start..."
        sleep $((INTERVAL * 60))
        continue
    fi

    # Count lineages
    TOTAL_LINEAGES=$(ls -d ${LOG_DIR}/.run_*/ 2>/dev/null | wc -l)
    if [ "$TOTAL_LINEAGES" -eq 0 ]; then
        echo "  No lineages found yet. Waiting..."
        sleep $((INTERVAL * 60))
        continue
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

    echo "  Total lineages: ${TOTAL_LINEAGES}"
    echo "  Lineages with errors: ${ERROR_LINEAGES}"
    echo "  DSO-6804: ${DSO_6804_COUNT}, CMD-010: ${CMD_010_COUNT}, CMD-012: ${CMD_012_COUNT}"

    # Check if we already notified for this error count
    PREV_ERRORS=0
    if [ -f "${STATE_FILE}" ]; then
        PREV_ERRORS=$(cat ${STATE_FILE})
    fi

    # Send email if new errors found
    if [ "$TOTAL_ERRORS" -gt 0 ] && [ "$TOTAL_ERRORS" -ne "$PREV_ERRORS" ]; then
        echo "  New errors detected! Sending email..."

        # Create HTML email body
        EMAIL_HTML="/tmp/dso_email_$$.html"

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
<p style="color: #888; font-size: 12px;">This is an automated message from DSO Error Monitor (checking every ${INTERVAL} minutes)</p>

</body>
</html>
EOF

        # Send email using formail + sendmail
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
            echo "  Email sent to ${EMAIL}"
        else
            echo "  Failed to send email (exit code: $MAIL_STATUS)"
        fi

        rm -f ${EMAIL_HTML}

        # Save state
        echo ${TOTAL_ERRORS} > ${STATE_FILE}
    elif [ "$TOTAL_ERRORS" -eq 0 ]; then
        echo "  No DSO errors found. All clean!"
        echo 0 > ${STATE_FILE}
    else
        echo "  Error count unchanged (${TOTAL_ERRORS}). No email sent."
    fi

    rm -f ${ERROR_FILE}

    echo "  Next check in ${INTERVAL} minutes..."
    sleep $((INTERVAL * 60))
done
