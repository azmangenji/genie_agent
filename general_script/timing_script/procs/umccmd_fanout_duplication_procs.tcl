################################################################################
# UMCCMD Fanout Duplication Permuton Procs
# Target: MrDimmEn_reg, IdleBWCfg_reg (removed AutoRefReqPlr - only 9 paths)
# Updated: 2026-02-19 - Fixed proc signature for DSO.ai compatibility
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_fanout_dup_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_fanout_duplication)
    puts "INFO: [info level 0] - Applying fanout duplication: $permuton_value"

    # Map permuton value to fanout threshold
    set fanout_threshold 10000
    switch $permuton_value {
        "none" {
            puts "  Fanout duplication: DISABLED"
            return
        }
        "low" {
            set fanout_threshold 200
            puts "  Fanout threshold: >200 (targets MrDimmEn_reg)"
        }
        "medium" {
            set fanout_threshold 150
            puts "  Fanout threshold: >150 (targets MrDimmEn, IdleBWCfg)"
        }
        "high" {
            set fanout_threshold 100
            puts "  Fanout threshold: >100 (targets all high-fanout regs)"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value, using medium"
            set fanout_threshold 150
        }
    }

    # Find high-fanout registers
    set high_fanout_regs [list]

    # Find MrDimmEn_reg
    set mrdimmen_cells [get_cells -quiet -hier -filter "ref_name =~ *MrDimmEn_reg*"]
    if {[sizeof_collection $mrdimmen_cells] > 0} {
        foreach_in_collection cell $mrdimmen_cells {
            set fanout [get_attribute [get_nets -quiet -of $cell] fanout]
            if {$fanout > $fanout_threshold} {
                lappend high_fanout_regs $cell
                puts "  Found MrDimmEn_reg: fanout=$fanout"
            }
        }
    }

    # Find IdleBWCfg_reg
    set idlebw_cells [get_cells -quiet -hier -filter "full_name =~ *IdleBWCfg_reg*"]
    if {[sizeof_collection $idlebw_cells] > 0} {
        foreach_in_collection cell $idlebw_cells {
            set fanout [get_attribute [get_nets -quiet -of $cell] fanout]
            if {$fanout > $fanout_threshold} {
                lappend high_fanout_regs $cell
                puts "  Found IdleBWCfg_reg: fanout=$fanout"
            }
        }
    }

    # Apply register duplication
    if {[llength $high_fanout_regs] > 0} {
        set reg_collection [get_cells $high_fanout_regs]

        # Enable register replication using FC app_options syntax
        set_app_options -name opt.common.user_instance_name_prefix -value HFOPT_
        set_app_options -name compile.seqmap.register_replication_placement_effort -value high
        set_dont_touch [get_nets -of $reg_collection] false

        # Size cells to allow duplication
        size_cell -all_instances $reg_collection

        # Create path groups for optimization focus with weight
        set fanout_nets [all_fanout -from $reg_collection -flat -only_cells]
        if {[sizeof_collection $fanout_nets] > 0} {
            group_path -name high_fanout_group -from $reg_collection -weight 2.0
        }

        puts "  Applied fanout duplication to [llength $high_fanout_regs] registers"
    } else {
        puts "  No registers found exceeding fanout threshold of $fanout_threshold"
    }

    return
}

define_proc_attributes umccmd_before_fanout_dup_proc -info "Fanout duplication permuton" \
    -define_args { \
        {umccmd_fanout_duplication "Fanout duplication level" umccmd_fanout_duplication string required} \
    }

proc umccmd_after_fanout_dup_proc {} {
    puts "INFO: [info level 0] - Cleaning up fanout duplication settings"

    # Remove custom path group if it exists
    if {[sizeof_collection [get_path_groups -quiet high_fanout_group]] > 0} {
        remove_path_group high_fanout_group
    }

    # Reset app_options to defaults
    reset_app_options opt.common.user_instance_name_prefix
    reset_app_options compile.seqmap.register_replication_placement_effort

    return
}

}
