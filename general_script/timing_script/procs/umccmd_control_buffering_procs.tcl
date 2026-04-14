################################################################################
# UMCCMD Control Signal Buffering Permuton Procs
# Target: High-fanout control signals
# Updated: 2026-02-09 - Fixed to use parse_proc_arguments for DSO value
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_control_buffer_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_control_buffering)
    puts "INFO: [info level 0] - Applying control signal buffering: $permuton_value"

    # Map permuton value to buffering multiplier
    set buffer_mult $permuton_value

    if {$buffer_mult < 1.0} {
        puts "  Control buffering: DISABLED (baseline)"
        return
    }

    puts "  Buffering multiplier: ${buffer_mult}x"

    # Calculate buffering constraints based on multiplier
    # Baseline: max_fanout=100, max_transition=0.15
    set max_fanout [expr int(100.0 / $buffer_mult)]
    set max_transition [expr 0.15 / $buffer_mult]

    puts "  Max fanout: $max_fanout (baseline: 100)"
    puts "  Max transition: $max_transition (baseline: 0.15)"

    # Get all high-fanout nets in the design
    set all_nets [get_nets -quiet -hier]
    if {[sizeof_collection $all_nets] == 0} {
        puts "WARNING: No nets found in design"
        return
    }

    set high_fanout_nets [filter_collection $all_nets "fanout > 100"]

    if {[sizeof_collection $high_fanout_nets] > 0} {
        puts "  Found [sizeof_collection $high_fanout_nets] high-fanout nets (>100 fanout)"

        # Focus on control signals from known problematic registers
        set control_nets [filter_collection $high_fanout_nets \
            "full_name =~ *MrDimmEn* || full_name =~ *AutoRefReq* || full_name =~ *IdleBWCfg*"]

        if {[sizeof_collection $control_nets] > 0} {
            puts "  Found [sizeof_collection $control_nets] critical control nets"

            # Set buffering constraints
            set_fix_multiple_port_nets -buffer_constants -all
            set_app_options -name opt.common.max_fanout -value $max_fanout

            # Apply transition and capacitance limits
            set_max_transition $max_transition [get_clocks UCLK]
            set_max_capacitance 0.5 $control_nets

            puts "  Applied buffering constraints to critical control signals"
        } else {
            puts "  No critical control nets found matching patterns"
        }
    } else {
        puts "  No high-fanout nets found for buffering"
    }

    return
}

define_proc_attributes umccmd_before_control_buffer_proc -info "Control signal buffering permuton" \
    -define_args { \
        {umccmd_control_buffering "Buffering multiplier value" umccmd_control_buffering float required} \
    }

proc umccmd_after_control_buffer_proc {} {
    puts "INFO: [info level 0] - Cleaning up control buffering settings"

    # Reset to default buffering settings
    set_app_options -name opt.common.max_fanout -value 100

    return
}

}
