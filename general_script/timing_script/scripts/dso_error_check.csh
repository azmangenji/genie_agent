#!/bin/csh -f
################################################################################
# DSO Error Check Script (One-shot)
# Checks for DSO errors and sends email notification once
# Usage: ./dso_error_check.csh <tile_dir>
################################################################################

set EMAIL = "abinbaba@amd.com"
set ERROR_CODES = "DSO-6804|CMD-010|CMD-012"

# Parse arguments
if ($#argv < 1) then
    echo "Usage: $0 <tile_dir>"
    exit 1
endif

set TILE_DIR = $1
set LOG_DIR = "${TILE_DIR}/data/CrlFlow/work"
set TIMESTAMP = `date "+%Y-%m-%d %H:%M:%S"`

echo "=============================================="
echo "DSO Error Check - ${TIMESTAMP}"
echo "Tile: ${TILE_DIR}"
echo "=============================================="

# Check if log directory exists
if (! -d "${LOG_DIR}") then
    echo "Error: Log directory not found: ${LOG_DIR}"
    exit 1
endif

# Count lineages
set TOTAL_LINEAGES = `ls -d ${LOG_DIR}/.run_*/ 2>/dev/null | wc -l`
echo "Total lineages: ${TOTAL_LINEAGES}"

if ($TOTAL_LINEAGES == 0) then
    echo "No lineages found."
    exit 0
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

echo "Lineages with errors: ${ERROR_LINEAGES}"
echo "DSO-6804: ${DSO_6804_COUNT}"
echo "CMD-010: ${CMD_010_COUNT}"
echo "CMD-012: ${CMD_012_COUNT}"
echo "Total errors: ${TOTAL_ERRORS}"

if ($TOTAL_ERRORS > 0) then
    echo ""
    echo "Sending email to ${EMAIL}..."

    # Create email body
    set EMAIL_BODY = "/tmp/dso_email_$$.txt"

    cat > ${EMAIL_BODY} << EMAILEOF
================================================================================
DSO ERROR ALERT
================================================================================

Time: ${TIMESTAMP}
Tile: ${TILE_DIR}

--------------------------------------------------------------------------------
ERROR SUMMARY
--------------------------------------------------------------------------------
Total Lineages:        ${TOTAL_LINEAGES}
Lineages with Errors:  ${ERROR_LINEAGES}

Error Counts:
  DSO-6804 (proc failure):    ${DSO_6804_COUNT}
  CMD-010 (unknown option):   ${CMD_010_COUNT}
  CMD-012 (extra positional): ${CMD_012_COUNT}
  ----------------------------------------
  TOTAL:                      ${TOTAL_ERRORS}

--------------------------------------------------------------------------------
AFFECTED LINEAGES
--------------------------------------------------------------------------------
EMAILEOF

    cat ${ERROR_FILE} | xargs -I{} dirname {} | xargs -I{} basename {} >> ${EMAIL_BODY}

    cat >> ${EMAIL_BODY} << EMAILEOF2

--------------------------------------------------------------------------------
SAMPLE ERRORS (first 15)
--------------------------------------------------------------------------------
EMAILEOF2

    grep -h -E "${ERROR_CODES}" ${LOG_DIR}/.run_*/FxSynthesize_*.log 2>/dev/null | head -15 >> ${EMAIL_BODY}

    cat >> ${EMAIL_BODY} << EMAILEOF3

--------------------------------------------------------------------------------
ERROR REFERENCE
--------------------------------------------------------------------------------
DSO-6804: Proc signature issue - use {args} + parse_proc_arguments
CMD-010:  Unknown option - check command syntax
CMD-012:  Extra positional option - deprecated syntax

See: dso_timing_enhancement/DSO_ERRORS.txt for fixes

================================================================================
This is an automated message from DSO Error Monitor
================================================================================
EMAILEOF3

    # Send email
    mail -s "[DSO Alert] `basename ${TILE_DIR}`: ${ERROR_LINEAGES}/${TOTAL_LINEAGES} lineages with ${TOTAL_ERRORS} errors" ${EMAIL} < ${EMAIL_BODY}

    echo "Email sent!"
    rm -f ${EMAIL_BODY}
else
    echo ""
    echo "No DSO errors found. All clean!"
endif

rm -f ${ERROR_FILE}
