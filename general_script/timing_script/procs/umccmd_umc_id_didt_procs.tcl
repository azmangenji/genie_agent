################################################################################
# UMCCMD UMC_ID_DIDT Optimization Permuton Procs
# Target: UMC_ID_DIDT paths (~1,447 failing paths, 24% of total)
# Updated: 2026-02-19 - Fixed proc signature for DSO.ai compatibility
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_umc_id_didt_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_umc_id_didt_opt)
    puts "INFO: [info level 0] - Applying UMC_ID_DIDT optimization: $permuton_value"

    switch $permuton_value {
        "none" {
            puts "  UMC_ID_DIDT optimization: DISABLED"
            return
        }
        "restructure" {
            puts "  Mode: Logic restructuring for UMC_ID_DIDT"
            set do_restructure true
            set do_retime false
            set do_buffer false
        }
        "retime" {
            puts "  Mode: Register retiming for UMC_ID_DIDT"
            set do_restructure false
            set do_retime true
            set do_buffer false
        }
        "buffer" {
            puts "  Mode: Aggressive buffering for UMC_ID_DIDT"
            set do_restructure false
            set do_retime false
            set do_buffer true
        }
        "aggressive" {
            puts "  Mode: All optimizations for UMC_ID_DIDT"
            set do_restructure true
            set do_retime true
            set do_buffer true
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # Find UMC_ID_DIDT cells
    set didt_cells [get_cells -quiet -hier -filter "full_name =~ *UMC_ID_DIDT*"]

    if {[sizeof_collection $didt_cells] == 0} {
        puts "  WARNING: No UMC_ID_DIDT cells found"
        return
    }

    puts "  Found UMC_ID_DIDT cells: [sizeof_collection $didt_cells]"

    # Create high-priority path group for UMC_ID_DIDT paths
    group_path -name umc_id_didt_group -from $didt_cells -weight 2.5
    group_path -name umc_id_didt_to_group -to $didt_cells -weight 2.0

    # Allow optimization on DIDT logic
    set_dont_touch $didt_cells false

    if {$do_restructure} {
        # Enable advanced logic restructuring
        set_app_options -name opt.common.advanced_logic_restructuring_mode -value area_timing
        set_app_options -name opt.common.allow_physical_feedthrough -value true
        puts "  Enabled logic restructuring"
    }

    if {$do_retime} {
        # Enable register retiming
        set_app_options -name compile.retiming.optimization_priority -value timing
        puts "  Enabled register retiming"
    }

    if {$do_buffer} {
        # Get nets from DIDT cells for buffering
        set didt_nets [get_nets -quiet -of $didt_cells]
        if {[sizeof_collection $didt_nets] > 0} {
            # Tighten transition constraints to force buffering
            set_max_transition 0.06 $didt_nets
            set_max_capacitance 0.3 $didt_nets
            puts "  Applied aggressive buffering constraints"
        }
    }

    # Increase timing effort
    set_app_options -name opt.timing.effort -value high

    puts "  Applied UMC_ID_DIDT optimizations"

    return
}

define_proc_attributes umccmd_before_umc_id_didt_proc -info "UMC_ID_DIDT optimization permuton" \
    -define_args { \
        {umccmd_umc_id_didt_opt "UMC_ID_DIDT optimization mode" umccmd_umc_id_didt_opt string required} \
    }

proc umccmd_after_umc_id_didt_proc {} {
    puts "INFO: [info level 0] - Cleaning up UMC_ID_DIDT settings"

    # Remove custom path groups
    if {[sizeof_collection [get_path_groups -quiet umc_id_didt_group]] > 0} {
        remove_path_group umc_id_didt_group
    }
    if {[sizeof_collection [get_path_groups -quiet umc_id_didt_to_group]] > 0} {
        remove_path_group umc_id_didt_to_group
    }

    # Reset app_options to defaults
    reset_app_options opt.common.advanced_logic_restructuring_mode
    reset_app_options opt.common.allow_physical_feedthrough
    reset_app_options compile.retiming.optimization_priority
    reset_app_options opt.timing.effort

    return
}

}
