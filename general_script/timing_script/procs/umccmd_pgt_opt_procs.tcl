################################################################################
# UMCCMD Page Table Optimization Permuton Procs
# Target: PGT allocation logic
# Updated: 2026-02-19 - Fixed proc signature for DSO.ai compatibility
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_pgt_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_pgt_optimization)
    puts "INFO: [info level 0] - Applying page table optimization: $permuton_value"

    if {$permuton_value == "false"} {
        puts "  Page table optimization: DISABLED"
        return
    }

    # Find PGT cells
    set pgt_cells [get_cells -quiet -hier -filter "full_name =~ *PGT*"]

    if {[sizeof_collection $pgt_cells] == 0} {
        puts "  WARNING: No PGT cells found"
        return
    }

    puts "  Found PGT cells: [sizeof_collection $pgt_cells]"

    # Find PgtAlloc and PgtDeAlloc specifically
    set pgt_alloc [get_cells -quiet -hier -filter "full_name =~ *PgtAlloc*"]
    set pgt_dealloc [get_cells -quiet -hier -filter "full_name =~ *PgtDeAlloc*"]

    if {[sizeof_collection $pgt_alloc] > 0} {
        puts "  Found PgtAlloc cells: [sizeof_collection $pgt_alloc]"
        group_path -name pgt_alloc_group -to $pgt_alloc -weight 2.0
    }

    if {[sizeof_collection $pgt_dealloc] > 0} {
        puts "  Found PgtDeAlloc cells: [sizeof_collection $pgt_dealloc]"
        group_path -name pgt_dealloc_group -from $pgt_dealloc -weight 2.0
    }

    # Allow optimization on PGT logic
    set_dont_touch $pgt_cells false

    # Filter hierarchical cells only for set_boundary_optimization
    # (leaf cells cannot have boundary optimization set - causes CMD-012)
    set pgt_hier_cells [filter_collection $pgt_cells "is_hierarchical == true"]
    if {[sizeof_collection $pgt_hier_cells] > 0} {
        set_boundary_optimization $pgt_hier_cells all
        puts "  Applied boundary optimization to [sizeof_collection $pgt_hier_cells] hierarchical cells"
    }

    puts "  Applied page table logic optimizations"

    return
}

define_proc_attributes umccmd_before_pgt_proc -info "Page table optimization permuton" \
    -define_args { \
        {umccmd_pgt_optimization "Page table optimization enabled" umccmd_pgt_optimization string required} \
    }

proc umccmd_after_pgt_proc {} {
    puts "INFO: [info level 0] - Cleaning up page table settings"

    # Remove custom path groups
    if {[sizeof_collection [get_path_groups -quiet pgt_alloc_group]] > 0} {
        remove_path_group pgt_alloc_group
    }
    if {[sizeof_collection [get_path_groups -quiet pgt_dealloc_group]] > 0} {
        remove_path_group pgt_dealloc_group
    }

    return
}

}
