################################################################################
# UMCCMD IO Path Optimization Permuton Procs
# Target: I2R, R2O, io_to_flop, io_to_io paths
# Created: 2026-03-18
################################################################################
# Analysis from 4Mac40p DSO run shows major TNS regressions in IO paths:
#   Path Group       Baseline TNS    DSO TNS       Delta
#   --------------------------------------------------------
#   SYN_I2R          -563,603 ps    -623,979 ps   -60,377 ps  <- WORST
#   io_to_flop        -30,956 ps     -35,519 ps    -4,564 ps
#   io_to_io          -27,980 ps     -31,663 ps    -3,682 ps
#   SYN_R2O           -23,873 ps     -25,446 ps    -1,572 ps
#   --------------------------------------------------------
#   TOTAL IO:        -646,412 ps    -716,607 ps   -70,195 ps
#
# Root cause: No permuton covered IO paths, all focused on R2R only
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_io_path_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_io_path_optimization)
    puts "INFO: [info level 0] - Applying IO path optimization: $permuton_value"

    switch $permuton_value {
        "none" {
            puts "  IO path optimization: DISABLED"
            return
        }
        "standard" {
            puts "  Mode: STANDARD - basic IO path optimization"
            set io_weight 1.3
            set io_critical_range 300
            set i2r_effort "high"
        }
        "aggressive" {
            puts "  Mode: AGGRESSIVE - maximum IO path optimization"
            set io_weight 2.0
            set io_critical_range 500
            set i2r_effort "ultra"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # ==========================================================================
    # I2R Path Optimization (SYN_I2R: -60K ps regression)
    # ==========================================================================
    puts "  Configuring I2R (Input-to-Register) path optimization..."

    # Get all input ports
    set all_inputs [all_inputs]
    set all_regs [all_registers]

    if {[sizeof_collection $all_inputs] > 0 && [sizeof_collection $all_regs] > 0} {
        # Create weighted I2R path group
        group_path -name io_opt_i2r -from $all_inputs -to $all_regs \
            -weight $io_weight -critical_range $io_critical_range
        puts "    Created I2R path group: [sizeof_collection $all_inputs] inputs -> regs (weight: $io_weight)"
    }

    # ==========================================================================
    # R2O Path Optimization (SYN_R2O: -1.5K ps regression)
    # ==========================================================================
    puts "  Configuring R2O (Register-to-Output) path optimization..."

    set all_outputs [all_outputs]

    if {[sizeof_collection $all_regs] > 0 && [sizeof_collection $all_outputs] > 0} {
        # Create weighted R2O path group
        group_path -name io_opt_r2o -from $all_regs -to $all_outputs \
            -weight $io_weight -critical_range $io_critical_range
        puts "    Created R2O path group: regs -> [sizeof_collection $all_outputs] outputs (weight: $io_weight)"
    }

    # ==========================================================================
    # IO-to-Flop Path Optimization (io_to_flop: -4.5K ps regression)
    # ==========================================================================
    puts "  Configuring IO-to-Flop path optimization..."

    # Target specific input paths that have timing issues
    # Focus on high-fanout input ports
    set input_ports_count [sizeof_collection $all_inputs]
    if {$input_ports_count > 0} {
        # Set input delay margins for critical inputs
        set_app_options -block [current_block] -name time.io_budgeting_mode -value true
        puts "    Enabled IO budgeting mode for io_to_flop paths"
    }

    # ==========================================================================
    # IO-to-IO Path Optimization (io_to_io: -3.7K ps regression)
    # ==========================================================================
    puts "  Configuring IO-to-IO (combinational) path optimization..."

    if {[sizeof_collection $all_inputs] > 0 && [sizeof_collection $all_outputs] > 0} {
        # Create weighted IO-to-IO path group for combinational paths
        group_path -name io_opt_io2io -from $all_inputs -to $all_outputs \
            -weight $io_weight -critical_range $io_critical_range
        puts "    Created IO-to-IO path group (weight: $io_weight)"
    }

    # ==========================================================================
    # Global IO Timing Settings
    # ==========================================================================
    puts "  Applying global IO timing settings..."

    # Enable slack-based TNS optimization for IO paths
    set_app_options -block [current_block] -name opt.timing.slack_based_tns_optimization -value true

    # Set timing effort based on mode
    set_app_options -block [current_block] -name opt.timing.effort -value $i2r_effort

    # Increase optimization iterations for IO paths
    if {$permuton_value eq "aggressive"} {
        set_app_options -block [current_block] -name opt.timing.tns_optimization_paths_per_endpoint -value 15
        puts "    Set TNS paths per endpoint: 15 (aggressive)"
    } else {
        set_app_options -block [current_block] -name opt.timing.tns_optimization_paths_per_endpoint -value 8
        puts "    Set TNS paths per endpoint: 8 (standard)"
    }

    puts "  IO path optimization configured successfully"
    return
}

define_proc_attributes umccmd_before_io_path_proc -info "IO path optimization permuton" \
    -define_args { \
        {umccmd_io_path_optimization "IO path optimization mode" umccmd_io_path_optimization string required} \
    }

proc umccmd_after_io_path_proc {} {
    puts "INFO: [info level 0] - Cleaning up IO path settings"

    # Remove IO path groups
    set io_groups [list "io_opt_i2r" "io_opt_r2o" "io_opt_io2io"]
    foreach group $io_groups {
        if {[sizeof_collection [get_path_groups -quiet $group]] > 0} {
            remove_path_group $group
            puts "  Removed path group: $group"
        }
    }

    # Reset app options
    reset_app_options time.io_budgeting_mode
    reset_app_options opt.timing.slack_based_tns_optimization
    reset_app_options opt.timing.effort
    reset_app_options opt.timing.tns_optimization_paths_per_endpoint

    puts "  IO path cleanup complete"
    return
}

}
