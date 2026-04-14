############################################################
# dso_timing_drc_priority Permuton Procedures
# Purpose: Prioritize timing optimization over DRC fixing
# Updated: 2026-01-26 - Fixed FC syntax (dot notation)
############################################################

namespace eval ::DSO::PERMUTONS {

  proc dso_before_timing_drc_proc {permuton_name permuton_value} {
    puts "INFO: Setting timing/DRC prioritization to $permuton_value"

    if {$permuton_value == "timing_first"} {
      # Prioritize timing, fix DRCs afterward using FC syntax
      set_app_options -name compile.timing.prioritize_tns -value true
      set_app_options -name route.common.post_route_eco_timing_effort -value high
      puts "INFO: Timing prioritized over DRC fixing"

    } elseif {$permuton_value == "timing_only"} {
      # Focus only on timing, minimize DRC fixing
      set_app_options -name compile.timing.prioritize_tns -value true
      set_app_options -name compile.timing.prioritize_wns -value true
      set_app_options -name route.common.post_route_eco_timing_effort -value ultra
      puts "INFO: Timing-only mode - DRC fixing minimized"

    } else {
      # balanced - default behavior
      puts "INFO: Balanced timing/DRC optimization"
    }
  }

  proc dso_after_timing_drc_proc {} {
    puts "INFO: Restoring timing/DRC prioritization to default"

    # Reset to default using FC syntax
    reset_app_options compile.timing.prioritize_tns
    reset_app_options compile.timing.prioritize_wns
    reset_app_options route.common.post_route_eco_timing_effort
  }

}
