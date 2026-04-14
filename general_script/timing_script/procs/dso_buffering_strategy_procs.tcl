############################################################
# dso_buffering_strategy Permuton Procedures
# Purpose: Control buffering aggressiveness for timing
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
############################################################

namespace eval ::DSO::PERMUTONS {

  proc dso_before_buffering_proc {permuton_name permuton_value} {
    puts "INFO: Setting buffering strategy to $permuton_value"

    if {$permuton_value == "aggressive"} {
      # Aggressive buffering using FC app_options syntax
      set_app_options -name compile.timing.buffer_replication -value true
      set_app_options -name opt.common.max_fanout -value 50
      puts "INFO: Aggressive buffering enabled (fanout threshold: 50)"

    } elseif {$permuton_value == "max_performance"} {
      # Maximum performance buffering (power trade-off)
      set_app_options -name compile.timing.buffer_replication -value true
      set_app_options -name opt.common.max_fanout -value 30
      set_app_options -name compile.timing.power_optimization -value false
      puts "INFO: Max performance buffering enabled (fanout threshold: 30, power opt disabled)"

    } else {
      # normal - use defaults
      puts "INFO: Normal buffering strategy"
    }
  }

  proc dso_after_buffering_proc {} {
    puts "INFO: Restoring buffering settings to defaults"

    # Reset all buffering variables using FC syntax
    reset_app_options compile.timing.buffer_replication
    reset_app_options opt.common.max_fanout
    reset_app_options compile.timing.power_optimization
  }

}
