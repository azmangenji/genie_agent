################################################################################
# UMCDAT Encryption Datapath Buffering Permuton Procs
# Target: UMCSEC datapath critical nets
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umcdat_before_encrypt_buffer_proc {permuton_name permuton_value} {
    puts "INFO: [info level 0] - Applying encryption datapath buffering: ${permuton_value}x"

    set buffer_mult $permuton_value

    if {$buffer_mult < 1.0} {
        puts "  Encryption buffering: DISABLED"
        return
    }

    puts "  Buffering multiplier: ${buffer_mult}x"

    # Calculate buffering constraints based on multiplier
    # Baseline: max_fanout=50, max_transition=0.12
    set max_fanout [expr int(50.0 / $buffer_mult)]
    set max_transition [expr 0.12 / $buffer_mult]

    puts "  Max fanout: $max_fanout (baseline: 50)"
    puts "  Max transition: $max_transition (baseline: 0.12)"

    # Find UMCSEC datapath cells
    set umcsec_cells [get_cells -quiet -hier -filter "full_name =~ *UMCSEC*"]

    if {[sizeof_collection $umcsec_cells] == 0} {
        puts "  WARNING: No UMCSEC cells found"
        return
    }

    puts "  Found UMCSEC cells: [sizeof_collection $umcsec_cells]"

    # Get datapath nets (exclude clock/reset)
    set umcsec_nets [get_nets -quiet -of $umcsec_cells]
    set data_nets [filter_collection $umcsec_nets "full_name !~ *clk* && full_name !~ *rst*"]

    if {[sizeof_collection $data_nets] > 0} {
        puts "  Found [sizeof_collection $data_nets] UMCSEC datapath nets"

        # Apply buffering constraints
        set_max_transition $max_transition $data_nets
        set_max_capacitance [expr 0.5 / $buffer_mult] $data_nets

        # Set fanout limit for buffer insertion
        set_app_options -name opt.common.max_fanout -value $max_fanout

        puts "  Applied buffering constraints to encryption datapath"
    } else {
        puts "  WARNING: No UMCSEC datapath nets found"
    }

    return
}

proc umcdat_after_encrypt_buffer_proc {} {
    puts "INFO: [info level 0] - Cleaning up encryption buffering settings"

    # Reset to default buffering settings
    set_app_options -name opt.common.max_fanout -value 100

    return
}

}
