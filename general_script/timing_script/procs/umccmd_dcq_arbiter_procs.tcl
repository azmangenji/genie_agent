################################################################################
# UMCCMD DCQ Arbiter Pipeline Permuton Procs
# Target: DCQARB, DCQARB1 arbiter logic
# Updated: 2026-02-19 - Fixed proc signature for DSO.ai compatibility
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_dcq_arb_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_dcq_arbiter_pipeline)
    puts "INFO: [info level 0] - Applying DCQ arbiter optimization: $permuton_value"

    set do_restructure false
    set do_balance false

    switch $permuton_value {
        "none" {
            puts "  DCQ arbiter optimization: DISABLED"
            return
        }
        "restructure" {
            set do_restructure true
            puts "  Mode: Restructure arbiter logic only"
        }
        "balance" {
            set do_balance true
            puts "  Mode: Balance arbiter paths only"
        }
        "both" {
            set do_restructure true
            set do_balance true
            puts "  Mode: Both restructure and balance"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # Find DCQ arbiter cells
    set dcqarb_cells [get_cells -quiet -hier -filter "full_name =~ *DCQARB*"]

    if {[sizeof_collection $dcqarb_cells] == 0} {
        puts "  WARNING: No DCQ arbiter cells found"
        return
    }

    puts "  Found DCQ arbiter cells: [sizeof_collection $dcqarb_cells]"

    # Find ArbSafeReg specifically (124 violations)
    set arb_safe_regs [get_cells -quiet -hier -filter "full_name =~ *ArbSafeReg*"]
    if {[sizeof_collection $arb_safe_regs] > 0} {
        puts "  Found ArbSafeReg cells: [sizeof_collection $arb_safe_regs]"
        group_path -name arb_safe_group -to $arb_safe_regs -weight 2.0
    }

    if {$do_restructure} {
        # Increase restructuring effort on arbiter logic using FC app_options
        set_app_options -block [current_block] -name opt.common.user_instance_name_prefix -value DCQOPT_

        # Allow restructuring
        set_dont_touch $dcqarb_cells false

        # Filter hierarchical cells only for set_boundary_optimization
        # (leaf cells cannot have boundary optimization set - causes CMD-012)
        set dcqarb_hier_cells [filter_collection $dcqarb_cells "is_hierarchical == true"]
        if {[sizeof_collection $dcqarb_hier_cells] > 0} {
            set_boundary_optimization $dcqarb_hier_cells all
            puts "  Applied boundary optimization to [sizeof_collection $dcqarb_hier_cells] hierarchical cells"
        } else {
            puts "  INFO: No hierarchical DCQ arbiter cells found for boundary optimization"
        }

        # Note: set_max_area removed - causes CMD-012 with large cell collections
        # Area constraints should be set at design level if needed

        puts "  Applied restructuring settings to DCQ arbiter"
    }

    if {$do_balance} {
        # Create path groups for balanced optimization with weight
        group_path -name dcqarb_group -through $dcqarb_cells -weight 2.0

        puts "  Applied balancing settings to DCQ arbiter"
    }

    return
}

define_proc_attributes umccmd_before_dcq_arb_proc -info "DCQ arbiter pipeline permuton" \
    -define_args { \
        {umccmd_dcq_arbiter_pipeline "DCQ arbiter optimization mode" umccmd_dcq_arbiter_pipeline string required} \
    }

proc umccmd_after_dcq_arb_proc {} {
    puts "INFO: [info level 0] - Cleaning up DCQ arbiter settings"

    # Remove custom path groups
    if {[sizeof_collection [get_path_groups -quiet arb_safe_group]] > 0} {
        remove_path_group arb_safe_group
    }
    if {[sizeof_collection [get_path_groups -quiet dcqarb_group]] > 0} {
        remove_path_group dcqarb_group
    }

    # Reset app_options to defaults
    reset_app_options opt.common.user_instance_name_prefix

    return
}

}
