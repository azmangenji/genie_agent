################################################################################
# UMCCMD Clock Gate Path Group Permuton Procs
# Target: clock_gating_default paths (NVP=545, TNS=-10,175ps, WNS=-59ps)
# Created: 2026-03-20
################################################################################
# Motivation: clock_gating_default group has 545 NVP and -10,175ps TNS but
# was NEVER targeted in any DSO lineage across 28Jan40p or 4Mac40p runs.
# v5 r2r_optimization.tcl added a fixed path group (weight=6, range=400).
# This permuton lets DSO explore the optimal weight for clock gate paths
# without conflicting with the dominant ARB/DCQARB groups.
#
# Ranges:
#   none  - No clock gate path group (tool handles via clock_gating_default)
#   low   - weight=4, range=300 (conservative, avoids stealing from ARB/DCQARB)
#   high  - weight=6, range=400 (same as v5 TCL setting)
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_clkgate_opt_proc {args} {
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_clkgate_opt)
    puts "INFO: [info level 0] - Applying clock gate optimization: $permuton_value"

    if {$permuton_value eq "none"} {
        puts "  Clock gate path group: DISABLED"
        return
    }

    switch $permuton_value {
        "low"  { set pg_weight 4; set pg_range 300 }
        "high" { set pg_weight 6; set pg_range 400 }
        default {
            puts "  WARNING: Unknown value: $permuton_value"
            return
        }
    }

    # Primary: use is_clock_gating_cell filter
    set clkgate_cells [get_cells -quiet -hier -filter "is_clock_gating_cell == true"]

    if {[sizeof_collection $clkgate_cells] > 0} {
        group_path -name umccmd_clkgate_dso \
            -critical_range $pg_range -weight $pg_weight \
            -to $clkgate_cells
        puts "  Created clkgate path group: [sizeof_collection $clkgate_cells] cells (weight=$pg_weight, range=$pg_range)"
    } else {
        # Fallback: ICG/ClkGate name pattern
        set clkgate_cells [get_cells -quiet -hier -filter \
            "full_name =~ *ICG* || full_name =~ *ClkGate*"]
        if {[sizeof_collection $clkgate_cells] > 0} {
            group_path -name umccmd_clkgate_dso \
                -critical_range $pg_range -weight $pg_weight \
                -to $clkgate_cells
            puts "  Created clkgate path group (name fallback): [sizeof_collection $clkgate_cells] cells (weight=$pg_weight, range=$pg_range)"
        } else {
            puts "  WARNING: No clock gating cells found - skipping"
        }
    }

    return
}

define_proc_attributes umccmd_before_clkgate_opt_proc \
    -info "Clock gate path group permuton (545 NVP, -10K TNS never targeted)" \
    -define_args { \
        {umccmd_clkgate_opt "Clock gate weight level: none/low/high" umccmd_clkgate_opt string required} \
    }

proc umccmd_after_clkgate_opt_proc {} {
    puts "INFO: [info level 0] - Cleaning up clock gate path group"

    if {[sizeof_collection [get_path_groups -quiet umccmd_clkgate_dso]] > 0} {
        remove_path_group umccmd_clkgate_dso
    }

    return
}

}
