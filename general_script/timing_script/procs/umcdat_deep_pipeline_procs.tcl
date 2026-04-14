################################################################################
# UMCDAT Deep Pipeline Register Insertion Permuton Procs
# Target: Paths with 25+ logic levels
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umcdat_before_deep_pipeline_proc {permuton_name permuton_value} {
    puts "INFO: [info level 0] - Applying deep pipeline register insertion: $permuton_value"

    set logic_level_threshold 100

    switch $permuton_value {
        "none" {
            puts "  Deep pipeline insertion: DISABLED"
            return
        }
        "conservative" {
            set logic_level_threshold 30
            puts "  Logic level threshold: >30 (conservative)"
        }
        "moderate" {
            set logic_level_threshold 25
            puts "  Logic level threshold: >25 (moderate)"
        }
        "aggressive" {
            set logic_level_threshold 20
            puts "  Logic level threshold: >20 (aggressive)"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # Get all timing paths
    set all_paths [get_timing_paths -quiet -max_paths 1000 -slack_lesser_than 0]

    if {[sizeof_collection $all_paths] > 0} {
        # Filter for deep logic paths
        set deep_paths [filter_collection $all_paths "levels_of_logic > $logic_level_threshold"]

        if {[sizeof_collection $deep_paths] > 0} {
            puts "  Found [sizeof_collection $deep_paths] paths with >$logic_level_threshold logic levels"

            # Get cells involved in these paths
            set deep_cells [get_cells -quiet -of [get_pins -quiet -of $deep_paths]]

            if {[sizeof_collection $deep_cells] > 0} {
                # Focus on UMCSEC cells in deep paths
                set deep_umcsec [filter_collection $deep_cells "full_name =~ *UMCSEC*"]

                if {[sizeof_collection $deep_umcsec] > 0} {
                    puts "  Found [sizeof_collection $deep_umcsec] UMCSEC cells in deep paths"

                    # Increase restructuring effort
                    set_app_options -name compile.flow.area_restructuring_effort -value high
                    set_dont_touch $deep_umcsec false

                    # Filter hierarchical cells only for set_boundary_optimization
                    # (leaf cells cannot have boundary optimization set - causes CMD-012)
                    set deep_umcsec_hier [filter_collection $deep_umcsec "is_hierarchical == true"]
                    if {[sizeof_collection $deep_umcsec_hier] > 0} {
                        set_boundary_optimization $deep_umcsec_hier all
                        puts "  Applied boundary optimization to [sizeof_collection $deep_umcsec_hier] hierarchical cells"
                    }

                    # Enable retiming for register insertion
                    set_app_options -name compile.flow.enable_retiming -value true
                    set_app_options -name opt.common.allow_physical_feedthrough -value true

                    puts "  Applied deep logic path optimizations"
                }
            }
        } else {
            puts "  No deep logic paths found (threshold: $logic_level_threshold)"
        }
    } else {
        puts "  No failing paths found for deep pipeline analysis"
    }

    return
}

proc umcdat_after_deep_pipeline_proc {} {
    puts "INFO: [info level 0] - Cleaning up deep pipeline settings"

    # No specific cleanup needed
    return
}

}
