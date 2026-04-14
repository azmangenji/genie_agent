############################################################
# dso_congestion_util Permuton Procedures
# Purpose: Control placement utilization for congestion reduction
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
############################################################

namespace eval ::DSO::PERMUTONS {

  proc dso_before_congestion_util_proc {permuton_name permuton_value} {
    puts "INFO: Setting congestion-driven max utilization to $permuton_value"

    # Set placement utilization using FC app_options syntax
    # Lower values = more white space = less congestion = better timing
    set_app_options -name place.coarse.max_density -value $permuton_value
    set_app_options -name place_opt.congestion.max_util -value $permuton_value

    puts "INFO: Placement max utilization set to [expr {$permuton_value * 100}]%"
  }

  proc dso_after_congestion_util_proc {} {
    puts "INFO: Restoring congestion-driven max utilization to default"

    # Reset to default using FC syntax
    reset_app_options place.coarse.max_density
    reset_app_options place_opt.congestion.max_util
  }

}
