############################################################
# dso_cond_default_arcs Permuton Procedures
# Purpose: Enable conditional default timing arcs
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
############################################################

namespace eval ::DSO::PERMUTONS {

  proc dso_before_cond_arcs_proc {permuton_name permuton_value} {
    puts "INFO: Setting conditional default arcs to $permuton_value"

    if {$permuton_value == "true"} {
      # Enable conditional default timing arcs using FC syntax
      set_app_options -name time.enable_cond_default_arcs -value true
      puts "INFO: Conditional default timing arcs enabled"

    } else {
      # false - standard timing arcs
      set_app_options -name time.enable_cond_default_arcs -value false
      puts "INFO: Standard timing arcs (conditional arcs disabled)"
    }
  }

  proc dso_after_cond_arcs_proc {} {
    puts "INFO: Restoring conditional default arcs to default"

    # Reset to default using FC syntax
    reset_app_options time.enable_cond_default_arcs
  }

}
