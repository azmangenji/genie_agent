################################################################################
# UMCDAT ECC Read Optimization Permuton Procs
# Target: ECCRD logic, EccSymbl, syndrome generation
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umcdat_before_ecc_read_proc {permuton_name permuton_value} {
    puts "INFO: [info level 0] - Applying ECC read optimization: $permuton_value"

    set effort_level "standard"
    set path_weight 1.0

    switch $permuton_value {
        "standard" {
            set effort_level "standard"
            set path_weight 1.0
            puts "  Optimization effort: STANDARD"
        }
        "high" {
            set effort_level "high"
            set path_weight 2.0
            puts "  Optimization effort: HIGH"
        }
        "ultra" {
            set effort_level "ultra"
            set path_weight 3.0
            puts "  Optimization effort: ULTRA"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value, using standard"
        }
    }

    # Find ECC cells
    set ecc_cells [get_cells -quiet -hier -filter "full_name =~ *ECC*"]

    if {[sizeof_collection $ecc_cells] == 0} {
        puts "  WARNING: No ECC cells found"
        return
    }

    puts "  Found ECC cells: [sizeof_collection $ecc_cells]"

    # Find ECCRD specifically
    set eccrd_cells [get_cells -quiet -hier -filter "full_name =~ *ECCRD*"]
    if {[sizeof_collection $eccrd_cells] > 0} {
        puts "  Found ECCRD cells: [sizeof_collection $eccrd_cells]"
        group_path -name eccrd_group -through $eccrd_cells -weight $path_weight
    }

    # Find EccSymbl registers
    set ecc_symbl [get_cells -quiet -hier -filter "full_name =~ *EccSymbl*"]
    if {[sizeof_collection $ecc_symbl] > 0} {
        puts "  Found EccSymbl cells: [sizeof_collection $ecc_symbl]"
        group_path -name ecc_symbl_group -from $ecc_symbl -weight [expr $path_weight * 1.2]
    }

    # Increase optimization effort on ECC logic
    set_dont_touch $ecc_cells false

    # Filter hierarchical cells only for set_boundary_optimization
    # (leaf cells cannot have boundary optimization set - causes CMD-012)
    set ecc_hier_cells [filter_collection $ecc_cells "is_hierarchical == true"]
    if {[sizeof_collection $ecc_hier_cells] > 0} {
        set_boundary_optimization $ecc_hier_cells all
        puts "  Applied boundary optimization to [sizeof_collection $ecc_hier_cells] hierarchical cells"
    }

    # Note: set_max_area removed - causes CMD-012 with large cell collections
    # Area constraints should be set at design level if needed

    # Set optimization effort using FC syntax
    if {$effort_level == "high"} {
        set_app_options -name opt.timing.effort -value high
    } elseif {$effort_level == "ultra"} {
        set_app_options -name opt.timing.effort -value high
        set_app_options -name compile.flow.high_effort_timing -value 1
        puts "  Enabled ultra optimization mode"
    }

    puts "  Applied ECC read path optimizations ($effort_level)"

    return
}

proc umcdat_after_ecc_read_proc {} {
    puts "INFO: [info level 0] - Cleaning up ECC read settings"

    # Remove custom path groups
    if {[sizeof_collection [get_path_groups -quiet eccrd_group]] > 0} {
        remove_path_group eccrd_group
    }
    if {[sizeof_collection [get_path_groups -quiet ecc_symbl_group]] > 0} {
        remove_path_group ecc_symbl_group
    }

    # Reset app_options to defaults
    reset_app_options opt.timing.effort
    reset_app_options compile.flow.high_effort_timing

    return
}

}
