#!/bin/tcl
################################################################################
# Find FC App_Options - Search for correct naming
# Usage: fc_shell> source find_appvars.tcl
################################################################################

puts ""
puts "==============================================================================="
puts "SEARCHING FOR FC APP_OPTIONS"
puts "==============================================================================="
puts ""

puts "=== 1. TIMING EFFORT OPTIONS ==="
report_app_options *effort*

puts ""
puts "=== 2. RETIMING OPTIONS ==="
report_app_options *retim*

puts ""
puts "=== 3. REPLICATION OPTIONS ==="
report_app_options *replic*

puts ""
puts "=== 4. TNS OPTIONS ==="
report_app_options *tns*

puts ""
puts "=== 5. BUFFER OPTIONS ==="
report_app_options *buffer*

puts ""
puts "=== 6. RESTRUCTURE OPTIONS ==="
report_app_options *restructur*

puts ""
puts "=== 7. ALL COMPILE OPTIONS ==="
report_app_options compile.*

puts ""
puts "==============================================================================="
puts "END OF SEARCH"
puts "==============================================================================="
