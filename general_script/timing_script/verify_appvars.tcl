#!/bin/tcl
#===============================================================================
# Fusion Compiler App_Options Verification Script
#===============================================================================
# Purpose: Verify all app_options used in timing permutons exist in FC
# Usage: fc_shell> source verify_appvars.tcl
# Created: 2026-01-16
# Updated: 2026-01-26 - Updated to use FC dot notation app_options
#===============================================================================

puts ""
puts "==============================================================================="
puts "FUSION COMPILER APP_OPTIONS VERIFICATION"
puts "==============================================================================="
puts "Verifying app_options used in DSO Timing Enhancement Permutons"
if {[catch {puts "FC Version: [get_app_var sh_product_version]"}]} {
    puts "FC Version: Unknown"
}
puts ""

# List of all app_options used in the timing permutons (using FC dot notation)
# These are the app_options actively used in the 12 custom permuton procs
# Updated: 2026-01-27 - Added UMCCMD-specific app_options
set app_options_to_check {
    opt.timing.effort
    opt.common.user_instance_name_prefix
    opt.common.allow_physical_feedthrough
    opt.common.advanced_logic_restructuring_mode
    opt.common.max_fanout
    compile.retiming.optimization_priority
    compile.seqmap.register_replication_placement_effort
    compile.flow.high_effort_timing
    compile.flow.areaResynthesis
}

set total_options [llength $app_options_to_check]
set exists_count 0
set missing_count 0
set missing_list [list]

puts "Checking $total_options app_options...\n"
puts [format "%-50s %-10s %s" "APP_OPTION" "STATUS" "CURRENT VALUE"]
puts [string repeat "-" 80]

foreach opt $app_options_to_check {
    if {[catch {set value [get_app_option_value -name $opt]} err]} {
        puts [format "%-50s %-10s %s" $opt "MISSING" "N/A"]
        incr missing_count
        lappend missing_list $opt
    } else {
        puts [format "%-50s %-10s %s" $opt "OK" $value]
        incr exists_count
    }
}

puts [string repeat "-" 80]
puts "\nSUMMARY:"
puts "  Total app_options checked: $total_options"
puts "  Found: $exists_count"
puts "  Missing: $missing_count"

if {$missing_count == 0} {
    puts "\n✓ SUCCESS: All app_options exist in this Fusion Compiler version"
    puts "  You can safely use the timing permutons."
} else {
    puts "\n⚠ WARNING: $missing_count app_options not found:"
    foreach opt $missing_list {
        puts "    - $opt"
    }
    puts "\n  These options may need to be replaced with alternatives."
    puts "  Use 'report_app_options *pattern*' to find similar options."
}

puts ""
puts "==============================================================================="
puts "USEFUL COMMANDS:"
puts "==============================================================================="
puts ""
puts "To search for available app_options:"
puts "  fc_shell> report_app_options compile.*"
puts "  fc_shell> report_app_options *timing*"
puts "  fc_shell> report_app_options *retiming*"
puts ""
puts "To get documentation for any app_option:"
puts "  fc_shell> man <app_option_name>"
puts ""
puts "Example:"
puts "  fc_shell> man opt.timing.effort"
puts "  fc_shell> man compile.retiming.optimization_priority"
puts ""
puts "To list all non-default app_options:"
puts "  fc_shell> report_app_options -non_default"
puts "==============================================================================="
puts ""
