############################################################
# dso_ultra_optimization Permuton Procedures
# Purpose: Enable ultra optimization mode for better QoR
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
############################################################

namespace eval ::DSO::PERMUTONS {

  proc dso_before_ultra_opt_proc {permuton_name permuton_value} {
    puts "INFO: Setting ultra optimization to $permuton_value"

    if {$permuton_value == "true"} {
      # Enable ultra optimization features using FC syntax
      set_app_options -name compile.flow.effort -value ultra
      set_app_options -name compile.timing.effort -value ultra
      set_app_options -name compile.flow.enable_tns_optimization -value true
      puts "INFO: Ultra optimization enabled (longer runtime, better QoR expected)"

    } else {
      # false - standard optimization
      puts "INFO: Standard optimization (ultra mode disabled)"
    }
  }

  proc dso_after_ultra_opt_proc {} {
    puts "INFO: Restoring ultra optimization settings to defaults"

    # Reset ultra optimization variables using FC syntax
    reset_app_options compile.flow.effort
    reset_app_options compile.timing.effort
    reset_app_options compile.flow.enable_tns_optimization
  }

}
