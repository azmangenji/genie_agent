################################################################################
# UMCDAT XTS Pipeline Optimization Permuton Procs
# Target: XTSPIPE, XtsDatPipeNxt registers
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umcdat_before_xts_pipeline_proc {permuton_name permuton_value} {
    puts "INFO: [info level 0] - Applying XTS pipeline optimization: $permuton_value"

    set do_restructure false
    set do_add_stage false

    switch $permuton_value {
        "none" {
            puts "  XTS pipeline optimization: DISABLED"
            return
        }
        "restructure" {
            set do_restructure true
            puts "  Mode: RESTRUCTURE (Galois field multiplication)"
        }
        "add_stage" {
            set do_add_stage true
            puts "  Mode: ADD_STAGE (insert pipeline register)"
        }
        "both" {
            set do_restructure true
            set do_add_stage true
            puts "  Mode: BOTH (restructure + add stage)"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # Find XTS pipeline cells
    set xts_pipe [get_cells -quiet -hier -filter "full_name =~ *XTSPIPE* || full_name =~ *XtsDatPipe*"]

    if {[sizeof_collection $xts_pipe] == 0} {
        puts "  WARNING: No XTS pipeline cells found"
        return
    }

    puts "  Found XTS pipeline cells: [sizeof_collection $xts_pipe]"

    if {$do_restructure} {
        # Allow restructuring of Galois field multiplication logic using FC syntax
        set_dont_touch $xts_pipe false

        # Filter hierarchical cells only for set_boundary_optimization
        # (leaf cells cannot have boundary optimization set - causes CMD-012)
        set xts_hier_cells [filter_collection $xts_pipe "is_hierarchical == true"]
        if {[sizeof_collection $xts_hier_cells] > 0} {
            set_boundary_optimization $xts_hier_cells all
            puts "  Applied boundary optimization to [sizeof_collection $xts_hier_cells] hierarchical cells"
        }

        set_app_options -name opt.common.advanced_logic_restructuring_mode -value timing
        puts "  Enabled XTS logic restructuring"
    }

    if {$do_add_stage} {
        # Enable retiming to insert pipeline stages using FC syntax
        set_app_options -name compile.retiming.optimization_priority -value timing
        set_app_options -name opt.common.allow_physical_feedthrough -value true
        puts "  Enabled XTS pipeline stage insertion"
    }

    # Create path group for XTS optimization with weight
    group_path -name xts_opt_group -through $xts_pipe -weight 2.0

    puts "  Applied XTS pipeline optimizations"

    return
}

proc umcdat_after_xts_pipeline_proc {} {
    puts "INFO: [info level 0] - Cleaning up XTS pipeline settings"

    # Remove custom path group
    if {[sizeof_collection [get_path_groups -quiet xts_opt_group]] > 0} {
        remove_path_group xts_opt_group
    }

    # Reset app_options to defaults
    reset_app_options opt.common.advanced_logic_restructuring_mode
    reset_app_options compile.retiming.optimization_priority
    reset_app_options opt.common.allow_physical_feedthrough

    return
}

}
