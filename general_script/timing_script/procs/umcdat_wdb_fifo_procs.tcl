################################################################################
# UMCDAT WDB FIFO Optimization Permuton Procs
# Target: wrstor_fifo, RdAdr_s_reg paths
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umcdat_before_wdb_fifo_proc {permuton_name permuton_value} {
    puts "INFO: [info level 0] - Applying WDB FIFO optimization: $permuton_value"

    if {$permuton_value == "false"} {
        puts "  WDB FIFO optimization: DISABLED"
        return
    }

    # Find WDB cells
    set wrstor_cells [get_cells -quiet -hier -filter "full_name =~ *wrstor_fifo*"]
    set rdadr_cells [get_cells -quiet -hier -filter "full_name =~ *RdAdr_s_reg*"]

    set found_cells 0

    if {[sizeof_collection $wrstor_cells] > 0} {
        puts "  Found wrstor_fifo cells: [sizeof_collection $wrstor_cells]"
        set_path_group -name wrstor_fifo_group -through $wrstor_cells
        set_critical_range 0.3 [get_clocks UCLK] -path_group wrstor_fifo_group
        set_dont_touch $wrstor_cells false
        incr found_cells [sizeof_collection $wrstor_cells]
    }

    if {[sizeof_collection $rdadr_cells] > 0} {
        puts "  Found RdAdr_s_reg cells: [sizeof_collection $rdadr_cells]"
        # These are high-fanout address registers
        set_dont_touch [get_nets -of $rdadr_cells] false
        size_cell -all_instances $rdadr_cells
        incr found_cells [sizeof_collection $rdadr_cells]
    }

    if {$found_cells > 0} {
        puts "  Applied WDB FIFO optimizations to $found_cells cells"
    } else {
        puts "  WARNING: No WDB FIFO cells found"
    }

    return
}

proc umcdat_after_wdb_fifo_proc {} {
    puts "INFO: [info level 0] - Cleaning up WDB FIFO settings"

    # Remove custom path group
    if {[sizeof_collection [get_path_groups -quiet wrstor_fifo_group]] > 0} {
        remove_path_group wrstor_fifo_group
    }

    return
}

}
