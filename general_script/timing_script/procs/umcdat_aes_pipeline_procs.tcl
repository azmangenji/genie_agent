################################################################################
# UMCDAT AES Pipeline Balancing Permuton Procs
# Target: UMCSEC_RDPIPE, UMCSEC_WRPIPE encryption pipelines
# Updated: 2026-01-26 - Fixed FC syntax (dot notation, removed invalid commands)
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umcdat_before_aes_pipeline_proc {permuton_name permuton_value} {
    puts "INFO: [info level 0] - Applying AES pipeline balancing: $permuton_value"

    set balance_level 0

    switch $permuton_value {
        "none" {
            puts "  AES pipeline balancing: DISABLED"
            return
        }
        "light" {
            set balance_level 1
            puts "  Balance level: LIGHT (10-15% redistribution)"
        }
        "balanced" {
            set balance_level 2
            puts "  Balance level: BALANCED (20-30% redistribution)"
        }
        "aggressive" {
            set balance_level 3
            puts "  Balance level: AGGRESSIVE (30-40% + possible stage insertion)"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # Find AES pipeline cells
    set aes_pipe_cells [get_cells -quiet -hier -filter "full_name =~ *UMCSEC*PIPE*"]

    if {[sizeof_collection $aes_pipe_cells] == 0} {
        puts "  WARNING: No AES pipeline cells found"
        return
    }

    puts "  Found AES pipeline cells: [sizeof_collection $aes_pipe_cells]"

    # Find specific pipeline stages
    set rdkey_pipe [get_cells -quiet -hier -filter "full_name =~ *RdKeyPipe*"]
    set wrkey_pipe [get_cells -quiet -hier -filter "full_name =~ *WrKeyPipe*"]
    set rddat_pipe [get_cells -quiet -hier -filter "full_name =~ *RdDatPipe*"]
    set xts_pipe [get_cells -quiet -hier -filter "full_name =~ *XtsDatPipe*"]

    if {[sizeof_collection $rdkey_pipe] > 0} {
        puts "  Found RdKeyPipe: [sizeof_collection $rdkey_pipe] cells"
        group_path -name rdkey_pipe_group -through $rdkey_pipe -weight 2.0
    }

    if {[sizeof_collection $wrkey_pipe] > 0} {
        puts "  Found WrKeyPipe: [sizeof_collection $wrkey_pipe] cells"
        group_path -name wrkey_pipe_group -through $wrkey_pipe -weight 2.0
    }

    if {[sizeof_collection $xts_pipe] > 0} {
        puts "  Found XtsDatPipe: [sizeof_collection $xts_pipe] cells"
        group_path -name xts_pipe_group -through $xts_pipe -weight 2.0
    }

    # Enable retiming based on balance level using FC app_options syntax
    if {$balance_level >= 1} {
        set_app_options -name compile.retiming.optimization_priority -value timing
        set_app_options -name opt.common.allow_physical_feedthrough -value true
    }

    if {$balance_level >= 2} {
        # Use FC app_options for register optimization
        set_app_options -name compile.seqmap.register_replication_placement_effort -value high
    }

    if {$balance_level >= 3} {
        # Aggressive: enable high effort timing and area resynthesis
        set_app_options -name compile.flow.areaResynthesis -value true
        set_app_options -name compile.flow.high_effort_timing -value 1
    }

    # Allow boundary optimization
    set_dont_touch $aes_pipe_cells false

    # Filter hierarchical cells only for set_boundary_optimization
    # (leaf cells cannot have boundary optimization set - causes CMD-012)
    set aes_pipe_hier_cells [filter_collection $aes_pipe_cells "is_hierarchical == true"]
    if {[sizeof_collection $aes_pipe_hier_cells] > 0} {
        set_boundary_optimization $aes_pipe_hier_cells all
        puts "  Applied boundary optimization to [sizeof_collection $aes_pipe_hier_cells] hierarchical cells"
    }

    puts "  Applied AES pipeline balancing (level $balance_level)"

    return
}

proc umcdat_after_aes_pipeline_proc {} {
    puts "INFO: [info level 0] - Cleaning up AES pipeline settings"

    # Remove custom path groups
    set pipe_groups [list "rdkey_pipe_group" "wrkey_pipe_group" "xts_pipe_group"]
    foreach group $pipe_groups {
        if {[sizeof_collection [get_path_groups -quiet $group]] > 0} {
            remove_path_group $group
        }
    }

    # Reset app_options to defaults
    reset_app_options compile.retiming.optimization_priority
    reset_app_options opt.common.allow_physical_feedthrough
    reset_app_options compile.seqmap.register_replication_placement_effort
    reset_app_options compile.flow.areaResynthesis
    reset_app_options compile.flow.high_effort_timing

    return
}

}
