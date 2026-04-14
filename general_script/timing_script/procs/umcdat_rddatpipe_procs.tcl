################################################################################
# UMCDAT RdDatPipe Stage Balancing Permuton Procs
# Target: RdDatPipe registers across RDPIPE0-6 instances
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umcdat_before_rddatpipe_proc {permuton_name permuton_value} {
    puts "INFO: [info level 0] - Applying RdDatPipe balancing: $permuton_value"

    set balance_level 0

    switch $permuton_value {
        "none" {
            puts "  RdDatPipe balancing: DISABLED"
            return
        }
        "light" {
            set balance_level 1
            puts "  Balance level: LIGHT (within-instance)"
        }
        "balanced" {
            set balance_level 2
            puts "  Balance level: BALANCED (cross-instance)"
        }
        "aggressive" {
            set balance_level 3
            puts "  Balance level: AGGRESSIVE (cross-instance + duplication)"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # Find RdDatPipe cells across all 7 instances (RDPIPE0-6)
    set rddatpipe_cells [get_cells -quiet -hier -filter "full_name =~ *RdDatPipe*"]

    if {[sizeof_collection $rddatpipe_cells] == 0} {
        puts "  WARNING: No RdDatPipe cells found"
        return
    }

    puts "  Found RdDatPipe cells: [sizeof_collection $rddatpipe_cells]"

    # Count instances
    for {set i 0} {$i < 7} {incr i} {
        set pipe_instance [get_cells -quiet -hier -filter "full_name =~ *RDPIPE${i}*RdDatPipe*"]
        if {[sizeof_collection $pipe_instance] > 0} {
            puts "  RDPIPE${i}: [sizeof_collection $pipe_instance] RdDatPipe cells"
        }
    }

    if {$balance_level >= 1} {
        # Light: Enable retiming within each instance
        set_app_options -name compile.flow.enable_retiming -value true
    }

    if {$balance_level >= 2} {
        # Balanced: Enable cross-instance optimization
        set_app_options -name opt.common.group_path_delays -value true

        # Create unified path group for all RdDatPipe instances
        set_path_group -name rddatpipe_all_group -through $rddatpipe_cells
        set_critical_range 0.3 [get_clocks UCLK] -path_group rddatpipe_all_group
    }

    if {$balance_level >= 3} {
        # Aggressive: Allow duplication across instances
        set_app_options -name compile.flow.allow_duplication -value true
        set_dont_touch $rddatpipe_cells false

        # Filter hierarchical cells only for set_boundary_optimization
        # (leaf cells cannot have boundary optimization set - causes CMD-012)
        set rddatpipe_hier_cells [filter_collection $rddatpipe_cells "is_hierarchical == true"]
        if {[sizeof_collection $rddatpipe_hier_cells] > 0} {
            set_boundary_optimization $rddatpipe_hier_cells all
            puts "  Applied boundary optimization to [sizeof_collection $rddatpipe_hier_cells] hierarchical cells"
        }
    }

    puts "  Applied RdDatPipe balancing (level $balance_level)"

    return
}

proc umcdat_after_rddatpipe_proc {} {
    puts "INFO: [info level 0] - Cleaning up RdDatPipe balancing settings"

    # Remove custom path group
    if {[sizeof_collection [get_path_groups -quiet rddatpipe_all_group]] > 0} {
        remove_path_group rddatpipe_all_group
    }

    return
}

}
