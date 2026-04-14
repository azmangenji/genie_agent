############################################################
# dso_area_recovery Permuton Procedures
# Purpose: Control area recovery to preserve timing gains
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
############################################################

namespace eval ::DSO::PERMUTONS {

  proc dso_before_area_recovery_proc {permuton_name permuton_value} {
    puts "INFO: Setting area recovery to $permuton_value"

    if {$permuton_value == "false"} {
      # Disable area recovery to preserve timing using FC syntax
      set_app_options -name compile.timing.area_recovery -value false
      puts "INFO: Area recovery disabled - timing will be preserved"

    } else {
      # true - enable area recovery (default)
      set_app_options -name compile.timing.area_recovery -value true
      puts "INFO: Area recovery enabled"
    }
  }

  proc dso_after_area_recovery_proc {} {
    puts "INFO: Restoring area recovery to default"

    # Reset to default using FC syntax
    reset_app_options compile.timing.area_recovery
  }

}
