################################################################################
# UMCCMD Critical Path Groups Permuton Procs
# Target: Group paths by critical startpoints + IO paths
# Updated: 2026-03-18 - Added IO path coverage (I2R, R2O, io_to_flop, io_to_io)
################################################################################
# V4 Changes:
#   - Added IO path groups to address -70K ps TNS regression from 4Mac40p
#   - SYN_I2R: -60,377 ps regression (now covered)
#   - io_to_flop: -4,564 ps regression (now covered)
#   - io_to_io: -3,682 ps regression (now covered)
#   - SYN_R2O: -1,572 ps regression (now covered)
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_crit_groups_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_critical_path_groups)
    puts "INFO: [info level 0] - Applying critical path grouping: $permuton_value"

    set num_groups 0
    set path_weight 1.5
    set io_weight 1.3
    set io_critical_range 300

    switch $permuton_value {
        "none" {
            puts "  Critical path grouping: DISABLED"
            return
        }
        "standard" {
            set num_groups 2
            set path_weight 1.5
            set io_weight 1.3
            set io_critical_range 300
            puts "  Mode: STANDARD (top 2 startpoints + IO paths, path weight: 1.5)"
        }
        "aggressive" {
            set num_groups 5
            set path_weight 2.5
            set io_weight 2.0
            set io_critical_range 500
            puts "  Mode: AGGRESSIVE (top 5 startpoints + IO paths, path weight: 2.5)"
        }
        default {
            puts "WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    # Create path groups for critical startpoints
    set group_count 0

    # =========================================================================
    # IO PATH GROUPS (NEW in V4 - address -70K ps TNS regression)
    # =========================================================================
    puts "  Creating IO path groups..."

    # IO Group 1: I2R paths (SYN_I2R had -60,377 ps regression)
    set all_inputs [all_inputs]
    set all_regs [all_registers]
    if {[sizeof_collection $all_inputs] > 0 && [sizeof_collection $all_regs] > 0} {
        group_path -name crit_i2r_group -from $all_inputs -to $all_regs \
            -weight $io_weight -critical_range $io_critical_range
        puts "    Created I2R path group (weight: $io_weight, crit_range: $io_critical_range)"
        incr group_count
    }

    # IO Group 2: R2O paths (SYN_R2O had -1,572 ps regression)
    set all_outputs [all_outputs]
    if {[sizeof_collection $all_regs] > 0 && [sizeof_collection $all_outputs] > 0} {
        group_path -name crit_r2o_group -from $all_regs -to $all_outputs \
            -weight $io_weight -critical_range $io_critical_range
        puts "    Created R2O path group (weight: $io_weight, crit_range: $io_critical_range)"
        incr group_count
    }

    # IO Group 3: IO-to-IO combinational paths (io_to_io had -3,682 ps regression)
    if {[sizeof_collection $all_inputs] > 0 && [sizeof_collection $all_outputs] > 0} {
        group_path -name crit_io2io_group -from $all_inputs -to $all_outputs \
            -weight $io_weight -critical_range $io_critical_range
        puts "    Created IO-to-IO path group (weight: $io_weight)"
        incr group_count
    }

    # =========================================================================
    # R2R CRITICAL STARTPOINT GROUPS (existing)
    # =========================================================================
    puts "  Creating R2R critical startpoint groups..."

    # Group 1: MrDimmEn_reg (665 paths - 18.5%)
    set mrdimmen_cells [get_cells -quiet -hier -filter "ref_name =~ *MrDimmEn_reg*"]
    if {[sizeof_collection $mrdimmen_cells] > 0} {
        group_path -name crit_mrdimmen_group -from $mrdimmen_cells -weight $path_weight
        puts "    Created path group for MrDimmEn_reg"
        incr group_count
    }

    # Group 2: AutoRefReqPlr_reg (309 paths - 8.6%)
    if {$num_groups >= 2} {
        set autoref_cells [get_cells -quiet -hier -filter "full_name =~ *AutoRefReqPlr_reg*"]
        if {[sizeof_collection $autoref_cells] > 0} {
            group_path -name crit_autoref_group -from $autoref_cells -weight $path_weight
            puts "    Created path group for AutoRefReqPlr_reg"
            incr group_count
        }
    }

    # Additional groups for aggressive mode
    if {$num_groups >= 5} {
        # Group 3: IdleBWCfg_reg (184 paths - 5.1%)
        set idlebw_cells [get_cells -quiet -hier -filter "full_name =~ *IdleBWCfg_reg*"]
        if {[sizeof_collection $idlebw_cells] > 0} {
            group_path -name crit_idlebw_group -from $idlebw_cells -weight $path_weight
            puts "    Created path group for IdleBWCfg_reg"
            incr group_count
        }

        # Group 4: Timing counters
        set counter_cells [get_cells -quiet -hier -filter "full_name =~ *TwtrCtr* || full_name =~ *WrWrCtr*"]
        if {[sizeof_collection $counter_cells] > 0} {
            group_path -name crit_counter_group -from $counter_cells -weight $path_weight
            puts "    Created path group for timing counters"
            incr group_count
        }

        # Group 5: DCQ arbiter
        set dcqarb_cells [get_cells -quiet -hier -filter "full_name =~ *DCQARB*"]
        if {[sizeof_collection $dcqarb_cells] > 0} {
            group_path -name crit_dcqarb_group -through $dcqarb_cells -weight $path_weight
            puts "    Created path group for DCQ arbiter"
            incr group_count
        }
    }

    puts "  Created $group_count critical path groups (including IO paths)"

    return
}

define_proc_attributes umccmd_before_crit_groups_proc -info "Critical path groups permuton" \
    -define_args { \
        {umccmd_critical_path_groups "Critical path grouping mode" umccmd_critical_path_groups string required} \
    }

proc umccmd_after_crit_groups_proc {} {
    puts "INFO: [info level 0] - Cleaning up critical path groups"

    # Remove all critical path groups (including new IO path groups)
    set crit_groups [list "crit_mrdimmen_group" "crit_autoref_group" "crit_idlebw_group" \
                          "crit_counter_group" "crit_dcqarb_group" \
                          "crit_i2r_group" "crit_r2o_group" "crit_io2io_group"]
    foreach group $crit_groups {
        if {[sizeof_collection [get_path_groups -quiet $group]] > 0} {
            remove_path_group $group
            puts "  Removed path group: $group"
        }
    }

    return
}

}
