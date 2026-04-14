############################################################
# dso_retime_mode Permuton Procedures
# Purpose: Enable register retiming for timing optimization
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
############################################################

namespace eval ::DSO::PERMUTONS {

  proc dso_before_retime_mode_proc {permuton_name permuton_value} {
    puts "INFO: Setting retiming mode to $permuton_value"

    if {$permuton_value == "simple"} {
      # Enable simple retiming (basic register movement)
      # Using FC app_options syntax with dot notation
      set_app_options -name compile.register_retiming.mode -value simple
      puts "INFO: Simple retiming enabled"

    } elseif {$permuton_value == "advanced"} {
      # Enable full retiming with logic restructuring
      set_app_options -name compile.register_retiming.mode -value full
      set_app_options -name compile.flow.enable_retiming -value true
      puts "INFO: Advanced retiming enabled"

    } else {
      # none - no retiming
      set_app_options -name compile.register_retiming.mode -value none
      puts "INFO: Retiming disabled (none)"
    }
  }

  proc dso_after_retime_mode_proc {} {
    puts "INFO: Disabling retiming modes"

    # Reset retiming variables using FC syntax
    reset_app_options compile.register_retiming.mode
    reset_app_options compile.flow.enable_retiming
  }

}
