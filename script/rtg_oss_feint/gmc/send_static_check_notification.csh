#!/bin/tcsh
# Script to send email notification when static check completes for GMC
# Usage: send_static_check_notification.csh <source_dir> <tag> <tile_name> <checktype_name> <temp_spec_file> [ip_name] [email_override]

if ($#argv < 5) then
    echo "Usage: $0 <source_dir> <tag> <tile_name> <checktype_name> <temp_spec_file> [ip_name] [email_override]"
    exit 1
endif

set source_dir = $1
set tag = $2
set tile_name = $3
set checktype_name = $4
set temp_spec_file = $5
set passed_ip_name = ""
if ($#argv >= 6) then
    set passed_ip_name = $6
endif
set email_override = ""
if ($#argv >= 7) then
    set email_override = $7
endif

echo "========================================================================"
echo "Sending GMC static check notification email..."
echo "Tag: $tag"
echo "Tile: $tile_name"
echo "Check Type: $checktype_name"
echo "========================================================================"

# Map checktype to friendly name
if ("$checktype_name" == "lint") then
    set check_display = "Lint"
else if ("$checktype_name" == "cdc_rdc") then
    set check_display = "CDC/RDC"
else if ("$checktype_name" == "spg_dft") then
    set check_display = "Spyglass DFT"
else
    set check_display = "$checktype_name"
endif

# Create notification spec file
set notify_spec = "${source_dir}/data/${tag}_${checktype_name}_notify.spec"
rm -f $notify_spec

# Append the analysis results from temp spec
if (-f $temp_spec_file && -s $temp_spec_file) then
    cat $temp_spec_file >> $notify_spec
else
    echo "#text#" >> $notify_spec
    echo "WARNING: No analysis results found" >> $notify_spec
endif

echo "" >> $notify_spec

# Get VTO name
source ${source_dir}/csh/env.csh
set vto = `cat assignment.csv | grep "vto," | head -n 1 | awk -F ',' '{print $2}' | sed 's/\r//g'`

# Add signature
echo "" >> $notify_spec
echo "Thanks," >> $notify_spec
echo "Genie AI Agent ($vto)" >> $notify_spec
echo "" >> $notify_spec
echo "#line#" >> $notify_spec

# Convert spec to HTML - first create a temporary spec with proper email format
set email_spec = "${source_dir}/data/${tag}_${checktype_name}_email.spec"
rm -f $email_spec

# Create email-formatted spec
echo "#text#" > $email_spec
cat $notify_spec >> $email_spec

# Add quote section for email threading
echo "#text#" >> $email_spec
echo "-----Original Message-----" >> $email_spec

# Get original email body if available
set mail_body = `python ${source_dir}/py/readTask.py --tasksModelFile tasksModel.csv --tag $tag --item mailBody |& grep -v "Traceback" | tail -1`
if ("$mail_body" != "" && "$mail_body" != "None") then
    echo "$mail_body" >> $email_spec
endif

# Convert to HTML
set notify_html = "${source_dir}/data/${tag}_${checktype_name}_notify.html"
python ${source_dir}/py/spec2Html.py --spec $email_spec --html $notify_html

# Send email directly using formail + sendmail
echo "Sending notification email directly..."

# Check for email override (from --to flag in genie_cli.py)
set recipients = ""

# First check if email_override was passed as parameter
if ("$email_override" != "") then
    set recipients = "$email_override"
    echo "Using email override: $recipients"
# Then check for email override file
else if (-f "${source_dir}/data/${tag}_email") then
    set override_content = `cat ${source_dir}/data/${tag}_email | head -1`
    if ("$override_content" != "" && "$override_content" != "default") then
        set recipients = "$override_content"
        echo "Using email override from file: $recipients"
    endif
endif

# If no override, get ALL recipients from assignment.csv (manager + all debuggers)
if ("$recipients" == "") then
    # Get manager
    set manager = `cat assignment.csv | grep "manager," | head -n 1 | awk -F ',' '{print $2}' | sed 's/\r//g'`
    if ("$manager" != "") then
        set recipients = "$manager"
    endif

    # Get ALL debuggers (not just the first one)
    foreach debugger_line (`cat assignment.csv | grep "debugger," | awk -F ',' '{print $2}' | sed 's/\r//g'`)
        if ("$recipients" != "") then
            set recipients = "${recipients},${debugger_line}"
        else
            set recipients = "$debugger_line"
        endif
    end

    # Get original sender from tasksModel if available
    set sender_email = `python ${source_dir}/py/readTask.py --tasksModelFile tasksModel.csv --tag $tag --item sender |& grep -v "Traceback" | tail -1`
    if ("$sender_email" != "" && "$sender_email" != "None") then
        if ("$recipients" != "") then
            set recipients = "${recipients},${sender_email}"
        else
            set recipients = "$sender_email"
        endif
    endif
endif

# Build descriptive subject
# Format: DDMon HH:MM - PROJECT IP CHECK_TYPE (tag) (Status)

# Get current datetime
set datetime_str = `date "+%d%b %H:%M"`

# Get IP from passed parameter, task spec, or assignment.csv
if ("$passed_ip_name" != "") then
    set ip_name = "$passed_ip_name"
else
    # Try email tasks model first
    if (-f "${source_dir}/tasksModel.csv") then
        set ip_name = `python ${source_dir}/py/readTask.py --tasksModelFile tasksModel.csv --tag $tag --item ip |& grep -v "Traceback\|Error\|No such file" | tail -1`
    endif
    if ("$ip_name" == "" || "$ip_name" == "None") then
        # Try CLI tasks model
        if (-f "${source_dir}/tasksModelCLI.csv") then
            set ip_name = `python ${source_dir}/py/readTask.py --tasksModelFile tasksModelCLI.csv --tag $tag --item ip |& grep -v "Traceback\|Error\|No such file" | tail -1`
        endif
    endif
    if ("$ip_name" == "" || "$ip_name" == "None") then
        set ip_name = `cat assignment.csv | grep "ip," | head -n 1 | awk -F ',' '{print $2}' | sed 's/\r//g'`
    endif
endif

# Get project name from project.list based on IP
set project_list_file = "${source_dir}/script/rtg_oss_feint/project.list"
set project_name = ""
if (-f $project_list_file && "$ip_name" != "") then
    set project_name = `grep "^${ip_name}," $project_list_file | head -1 | awk -F',' '{print $2}' | sed 's/\r//g' | tr '[:lower:]' '[:upper:]'`
endif
# Fallback to assignment.csv if not found in project.list
if ("$project_name" == "") then
    set project_name = `cat assignment.csv | grep "project," | head -n 1 | awk -F ',' '{print $2}' | sed 's/\r//g' | tr '[:lower:]' '[:upper:]'`
endif

# Determine status from spec file content
set status = "Completed"
if (-f $temp_spec_file) then
    # Check for error indicators
    set has_errors = `grep -i -E "error|fail|violation" $temp_spec_file | grep -v "0 error" | grep -v "0 fail" | head -1`
    if ("$has_errors" != "") then
        set status = "Has Issues"
    endif
endif

# Map checktype to display name (uppercase)
set check_type_upper = `echo "$checktype_name" | tr '[:lower:]' '[:upper:]' | sed 's/_/\//g'`

# Build subject
if ("$project_name" != "" && "$ip_name" != "") then
    set subject = "${datetime_str} - ${project_name} ${ip_name} ${check_type_upper} (${tag}) (${status})"
else if ("$ip_name" != "") then
    set subject = "${datetime_str} - ${ip_name} ${check_type_upper} (${tag}) (${status})"
else
    set subject = "${datetime_str} - ${check_type_upper} (${tag}) (${status})"
endif

# Remove duplicate email addresses from recipients list
if ("$recipients" != "") then
    echo "$recipients" | tr ',' '\n' | sort -u > /tmp/recipients_unique_$$.tmp
    set recipients = `cat /tmp/recipients_unique_$$.tmp | tr '\n' ',' | sed 's/,$//'`
    rm -f /tmp/recipients_unique_$$.tmp
endif

echo "DEBUG: recipients = $recipients"
echo "DEBUG: subject = $subject"

# Send email using formail + sendmail
if ("$recipients" != "") then
    cat $notify_html | formail -I "To: $recipients" -I "From: Genie AI Agent <${vto}@atlmail.amd.com>" -I "MIME-Version: 1.0" -I "Content-type: text/html; charset=utf-8" -I "Subject: $subject" | /sbin/sendmail -oi $recipients

    set mail_exit_status = $?
    if ($mail_exit_status == 0) then
        echo "GMC static check notification email sent successfully to: $recipients"
    else
        echo "Failed to send GMC static check notification email (exit code: $mail_exit_status)"
    endif
else
    echo "WARNING: No recipients found - email not sent"
endif

# Cleanup temp files
rm -f $temp_spec_file

echo "========================================================================"
