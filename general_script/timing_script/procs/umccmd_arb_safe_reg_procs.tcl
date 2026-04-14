################################################################################
# UMCCMD Arbiter Safe Register Optimization Permuton Procs
# Target: ArbSafeRegPc/Ph/Pm registers
# Updated: 2026-02-19 - Fixed proc signature for DSO.ai compatibility
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_arb_safe_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_arb_safe_reg_opt)
    puts "INFO: [info level 0] - Applying arbiter safe register optimization: $permuton_value"

    set path_weight 1.0
    set enable_ultra false

    switch $permuton_value {
        "normal" {
            set path_weight 1.5
            puts "  Optimization effort: NORMAL (path weight: 1.5)"
        }
        "high" {
            set path_weight 2.0
            puts "  Optimization effort: HIGH (path weight: 2.0)"
        }
        "ultra" {
            set path_weight 3.0
            set enable_ultra true
            puts "  Optimization effort: ULTRA (path weight: 3.0)"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value, using normal"
            set path_weight 1.5
        }
    }

    # Find ArbSafeReg cells
    set arb_safe_regs [get_cells -quiet -hier -filter "full_name =~ *ArbSafeReg*"]

    if {[sizeof_collection $arb_safe_regs] == 0} {
        puts "  WARNING: No ArbSafeReg cells found"
        return
    }

    puts "  Found ArbSafeReg cells: [sizeof_collection $arb_safe_regs]"

    # Create path group with weight for prioritization
    group_path -name arb_safe_opt_group -to $arb_safe_regs -weight $path_weight

    # Allow area increase for timing
    set_dont_touch $arb_safe_regs false

    # Filter hierarchical cells only for set_boundary_optimization
    # (leaf cells cannot have boundary optimization set - causes CMD-012)
    set arb_safe_hier_cells [filter_collection $arb_safe_regs "is_hierarchical == true"]
    if {[sizeof_collection $arb_safe_hier_cells] > 0} {
        set_boundary_optimization $arb_safe_hier_cells all
        puts "  Applied boundary optimization to [sizeof_collection $arb_safe_hier_cells] hierarchical cells"
    }

    if {$enable_ultra} {
        # Ultra mode: enable maximum optimization effort
        set_app_options -name opt.timing.effort -value high
        set_app_options -name compile.flow.high_effort_timing -value 1
        puts "  Enabled ultra optimization mode"
    }

    puts "  Applied arbiter safe register optimizations"

    return
}

define_proc_attributes umccmd_before_arb_safe_proc -info "Arbiter safe register optimization permuton" \
    -define_args { \
        {umccmd_arb_safe_reg_opt "Arbiter safe register optimization level" umccmd_arb_safe_reg_opt string required} \
    }

proc umccmd_after_arb_safe_proc {} {
    puts "INFO: [info level 0] - Cleaning up arbiter safe register settings"

    # Remove custom path group
    if {[sizeof_collection [get_path_groups -quiet arb_safe_opt_group]] > 0} {
        remove_path_group arb_safe_opt_group
    }

    # Reset app_options to defaults
    reset_app_options opt.timing.effort
    reset_app_options compile.flow.high_effort_timing

    return
}

}
