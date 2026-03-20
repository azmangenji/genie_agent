#!/usr/bin/perl
# Filter CDC violations by custom patterns
# Usage: perl filter_cdc_violations.pl <cdc_report.rpt> [filter_pattern]
# Default filter: rsmu|dft
# Custom filter: perl filter_cdc_violations.pl report.rpt "rsmu|dft|no_sync"

use strict;
use warnings;

my $report_file = $ARGV[0] || die "Usage: $0 <cdc_report.rpt> [filter_pattern]\n";
my $filter_pattern = $ARGV[1] || "rsmu|dft";  # Default filter

print "Using filter pattern: $filter_pattern\n";

open(my $fh, '<', $report_file) or die "Cannot open $report_file: $!\n";

my $current_start = '';
my $start_has_rsmu_dft = 0;
my $total_violations = 0;
my $filtered_violations = 0;
my $unfiltered_violations = 0;
my $in_violations_section = 0;

while (my $line = <$fh>) {
    # Track if we're in the Violations section (detail header)
    # Handle both "Violations" (CDC) and "Violation" (RDC)
    if ($line =~ /^Violations?$/) {
        $in_violations_section = 1;
        next;
    }
    # Exit Violations section when we hit Cautions/Caution section
    if ($in_violations_section && $line =~ /^Cautions?$/) {
        $in_violations_section = 0;
    }
    
    # Only process lines in Violations section
    next unless $in_violations_section;
    
    # Detect start line (for start/end format violations)
    if ($line =~ /: start :/) {
        $current_start = $line;
        # Check if start matches filter pattern
        if ($line =~ /$filter_pattern/i) {
            $start_has_rsmu_dft = 1;
        } else {
            $start_has_rsmu_dft = 0;
        }
    }
    # Detect end line with ID (for start/end format violations)
    elsif ($line =~ /: end :.*\(ID:/) {
        $total_violations++;
        
        # Filter logic for start/end format:
        # 1. If start matches filter -> filter (all ends are filtered)
        # 2. If start doesn't match -> check if this end matches filter
        if ($start_has_rsmu_dft) {
            # Start matches filter -> filter this violation
            $filtered_violations++;
        } elsif ($line =~ /$filter_pattern/i) {
            # Start doesn't match, but this end does -> filter
            $filtered_violations++;
        } else {
            # Neither start nor end matches filter -> keep (unfiltered)
            $unfiltered_violations++;
        }
    }
    # Detect direct violation (no start/end format) - has ID but no ": end :"
    elsif ($line =~ /\(ID:/ && $line !~ /: end :/) {
        $total_violations++;
        
        # Filter logic for direct violations:
        # Check if the signal path matches filter pattern
        if ($line =~ /$filter_pattern/i) {
            $filtered_violations++;
        } else {
            $unfiltered_violations++;
        }
    }
}

close($fh);

# Print results
print "CDC Violation Filter Results\n";
print "=" x 50 . "\n";
print "Total Violations:      $total_violations\n";
print "Filtered (rsmu/dft):   $filtered_violations\n";
print "Unfiltered (clean):    $unfiltered_violations\n";
print "=" x 50 . "\n";
