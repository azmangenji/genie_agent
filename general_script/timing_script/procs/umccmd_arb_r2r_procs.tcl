################################################################################
# UMCCMD ARB R2R Path Optimization Permuton Procs
# Target: umc_ARB_r2r_to path group (top R2R violator)
# Created: 2026-03-03
################################################################################
# Analysis: Feb23 run shows:
#   - umc_ARB_r2r_to: WNS -120.65ps, TNS -32,090ps, 3484 NVP
#   - umc_ARB_r2r_from: WNS -44.52ps, TNS -443ps, 21 NVP
#   - ARB module endpoints in nearly 100% of R2R violations
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_arb_r2r_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_arb_r2r_opt)
    puts "INFO: [info level 0] - Applying ARB R2R optimization: $permuton_value"

    if {$permuton_value eq "none"} {
        puts "  ARB R2R optimization: DISABLED"
        return
    }

    # Get ARB registers (R2R endpoints) - DCQARB excluded to avoid pollution
    # DCQARB contains "ARB" as substring - must explicitly exclude it
    set arb_regs [get_cells -quiet -hier -filter "full_name =~ *ARB* && full_name !~ *DCQARB* && is_sequential == true"]

    if {[sizeof_collection $arb_regs] == 0} {
        puts "  WARNING: No ARB registers found, skipping ARB R2R optimization"
        return
    }

    puts "  Found ARB registers: [sizeof_collection $arb_regs]"

    switch $permuton_value {
        "restructure" {
            # Enable aggressive logic restructuring for ARB R2R paths
            set_app_options -block [current_block] -name opt.common.advanced_logic_restructuring_mode -value area_timing

            # Create R2R path group for ARB endpoints with moderate weight
            # Use -to for R2R endpoints (not -through to avoid path explosion)
            group_path -name arb_r2r_critical -to $arb_regs -weight 1.3

            puts "  Mode: Restructure - enabled logic restructuring for ARB R2R paths"
        }
        "retime" {
            # Enable retiming for ARB R2R paths
            set_app_options -block [current_block] -name compile.retiming.optimization_priority -value setup_timing
            set_app_options -block [current_block] -name compile.seqmap.register_replication_placement_effort -value high

            # Create R2R path group for ARB with retiming focus
            group_path -name arb_r2r_retime -to $arb_regs -weight 1.2

            puts "  Mode: Retime - enabled retiming optimization for ARB R2R paths"
        }
        default {
            puts "  WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    return
}

define_proc_attributes umccmd_before_arb_r2r_proc -info "ARB R2R path optimization permuton" \
    -define_args { \
        {umccmd_arb_r2r_opt "ARB R2R optimization mode" umccmd_arb_r2r_opt string required} \
    }

proc umccmd_after_arb_r2r_proc {} {
    puts "INFO: [info level 0] - Cleaning up ARB R2R settings"

    # Reset app options
    reset_app_options opt.common.advanced_logic_restructuring_mode
    reset_app_options compile.retiming.optimization_priority
    reset_app_options compile.seqmap.register_replication_placement_effort

    # Remove path groups
    if {[sizeof_collection [get_path_groups -quiet arb_r2r_critical]] > 0} {
        remove_path_group arb_r2r_critical
    }
    if {[sizeof_collection [get_path_groups -quiet arb_r2r_retime]] > 0} {
        remove_path_group arb_r2r_retime
    }

    return
}

}
