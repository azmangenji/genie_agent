################################################################################
# UMCDAT Key Pipeline Retiming Permuton Procs
# Target: RdKeyPipe, WrKeyPipe registers
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umcdat_before_key_retime_proc {permuton_name permuton_value} {
    puts "INFO: [info level 0] - Applying key pipeline retiming: $permuton_value"

    set retime_mode "none"

    switch $permuton_value {
        "none" {
            puts "  Key pipeline retiming: DISABLED"
            return
        }
        "forward" {
            set retime_mode "forward"
            puts "  Retiming mode: FORWARD (move registers toward outputs)"
        }
        "backward" {
            set retime_mode "backward"
            puts "  Retiming mode: BACKWARD (move registers toward inputs)"
        }
        "adaptive" {
            set retime_mode "adaptive"
            puts "  Retiming mode: ADAPTIVE (tool decides per register)"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # Find key pipeline cells
    set rdkey_pipe [get_cells -quiet -hier -filter "full_name =~ *RdKeyPipe*"]
    set wrkey_pipe [get_cells -quiet -hier -filter "full_name =~ *WrKeyPipe*"]

    set key_pipe_cells [list]
    if {[sizeof_collection $rdkey_pipe] > 0} {
        puts "  Found RdKeyPipe: [sizeof_collection $rdkey_pipe] cells"
        lappend key_pipe_cells $rdkey_pipe
    }
    if {[sizeof_collection $wrkey_pipe] > 0} {
        puts "  Found WrKeyPipe: [sizeof_collection $wrkey_pipe] cells"
        lappend key_pipe_cells $wrkey_pipe
    }

    if {[llength $key_pipe_cells] == 0} {
        puts "  WARNING: No key pipeline cells found"
        return
    }

    # Enable retiming with specified mode using FC app_options syntax
    # compile.retiming.optimization_priority: auto, area, timing
    if {$retime_mode == "forward" || $retime_mode == "backward"} {
        set_app_options -name compile.retiming.optimization_priority -value timing
    } else {
        set_app_options -name compile.retiming.optimization_priority -value auto
    }

    # Create path groups for key expansion paths with weight
    set key_collection [get_cells $key_pipe_cells]
    group_path -name key_expansion_group -through $key_collection -weight 2.0

    # Allow optimization
    set_dont_touch $key_collection false

    # Filter hierarchical cells only for set_boundary_optimization
    # (leaf cells cannot have boundary optimization set - causes CMD-012)
    set key_hier_cells [filter_collection $key_collection "is_hierarchical == true"]
    if {[sizeof_collection $key_hier_cells] > 0} {
        set_boundary_optimization $key_hier_cells all
        puts "  Applied boundary optimization to [sizeof_collection $key_hier_cells] hierarchical cells"
    }

    puts "  Applied key pipeline retiming ($retime_mode mode)"

    return
}

proc umcdat_after_key_retime_proc {} {
    puts "INFO: [info level 0] - Cleaning up key pipeline retiming settings"

    # Remove custom path group
    if {[sizeof_collection [get_path_groups -quiet key_expansion_group]] > 0} {
        remove_path_group key_expansion_group
    }

    # Reset retiming mode to default using FC syntax
    reset_app_options compile.retiming.optimization_priority

    return
}

}
