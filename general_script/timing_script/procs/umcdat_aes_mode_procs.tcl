################################################################################
# UMCDAT Aes128Mode Fanout Reduction Permuton Procs
# Target: Aes128Mode_reg control signal
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umcdat_before_aes_mode_proc {permuton_name permuton_value} {
    puts "INFO: [info level 0] - Applying Aes128Mode fanout reduction: $permuton_value"

    set do_replicate false
    set do_buffer false

    switch $permuton_value {
        "none" {
            puts "  Aes128Mode fanout reduction: DISABLED"
            return
        }
        "replicate" {
            set do_replicate true
            puts "  Mode: REPLICATE (duplicate register)"
        }
        "buffer" {
            set do_buffer true
            puts "  Mode: BUFFER (insert buffers)"
        }
        "both" {
            set do_replicate true
            set do_buffer true
            puts "  Mode: BOTH (replicate + buffer)"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # Find Aes128Mode_reg
    set aes_mode_cells [get_cells -quiet -hier -filter "full_name =~ *Aes128Mode_reg*"]

    if {[sizeof_collection $aes_mode_cells] == 0} {
        puts "  WARNING: No Aes128Mode_reg found"
        return
    }

    puts "  Found Aes128Mode_reg: [sizeof_collection $aes_mode_cells] instances"

    if {$do_replicate} {
        # Enable register replication for fanout reduction
        set_dont_touch [get_nets -of $aes_mode_cells] false
        size_cell -all_instances $aes_mode_cells
        puts "  Enabled register replication"
    }

    if {$do_buffer} {
        # Add buffering on Aes128Mode net
        set aes_mode_nets [get_nets -of $aes_mode_cells]
        set_max_transition 0.08 $aes_mode_nets
        set_max_capacitance 0.4 $aes_mode_nets
        puts "  Applied buffering constraints"
    }

    # Create path group for focused optimization
    set fanout_nets [all_fanout -from $aes_mode_cells -flat -only_cells]
    if {[sizeof_collection $fanout_nets] > 0} {
        set_path_group -name aes_mode_fanout_group -from $aes_mode_cells
        set_critical_range 0.4 [get_clocks UCLK] -path_group aes_mode_fanout_group
    }

    puts "  Applied Aes128Mode fanout reduction"

    return
}

proc umcdat_after_aes_mode_proc {} {
    puts "INFO: [info level 0] - Cleaning up Aes128Mode fanout settings"

    # Remove custom path group
    if {[sizeof_collection [get_path_groups -quiet aes_mode_fanout_group]] > 0} {
        remove_path_group aes_mode_fanout_group
    }

    return
}

}
