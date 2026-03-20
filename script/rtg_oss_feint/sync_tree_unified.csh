#!/bin/tcsh
# Top-level unified sync tree entry point for UMC, OSS, and GMC
# Auto-detects project type based on IP name and routes to appropriate script
# Usage: sync_tree_unified.csh <refDir> <ip> <CL> <tag> <p4File>

set refDir = $1
set ip = $2
set CL = $3
set tag = $4
set p4File = $5
set source_dir = `pwd`

# Parse IP name to detect project type
set ip_name = `echo $ip | sed 's/:/ /g' | awk '{$1="";print $0}'`

# Project detection based on IP prefix:
# UMC: IP starts with umc (umc9_2, umc9_3, umc17_0, etc.)
# OSS: IP starts with oss (oss7_2, oss8_0, etc.)
# GMC: IP starts with gmc (gmc13_1a, etc.)

set project_type = ""

if ($ip_name =~ umc*) then
    set project_type = "umc"
else if ($ip_name =~ oss*) then
    set project_type = "oss"
else if ($ip_name =~ gmc*) then
    set project_type = "gmc"
else
    # Unknown project - exit with error
    echo "ERROR: Cannot determine project type from IP '$ip_name'"
    echo "ERROR: Cannot determine project type from IP '$ip_name'" >> $source_dir/data/${tag}_spec
    echo "Valid IP prefixes: umc*, oss*, gmc*" >> $source_dir/data/${tag}_spec
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Route to appropriate project-specific script
if ($project_type == "umc") then
    echo "Detected UMC project (IP: $ip_name)"
    source $source_dir/script/rtg_oss_feint/umc/sync_tree.csh $refDir $ip $CL $tag $p4File

else if ($project_type == "oss") then
    echo "Detected OSS project (IP: $ip_name)"
    source $source_dir/script/rtg_oss_feint/oss/sync_tree.csh $refDir $ip $CL $tag $p4File

else if ($project_type == "gmc") then
    echo "Detected GMC project (IP: $ip_name)"
    source $source_dir/script/rtg_oss_feint/gmc/sync_tree.csh $refDir $ip $CL $tag $p4File

else
    echo "ERROR: Could not detect project type" >> $source_dir/data/${tag}_spec
endif
