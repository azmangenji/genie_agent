################################################################################
# UMCCMD Control-to-Datapath Isolation Permuton Procs
# Target: Isolate high-fanout control from datapath
# Updated: 2026-02-09 - Fixed to use parse_proc_arguments for DSO value
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_ctrl_iso_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_control_isolation)
    puts "INFO: [info level 0] - Applying control-datapath isolation: $permuton_value"

    set use_buffers false
    set use_spatial false

    switch $permuton_value {
        "none" {
            puts "  Control isolation: DISABLED"
            return
        }
        "buffers" {
            set use_buffers true
            puts "  Mode: Buffer insertion isolation"
        }
        "spatial" {
            set use_spatial true
            puts "  Mode: Spatial placement separation"
        }
        "both" {
            set use_buffers true
            set use_spatial true
            puts "  Mode: Both buffers and spatial separation"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # Find high-fanout control registers
    set control_regs [list]

    set mrdimmen_cells [get_cells -quiet -hier -filter "ref_name =~ *MrDimmEn_reg*"]
    if {[sizeof_collection $mrdimmen_cells] > 0} {
        lappend control_regs $mrdimmen_cells
    }

    set autoref_cells [get_cells -quiet -hier -filter "full_name =~ *AutoRefReqPlr_reg*"]
    if {[sizeof_collection $autoref_cells] > 0} {
        lappend control_regs $autoref_cells
    }

    set idlebw_cells [get_cells -quiet -hier -filter "full_name =~ *IdleBWCfg_reg*"]
    if {[sizeof_collection $idlebw_cells] > 0} {
        lappend control_regs $idlebw_cells
    }

    if {[llength $control_regs] == 0} {
        puts "  WARNING: No control registers found for isolation"
        return
    }

    set control_collection [get_cells $control_regs]
    puts "  Found [sizeof_collection $control_collection] control registers"

    if {$use_buffers} {
        # Insert isolation buffers on control nets
        set control_nets [get_nets -quiet -of $control_collection]

        if {[sizeof_collection $control_nets] > 0} {
            # Set ideal network to force buffering
            set_ideal_network -no_propagate $control_nets

            # Or use explicit buffering constraints
            set_max_transition 0.08 $control_nets
            set_max_capacitance 0.4 $control_nets

            puts "  Applied buffer insertion constraints"
        }
    }

    if {$use_spatial} {
        # Note: Spatial constraints are design-specific and may need floorplan
        # This is a placeholder for actual spatial constraint commands
        puts "  Spatial separation requested (requires floorplan integration)"

        # Example (commented - requires actual floorplan):
        # create_bounds -name control_region -coordinate {x1 y1 x2 y2}
        # set_placement_area -cells $control_collection -region control_region
    }

    return
}

define_proc_attributes umccmd_before_ctrl_iso_proc -info "Control-datapath isolation permuton" \
    -define_args { \
        {umccmd_control_isolation "Isolation mode (none/buffers/spatial/both)" umccmd_control_isolation string required} \
    }

proc umccmd_after_ctrl_iso_proc {} {
    puts "INFO: [info level 0] - Cleaning up control isolation settings"

    # Reset ideal network if it was set
    # Note: get_nets with previous filter may not work in after_proc
    # So we remove all ideal networks (may be too aggressive)
    # reset_ideal_network [all_connected [get_pins -of_objects [all_registers]]]

    return
}

}
