############################################################
# dso_r2r_path_weight Permuton Procedures
# Purpose: Increase optimization weight for r2r paths
############################################################

namespace eval ::DSO::PERMUTONS {

  proc dso_before_r2r_weight_proc {permuton_name permuton_value} {
    puts "INFO: Setting r2r path group weight to $permuton_value"

    # Set cost priority to delay (timing focus)
    set_cost_priority -delay

    # Create weighted path group for register-to-register paths
    # Higher weight = higher optimization priority
    group_path -name R2R_CRITICAL \
      -weight $permuton_value \
      -from [all_registers -clock_pins] \
      -to [all_registers -data_pins]

    puts "INFO: R2R path group created with weight $permuton_value"
  }

  proc dso_after_r2r_weight_proc {} {
    puts "INFO: Removing r2r path group weight settings"

    # Clean up: remove the path group
    if {[sizeof_collection [get_path_groups R2R_CRITICAL -quiet]] > 0} {
      remove_path_group R2R_CRITICAL
    }
  }

}
