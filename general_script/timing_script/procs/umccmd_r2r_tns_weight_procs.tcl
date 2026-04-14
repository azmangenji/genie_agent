################################################################################
# UMCCMD R2R TNS Weight Balancing Permuton Procs
# Target: Balance R2R WNS vs R2R TNS optimization
# Created: 2026-03-03
################################################################################
# Analysis: 40p DSO run shows:
#   - 24 lineages beat R2R WNS baseline
#   - Only 6 lineages beat BOTH R2R WNS and R2R TNS
#   - WNS-focused runs sacrifice TNS for WNS
#
# R2R Path Groups (Feb23):
#   - Total R2R TNS: -116,554ps
#   - Total R2R NVP: 7,929 paths
################################################################################

namespace eval ::DSO::PERMUTONS {

proc umccmd_before_r2r_tns_weight_proc {args} {
    # Parse arguments - DSO passes permuton value as named argument
    parse_proc_arguments -args $args proc_args
    set permuton_value $proc_args(umccmd_r2r_tns_weight)
    puts "INFO: [info level 0] - Applying R2R TNS weight: $permuton_value"

    switch $permuton_value {
        "low" {
            # Focus on R2R WNS (current default behavior)
            # Lower TNS weight means tool prioritizes worst R2R paths
            set_app_options -block [current_block] -name opt.timing.slack_based_tns_optimization -value false

            puts "  Mode: LOW - WNS-focused R2R optimization"
        }
        "balanced" {
            # Balanced R2R WNS and R2R TNS
            set_app_options -block [current_block] -name opt.timing.slack_based_tns_optimization -value true
            set_app_options -block [current_block] -name opt.timing.effort -value high

            # Create weighted R2R path groups for TNS balance
            # Focus on high-TNS R2R groups
            set dcqarb_regs [get_cells -quiet -hier -filter "full_name =~ *DCQARB* && is_sequential == true"]
            if {[sizeof_collection $dcqarb_regs] > 0} {
                group_path -name r2r_tns_dcqarb -to $dcqarb_regs -weight 1.2
                puts "  Created DCQARB R2R TNS group: [sizeof_collection $dcqarb_regs] endpoints"
            }

            puts "  Mode: BALANCED - equal focus on R2R WNS and TNS"
        }
        "high" {
            # Focus on R2R TNS (more paths, better overall R2R timing)
            set_app_options -block [current_block] -name opt.timing.slack_based_tns_optimization -value true
            set_app_options -block [current_block] -name opt.timing.effort -value ultra

            # Increase number of R2R paths optimized per iteration
            set_app_options -block [current_block] -name opt.timing.tns_optimization_paths_per_endpoint -value 10

            # Create weighted R2R path groups for TNS focus
            set arb_regs [get_cells -quiet -hier -filter "full_name =~ *ARB* && is_sequential == true"]
            set dcqarb_regs [get_cells -quiet -hier -filter "full_name =~ *DCQARB* && is_sequential == true"]

            if {[sizeof_collection $arb_regs] > 0} {
                group_path -name r2r_tns_arb -to $arb_regs -weight 1.5
                puts "  Created ARB R2R TNS group: [sizeof_collection $arb_regs] endpoints"
            }
            if {[sizeof_collection $dcqarb_regs] > 0} {
                group_path -name r2r_tns_dcqarb -to $dcqarb_regs -weight 1.5
                puts "  Created DCQARB R2R TNS group: [sizeof_collection $dcqarb_regs] endpoints"
            }

            puts "  Mode: HIGH - TNS-focused R2R optimization"
        }
        default {
            puts "  WARNING: Unknown permuton value: $permuton_value"
            return
        }
    }

    return
}

define_proc_attributes umccmd_before_r2r_tns_weight_proc -info "R2R TNS weight balancing permuton" \
    -define_args { \
        {umccmd_r2r_tns_weight "R2R TNS weight mode" umccmd_r2r_tns_weight string required} \
    }

proc umccmd_after_r2r_tns_weight_proc {} {
    puts "INFO: [info level 0] - Cleaning up R2R TNS weight settings"

    # Reset app options
    reset_app_options opt.timing.slack_based_tns_optimization
    reset_app_options opt.timing.effort
    reset_app_options opt.timing.tns_optimization_paths_per_endpoint

    # Remove path groups
    if {[sizeof_collection [get_path_groups -quiet r2r_tns_arb]] > 0} {
        remove_path_group r2r_tns_arb
    }
    if {[sizeof_collection [get_path_groups -quiet r2r_tns_dcqarb]] > 0} {
        remove_path_group r2r_tns_dcqarb
    }

    return
}

}
