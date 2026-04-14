################################################################################
# UMCCMD DCQARB Max Fanout Permuton Procs
# Target: High-fanout nets in DCQARB (49.8% of all registers)
# Created: 2026-03-20
################################################################################
# Motivation: v5 r2r_optimization.tcl sets max_fanout=30 for all DCQARB cells.
# The optimal fanout limit is unknown - too tight causes excessive buffering
# (area/power hit), too loose leaves slow high-fanout nets unaddressed.
# This permuton lets DSO find the optimal DCQARB fanout limit.
#
# Ranges:
#   none  - No max_fanout constraint (tool default, typically 100+)
#   20    - Aggressive: force buffering on all nets >20 fanout
#   30    - v5 TCL setting
#   40    - Moderate: allow higher fanout, less buffering overhead
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_dcqarb_fanout_proc {args} {
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_dcqarb_max_fanout)
    puts "INFO: [info level 0] - Applying DCQARB max_fanout: $permuton_value"

    if {$permuton_value eq "none"} {
        puts "  DCQARB max_fanout: NOT SET (tool default)"
        return
    }

    set fanout_limit [expr {int($permuton_value)}]

    set dcqarb_cells [get_cells -quiet -hier -filter "full_name =~ *DCQARB*"]
    if {[sizeof_collection $dcqarb_cells] > 0} {
        set_max_fanout $fanout_limit $dcqarb_cells
        puts "  Set max_fanout=$fanout_limit for [sizeof_collection $dcqarb_cells] DCQARB cells"
    } else {
        puts "  WARNING: No DCQARB cells found"
    }

    return
}

define_proc_attributes umccmd_before_dcqarb_fanout_proc \
    -info "DCQARB max fanout constraint permuton" \
    -define_args { \
        {umccmd_dcqarb_max_fanout "Max fanout limit for DCQARB: none/20/30/40" umccmd_dcqarb_max_fanout string required} \
    }

proc umccmd_after_dcqarb_fanout_proc {} {
    puts "INFO: [info level 0] - Cleaning up DCQARB max_fanout constraints"

    set dcqarb_cells [get_cells -quiet -hier -filter "full_name =~ *DCQARB*"]
    if {[sizeof_collection $dcqarb_cells] > 0} {
        remove_attribute $dcqarb_cells max_fanout
    }

    return
}

}
