#!/bin/csh -f
################################################################################
# DSO Error Monitor Script
# Checks for DSO errors and sends email notification
# Usage: ./dso_error_monitor.csh <tile_dir> [interval_minutes]
# Example: ./dso_error_monitor.csh /proj/.../umccmd_DSO_28Jan_40p 30
################################################################################

set EMAIL = "abinbaba@amd.com"
set ERROR_CODES = "DSO-6804|CMD-010|CMD-012"

# Parse arguments
if ($#argv < 1) then
    echo "Usage: $0 <tile_dir> [interval_minutes]"
    echo "Example: $0 /proj/.../umccmd_DSO_28Jan_40p 30"
    exit 1
endif

set TILE_DIR = $1
set INTERVAL = 30
if ($#argv >= 2) then
    set INTERVAL = $2
endif

set LOG_DIR = "${TILE_DIR}/data/CrlFlow/work"
set SCRIPT_DIR = `dirname $0`
set STATE_FILE = "/tmp/dso_monitor_`basename ${TILE_DIR}`.state"

echo "=============================================="
echo "DSO Error Monitor Started"
echo "Tile: ${TILE_DIR}"
echo "Interval: ${INTERVAL} minutes"
echo "Email: ${EMAIL}"
echo "=============================================="

# Main monitoring loop
while (1)
    set TIMESTAMP = `date "+%Y-%m-%d %H:%M:%S"`
    echo ""
    echo "[$TIMESTAMP] Checking for DSO errors..."

    # Check if log directory exists
    if (! -d "${LOG_DIR}") then
        echo "  Warning: Log directory not found: ${LOG_DIR}"
        echo "  Waiting for DSO run to start..."
        sleep `expr ${INTERVAL} \* 60`
        continue
    endif

    # Count lineages
    set TOTAL_LINEAGES = `ls -d ${LOG_DIR}/.run_*/ 2>/dev/null | wc -l`
    if ($TOTAL_LINEAGES == 0) then
        echo "  No lineages found yet. Waiting..."
        sleep `expr ${INTERVAL} \* 60`
        continue
    endif

    # Check for errors
    set ERROR_FILE = "/tmp/dso_errors_$$.txt"
    grep -l -E "${ERROR_CODES}" ${LOG_DIR}/.run_*/FxSynthesize_*.log >& ${ERROR_FILE}
    set ERROR_LINEAGES = `cat ${ERROR_FILE} | wc -l`

    # Get error counts per type
    set DSO_6804_COUNT = `grep -h "DSO-6804" ${LOG_DIR}/.run_*/FxSynthesize_*.log 2>/dev/null | wc -l`
    set CMD_010_COUNT = `grep -h "CMD-010" ${LOG_DIR}/.run_*/FxSynthesize_*.log 2>/dev/null | wc -l`
    set CMD_012_COUNT = `grep -h "CMD-012" ${LOG_DIR}/.run_*/FxSynthesize_*.log 2>/dev/null | wc -l`
    set TOTAL_ERRORS = `expr ${DSO_6804_COUNT} + ${CMD_010_COUNT} + ${CMD_012_COUNT}`

    echo "  Total lineages: ${TOTAL_LINEAGES}"
    echo "  Lineages with errors: ${ERROR_LINEAGES}"
    echo "  DSO-6804: ${DSO_6804_COUNT}, CMD-010: ${CMD_010_COUNT}, CMD-012: ${CMD_012_COUNT}"

    # Check if we already notified for this error count
    set PREV_ERRORS = 0
    if (-f ${STATE_FILE}) then
        set PREV_ERRORS = `cat ${STATE_FILE}`
    endif

    # Send email if new errors found
    if ($TOTAL_ERRORS > 0 && $TOTAL_ERRORS != $PREV_ERRORS) then
        echo "  New errors detected! Sending email..."

        # Create email body
        set EMAIL_BODY = "/tmp/dso_email_$$.txt"
        echo "DSO Error Alert - ${TIMESTAMP}" > ${EMAIL_BODY}
        echo "" >> ${EMAIL_BODY}
        echo "Tile: ${TILE_DIR}" >> ${EMAIL_BODY}
        echo "" >> ${EMAIL_BODY}
        echo "Error Summary:" >> ${EMAIL_BODY}
        echo "  Total Lineages: ${TOTAL_LINEAGES}" >> ${EMAIL_BODY}
        echo "  Lineages with Errors: ${ERROR_LINEAGES}" >> ${EMAIL_BODY}
        echo "" >> ${EMAIL_BODY}
        echo "Error Counts:" >> ${EMAIL_BODY}
        echo "  DSO-6804 (proc failure): ${DSO_6804_COUNT}" >> ${EMAIL_BODY}
        echo "  CMD-010 (unknown option): ${CMD_010_COUNT}" >> ${EMAIL_BODY}
        echo "  CMD-012 (extra positional): ${CMD_012_COUNT}" >> ${EMAIL_BODY}
        echo "" >> ${EMAIL_BODY}
        echo "Affected Lineages:" >> ${EMAIL_BODY}
        cat ${ERROR_FILE} | xargs -I{} dirname {} | xargs -I{} basename {} >> ${EMAIL_BODY}
        echo "" >> ${EMAIL_BODY}
        echo "Sample Errors:" >> ${EMAIL_BODY}
        grep -h -E "${ERROR_CODES}" ${LOG_DIR}/.run_*/FxSynthesize_*.log 2>/dev/null | head -10 >> ${EMAIL_BODY}
        echo "" >> ${EMAIL_BODY}
        echo "---" >> ${EMAIL_BODY}
        echo "This is an automated message from DSO Error Monitor" >> ${EMAIL_BODY}

        # Send email
        mail -s "DSO Error Alert: `basename ${TILE_DIR}` - ${ERROR_LINEAGES}/${TOTAL_LINEAGES} lineages with errors" ${EMAIL} < ${EMAIL_BODY}

        echo "  Email sent to ${EMAIL}"
        rm -f ${EMAIL_BODY}

        # Save state
        echo ${TOTAL_ERRORS} > ${STATE_FILE}
    else if ($TOTAL_ERRORS == 0) then
        echo "  No DSO errors found. All clean!"
        echo 0 > ${STATE_FILE}
    else
        echo "  Error count unchanged (${TOTAL_ERRORS}). No email sent."
    endif

    rm -f ${ERROR_FILE}

    echo "  Next check in ${INTERVAL} minutes..."
    sleep `expr ${INTERVAL} \* 60`
end
