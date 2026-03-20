#!/bin/tcsh
# Top-level unified static check entry point for both UMC and OSS
# Auto-detects project type based on tile name and routes to appropriate script
# Usage: static_check_unified.csh <refDir> <ip> <tile> <CL> <tag> <p4File> <checkType>

set refDir = $1
set ip = $2
set tile = $3
set CL = $4
set tag = $5
set p4File = $6
set checkType = $7
set source_dir = `pwd`

# Parse tile name and IP name to detect project type
set tile_name = `echo $tile | sed 's/:/ /g' | awk '{$1="";print $0}' | sed 's/^ *//'`
set ip_name = `echo $ip | sed 's/:/ /g' | awk '{$1="";print $0}' | sed 's/^ *//'`

echo "DEBUG: ip_name='$ip_name' tile_name='$tile_name'"

# Project detection based on IP prefix (priority 1):
# UMC: IP starts with umc (umc9_2, umc9_3, umc17_0, etc.)
# OSS: IP starts with oss (oss7_2, oss8_0, etc.)
# GMC: IP starts with gmc (gmc13_1a, etc.)

set project_type = ""

# Priority 1: Check IP prefix
if ($ip_name =~ umc*) then
    set project_type = "umc"
else if ($ip_name =~ oss*) then
    set project_type = "oss"
else if ($ip_name =~ gmc*) then
    set project_type = "gmc"

# Priority 2: Check tile name (for backwards compatibility)
else if ($tile_name == "umc_top") then
    set project_type = "umc"
else if ($tile_name == "osssys" || $tile_name == "hdp" || $tile_name == "sdma0_gc" || $tile_name == "lsdma0" || $tile_name == "all") then
    set project_type = "oss"
else if ($tile_name == "gmc_gmcctrl_t" || $tile_name == "gmc_gmcch_t") then
    set project_type = "gmc"

# Unknown project - exit with error
else
    echo "ERROR: Cannot determine project type from IP '$ip_name' or tile '$tile_name'"
    echo "ERROR: Cannot determine project type from IP '$ip_name' or tile '$tile_name'" >> $source_dir/data/${tag}_spec
    echo "Valid IP prefixes: umc*, oss*, gmc*" >> $source_dir/data/${tag}_spec
    source $source_dir/script/rtg_oss_feint/finishing_task.csh
    exit 1
endif

# Route to appropriate project-specific script
if ($project_type == "umc") then
    echo "Detected UMC project"
    source $source_dir/script/rtg_oss_feint/umc/static_check.csh $refDir $ip $tile $CL $tag $p4File $checkType

else if ($project_type == "oss") then
    echo "Detected OSS project"
    source $source_dir/script/rtg_oss_feint/oss/static_check.csh $refDir $ip $tile $CL $tag $p4File $checkType

else if ($project_type == "gmc") then
    echo "Detected GMC project"
    source $source_dir/script/rtg_oss_feint/gmc/static_check.csh $refDir $ip $tile $CL $tag $p4File $checkType

else
    echo "ERROR: Could not detect project type" >> $source_dir/data/${tag}_spec
endif
