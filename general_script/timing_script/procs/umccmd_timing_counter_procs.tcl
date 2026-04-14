################################################################################
# UMCCMD Timing Counter Optimization Permuton Procs
# Target: TwtrCtr, WrWrCtr, RdRdCtr counters
# Updated: 2026-02-19 - Fixed proc signature for DSO.ai compatibility
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_timer_counter_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_timing_counter_opt)
    puts "INFO: [info level 0] - Applying timing counter optimization: $permuton_value"

    set do_pipeline false
    set do_restructure false

    switch $permuton_value {
        "none" {
            puts "  Timing counter optimization: DISABLED"
            return
        }
        "pipeline" {
            set do_pipeline true
            puts "  Mode: Pipeline counter logic"
        }
        "restructure" {
            set do_restructure true
            puts "  Mode: Restructure counter implementation"
        }
        "both" {
            set do_pipeline true
            set do_restructure true
            puts "  Mode: Both pipeline and restructure"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # Find timing counter cells
    set counter_patterns [list "*TwtrCtr*" "*WrWrCtr*" "*RdRdCtr*" "*RdBusyCtr*"]
    set found_counters 0

    foreach pattern $counter_patterns {
        set matched_cells [get_cells -quiet -hier -filter "full_name =~ $pattern"]
        if {[sizeof_collection $matched_cells] > 0} {
            puts "  Found counter cells matching $pattern: [sizeof_collection $matched_cells]"

            # Group counter paths for focused optimization with weight
            set group_name [format "counter_%s" [string map {* ""} $pattern]]
            group_path -name $group_name -to $matched_cells -weight 2.0

            if {$do_restructure} {
                # Allow restructuring of counter logic
                set_dont_touch $matched_cells false

                # Filter hierarchical cells only for set_boundary_optimization
                # (leaf cells cannot have boundary optimization set - causes CMD-012)
                set matched_hier_cells [filter_collection $matched_cells "is_hierarchical == true"]
                if {[sizeof_collection $matched_hier_cells] > 0} {
                    set_boundary_optimization $matched_hier_cells all
                    puts "  Applied boundary optimization to [sizeof_collection $matched_hier_cells] hierarchical cells"
                }

                # Increase optimization effort using FC app_options
                set_app_options -name opt.timing.effort -value high
            }

            if {$do_pipeline} {
                # Enable retiming for pipeline insertion using FC app_options
                set_app_options -name compile.retiming.optimization_priority -value timing
                set_app_options -name opt.common.allow_physical_feedthrough -value true
            }

            incr found_counters [sizeof_collection $matched_cells]
        }
    }

    if {$found_counters > 0} {
        puts "  Applied timing counter optimizations to $found_counters cells"
    } else {
        puts "  WARNING: No timing counter cells found"
    }

    return
}

define_proc_attributes umccmd_before_timer_counter_proc -info "Timing counter optimization permuton" \
    -define_args { \
        {umccmd_timing_counter_opt "Timing counter optimization mode" umccmd_timing_counter_opt string required} \
    }

proc umccmd_after_timer_counter_proc {} {
    puts "INFO: [info level 0] - Cleaning up timing counter settings"

    # Remove counter path groups
    set counter_groups [list "counter_TwtrCtr" "counter_WrWrCtr" "counter_RdRdCtr" "counter_RdBusyCtr"]
    foreach group $counter_groups {
        if {[sizeof_collection [get_path_groups -quiet $group]] > 0} {
            remove_path_group $group
        }
    }

    # Reset app_options to defaults
    reset_app_options opt.timing.effort
    reset_app_options compile.retiming.optimization_priority
    reset_app_options opt.common.allow_physical_feedthrough

    return
}

}
