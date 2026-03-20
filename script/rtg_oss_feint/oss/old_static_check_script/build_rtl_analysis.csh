#!/bin/tcsh
# OSS RTL build results analysis
# Called by static_check_command.csh after run_build_rtl.csh
# Requires: $tile_name, $source_dir, $tag, $refdir_name

echo "========================================="
echo "Analyzing RTL build results for OSS"
echo "Tile: $tile_name"
echo "========================================="

# Analyze RTL build results based on tile
if ($tile_name == "osssys") then
    echo "Analyzing RTL build for osssys..."
    
    cat >> $source_dir/data/${tag}_spec << EOF
#text#
    The rtl run for $tile_name tiles are done.
EOF
    
    set logfile = `ls osssys_rtl.log 2>/dev/null`
    if ("$logfile" != "") then
        set failpass = `grep -A1 "Execution Summary" $logfile | grep -v "Execution Summary" | grep rhea_drop | awk '{print $4}' | sort -u`
        if ($failpass == "PASSED") then
            echo "The RTL build at $refdir_name is PASSED" >> $source_dir/data/${tag}_spec
        else 
            echo "The RTL build at $refdir_name is FAILED, please debug" >> $source_dir/data/${tag}_spec
        endif
    else
        echo "WARNING: Log file not found for osssys" >> $source_dir/data/${tag}_spec
    endif
    
else if ($tile_name == "hdp") then
    echo "Analyzing RTL build for hdp..."
    
    cat >> $source_dir/data/${tag}_spec << EOF
#text#
    The rtl run for $tile_name tiles are done.
EOF
    
    set logfile = `ls hdp_rtl.log 2>/dev/null`
    if ("$logfile" != "") then
        set failpass = `grep -A1 "Execution Summary" $logfile | grep -v "Execution Summary" | grep rhea_drop | awk '{print $4}' | sort -u`
        if ($failpass == "PASSED") then
            echo "The RTL build at $refdir_name is PASSED" >> $source_dir/data/${tag}_spec
        else 
            echo "The RTL build at $refdir_name is FAILED, please debug" >> $source_dir/data/${tag}_spec
        endif
    else
        echo "WARNING: Log file not found for hdp" >> $source_dir/data/${tag}_spec
    endif
    
else if ($tile_name == "sdma0_gc") then
    echo "Analyzing RTL build for sdma0_gc..."
    
    cat >> $source_dir/data/${tag}_spec << EOF
#text#
    The rtl run for $tile_name tiles are done.
EOF
    
    set logfile = `ls sdma0_gc_rtl.log 2>/dev/null`
    if ("$logfile" != "") then
        set failpass = `grep -A1 "Execution Summary" $logfile | grep -v "Execution Summary" | grep rhea_drop | awk '{print $4}' | sort -u`
        if ($failpass == "PASSED") then
            echo "The RTL build at $refdir_name is PASSED" >> $source_dir/data/${tag}_spec
        else 
            echo "The RTL build at $refdir_name is FAILED, please debug" >> $source_dir/data/${tag}_spec
        endif
    else
        echo "WARNING: Log file not found for sdma0_gc" >> $source_dir/data/${tag}_spec
    endif
    
else if ($tile_name == "sdma1_gc") then
    echo "Analyzing RTL build for sdma1_gc..."
    
    cat >> $source_dir/data/${tag}_spec << EOF
#text#
    The rtl run for $tile_name tiles are done.
EOF
    
    set logfile = `ls sdma1_gc_rtl.log 2>/dev/null`
    if ("$logfile" != "") then
        set failpass = `grep -A1 "Execution Summary" $logfile | grep -v "Execution Summary" | grep rhea_drop | awk '{print $4}' | sort -u`
        if ($failpass == "PASSED") then
            echo "The RTL build at $refdir_name is PASSED" >> $source_dir/data/${tag}_spec
        else 
            echo "The RTL build at $refdir_name is FAILED, please debug" >> $source_dir/data/${tag}_spec
        endif
    else
        echo "WARNING: Log file not found for sdma1_gc" >> $source_dir/data/${tag}_spec
    endif
    
else if ($tile_name == "all") then
    echo "Analyzing RTL build for all tiles..."
    
    cat >> $source_dir/data/${tag}_spec << EOF
#text#
    The rtl run for all tiles are done.
EOF
    
    # Analyze osssys
    set logfile = `ls osssys_rtl.log 2>/dev/null`
    if ("$logfile" != "") then
        set failpass = `grep -A1 "Execution Summary" $logfile | grep -v "Execution Summary" | grep rhea_drop | awk '{print $4}' | sort -u`
        if ($failpass == "PASSED") then
            echo "  osssys RTL build: PASSED" >> $source_dir/data/${tag}_spec
        else 
            echo "  osssys RTL build: FAILED" >> $source_dir/data/${tag}_spec
        endif
    endif
    
    # Analyze hdp
    set logfile = `ls hdp_rtl.log 2>/dev/null`
    if ("$logfile" != "") then
        set failpass = `grep -A1 "Execution Summary" $logfile | grep -v "Execution Summary" | grep rhea_drop | awk '{print $4}' | sort -u`
        if ($failpass == "PASSED") then
            echo "  hdp RTL build: PASSED" >> $source_dir/data/${tag}_spec
        else 
            echo "  hdp RTL build: FAILED" >> $source_dir/data/${tag}_spec
        endif
    endif
    
    # Analyze sdma
    set logfile = `ls sdma_rtl.log 2>/dev/null`
    if ("$logfile" != "") then
        set failpass = `grep -A1 "Execution Summary" $logfile | grep -v "Execution Summary" | grep rhea_drop | awk '{print $4}' | sort -u`
        if ($failpass == "PASSED") then
            echo "  sdma RTL build: PASSED" >> $source_dir/data/${tag}_spec
        else 
            echo "  sdma RTL build: FAILED" >> $source_dir/data/${tag}_spec
        endif
    endif
    
    echo "RTL build analysis completed for all tiles"

else
    echo "ERROR: Unknown tile name: $tile_name"
    exit 1
endif

echo "RTL build analysis completed"
