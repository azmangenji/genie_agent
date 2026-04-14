############################################################
# dso_critical_range Permuton Procedures
# Purpose: Control critical path range for optimization
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
############################################################

namespace eval ::DSO::PERMUTONS {

  variable saved_critical_range

  proc dso_before_critical_range_proc {permuton_name permuton_value} {
    variable saved_critical_range

    puts "INFO: Setting critical range to $permuton_value"

    # Save original value using FC dot notation
    if {[catch {get_app_option_value [get_app_options compile.timing.critical_range]} val]} {
      set saved_critical_range ""
      puts "INFO: Could not get current compile.timing.critical_range value"
    } else {
      set saved_critical_range $val
    }

    # Set new critical range using FC app_options syntax
    # Lower values = more paths considered critical
    set_app_options -name compile.timing.critical_range -value $permuton_value

    puts "INFO: Critical range changed from $saved_critical_range to $permuton_value"
  }

  proc dso_after_critical_range_proc {} {
    variable saved_critical_range

    puts "INFO: Restoring critical range"

    # Reset to default using FC syntax
    reset_app_options compile.timing.critical_range
  }

}
