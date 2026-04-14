#!/bin/tcl
################################################################################
# DSO Timing Enhancement - TCL Procs Syntax Verification
# Usage: fc_shell> source verify_procs.tcl
# Updated: 2026-01-26
################################################################################

puts ""
puts "==============================================================================="
puts "DSO TIMING ENHANCEMENT - TCL PROCS SYNTAX VERIFICATION"
puts "==============================================================================="
puts ""

set base_path "/proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/dso_timing_enhancement/procs"

set proc_files {
    umccmd_fanout_duplication_procs.tcl
    umccmd_control_buffering_procs.tcl
    umccmd_dcq_arbiter_procs.tcl
    umccmd_timing_counter_procs.tcl
    umccmd_arb_safe_reg_procs.tcl
    umccmd_critical_groups_procs.tcl
    umccmd_pgt_opt_procs.tcl
    umccmd_control_isolation_procs.tcl
    umccmd_umc_id_didt_procs.tcl
    umcdat_ecc_read_procs.tcl
    umcdat_aes_pipeline_procs.tcl
    umcdat_key_retime_procs.tcl
    umcdat_xts_pipeline_procs.tcl
}

set pass_count 0
set fail_count 0
set failed_files [list]

puts [format "%-45s %s" "PROC FILE" "STATUS"]
puts [string repeat "-" 60]

foreach f $proc_files {
    set full_path "${base_path}/${f}"
    if {[catch {source $full_path} err]} {
        puts [format "%-45s %s" $f "FAIL"]
        puts "  Error: $err"
        incr fail_count
        lappend failed_files $f
    } else {
        puts [format "%-45s %s" $f "OK"]
        incr pass_count
    }
}

puts [string repeat "-" 60]
puts ""
puts "SUMMARY:"
puts "  Total files: [llength $proc_files]"
puts "  Passed: $pass_count"
puts "  Failed: $fail_count"
puts ""

if {$fail_count == 0} {
    puts "SUCCESS: All TCL procs have valid syntax"
    puts ""
    puts "Loaded procs in ::DSO::PERMUTONS namespace:"
    foreach p [lsort [info commands ::DSO::PERMUTONS::*]] {
        puts "  [namespace tail $p]"
    }
} else {
    puts "WARNING: $fail_count file(s) have syntax errors:"
    foreach f $failed_files {
        puts "  - $f"
    }
}

puts ""
puts "==============================================================================="
