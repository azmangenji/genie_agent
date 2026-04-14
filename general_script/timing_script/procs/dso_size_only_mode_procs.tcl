############################################################
# dso_size_only_mode Permuton Procedures
# Purpose: Use size-only optimization for faster iteration
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
############################################################

namespace eval ::DSO::PERMUTONS {

  proc dso_before_size_only_proc {permuton_name permuton_value} {
    puts "INFO: Setting size-only mode to $permuton_value"

    if {$permuton_value == "true"} {
      # Enable size-only optimization (no buffering/restructuring) using FC syntax
      set_app_options -name compile.timing.size_only_mode -value true
      set_app_options -name compile.timing.buffer_insertion -value false
      puts "INFO: Size-only optimization enabled (faster iteration)"

    } else {
      # false - full optimization
      set_app_options -name compile.timing.size_only_mode -value false
      set_app_options -name compile.timing.buffer_insertion -value true
      puts "INFO: Full optimization mode (size-only disabled)"
    }
  }

  proc dso_after_size_only_proc {} {
    puts "INFO: Restoring size-only mode to default"

    # Reset to default using FC syntax
    reset_app_options compile.timing.size_only_mode
    reset_app_options compile.timing.buffer_insertion
  }

}
