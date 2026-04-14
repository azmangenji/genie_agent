################################################################################
# UMCCMD DCQARB Boundary Optimization Permuton Procs
# Target: DCQARB cross-hierarchy R2R paths (NVP=2339, TNS=-39K, WNS=-62ps)
# Created: 2026-03-20
################################################################################
# Motivation: v5 r2r_optimization.tcl introduced safe DCQARB boundary opt
# (no dont_touch removal, no logic restructuring). This permuton lets DSO
# explore whether to apply it to ARB only, DCQARB only, or both.
#
# Distinct from umccmd_dcq_arbiter_pipeline=restructure which also applies
# dont_touch=false and logic restructuring (can cause instability).
# This permuton is the SAFE path: boundary opt only.
#
# Ranges:
#   none      - No boundary opt applied (pure tool default)
#   arb_only  - ARB boundary opt only (v3 behavior)
#   both      - ARB + DCQARB boundary opt (v5 TCL behavior)
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_dcqarb_boundary_opt_proc {args} {
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_dcqarb_boundary_opt)
    puts "INFO: [info level 0] - Applying DCQARB boundary opt: $permuton_value"

    if {$permuton_value eq "none"} {
        puts "  Boundary optimization: DISABLED"
        return
    }

    # ARB boundary opt - applied for arb_only and both
    set arb_hier_cells [get_cells -quiet -hier -filter \
        "full_name =~ *ARB* && is_hierarchical == true && full_name !~ *DCQARB*"]
    if {[sizeof_collection $arb_hier_cells] > 0} {
        set_boundary_optimization $arb_hier_cells true
        puts "  Enabled boundary opt: [sizeof_collection $arb_hier_cells] ARB cells"
    }

    # DCQARB boundary opt - only for 'both'
    if {$permuton_value eq "both"} {
        set dcqarb_hier_cells [get_cells -quiet -hier -filter \
            "full_name =~ *DCQARB* && is_hierarchical == true"]
        if {[sizeof_collection $dcqarb_hier_cells] > 0} {
            set_boundary_optimization $dcqarb_hier_cells true
            puts "  Enabled boundary opt: [sizeof_collection $dcqarb_hier_cells] DCQARB cells"
        } else {
            puts "  INFO: No hierarchical DCQARB cells found"
        }
    }

    return
}

define_proc_attributes umccmd_before_dcqarb_boundary_opt_proc \
    -info "DCQARB safe boundary optimization permuton (no dont_touch removal)" \
    -define_args { \
        {umccmd_dcqarb_boundary_opt "Boundary opt scope: none/arb_only/both" umccmd_dcqarb_boundary_opt string required} \
    }

proc umccmd_after_dcqarb_boundary_opt_proc {} {
    puts "INFO: [info level 0] - Cleaning up boundary opt settings"

    # Reset ARB boundary opt
    set arb_hier_cells [get_cells -quiet -hier -filter \
        "full_name =~ *ARB* && is_hierarchical == true && full_name !~ *DCQARB*"]
    if {[sizeof_collection $arb_hier_cells] > 0} {
        set_boundary_optimization $arb_hier_cells false
    }

    # Reset DCQARB boundary opt
    set dcqarb_hier_cells [get_cells -quiet -hier -filter \
        "full_name =~ *DCQARB* && is_hierarchical == true"]
    if {[sizeof_collection $dcqarb_hier_cells] > 0} {
        set_boundary_optimization $dcqarb_hier_cells false
    }

    return
}

}
