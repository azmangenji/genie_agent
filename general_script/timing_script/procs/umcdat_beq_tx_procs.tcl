################################################################################
# UMCDAT BEQ TX Path Optimization Permuton Procs
# Target: beq_tx logic, CA CRC
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umcdat_before_beq_tx_proc {permuton_name permuton_value} {
    puts "INFO: [info level 0] - Applying BEQ TX optimization: $permuton_value"

    if {$permuton_value == "false"} {
        puts "  BEQ TX optimization: DISABLED"
        return
    }

    # Find beq_tx cells
    set beq_tx_cells [get_cells -quiet -hier -filter "full_name =~ *beq_tx*"]

    if {[sizeof_collection $beq_tx_cells] == 0} {
        puts "  WARNING: No beq_tx cells found"
        return
    }

    puts "  Found beq_tx cells: [sizeof_collection $beq_tx_cells]"

    # Find CA CRC specifically
    set cacrc_cells [get_cells -quiet -hier -filter "full_name =~ *CACRC*"]
    if {[sizeof_collection $cacrc_cells] > 0} {
        puts "  Found CACRC cells: [sizeof_collection $cacrc_cells]"
        set_path_group -name cacrc_group -through $cacrc_cells
        set_critical_range 0.4 [get_clocks UCLK] -path_group cacrc_group
    }

    # Optimize beq_tx paths
    set_dont_touch $beq_tx_cells false

    # Filter hierarchical cells only for set_boundary_optimization
    # (leaf cells cannot have boundary optimization set - causes CMD-012)
    set beq_tx_hier_cells [filter_collection $beq_tx_cells "is_hierarchical == true"]
    if {[sizeof_collection $beq_tx_hier_cells] > 0} {
        set_boundary_optimization $beq_tx_hier_cells all
        puts "  Applied boundary optimization to [sizeof_collection $beq_tx_hier_cells] hierarchical cells"
    }

    # Create path group for BEQ TX
    set_path_group -name beq_tx_group -through $beq_tx_cells
    set_critical_range 0.3 [get_clocks UCLK] -path_group beq_tx_group

    puts "  Applied BEQ TX path optimizations"

    return
}

proc umcdat_after_beq_tx_proc {} {
    puts "INFO: [info level 0] - Cleaning up BEQ TX settings"

    # Remove custom path groups
    if {[sizeof_collection [get_path_groups -quiet cacrc_group]] > 0} {
        remove_path_group cacrc_group
    }
    if {[sizeof_collection [get_path_groups -quiet beq_tx_group]] > 0} {
        remove_path_group beq_tx_group
    }

    return
}

}
