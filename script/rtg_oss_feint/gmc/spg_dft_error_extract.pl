#!/usr/bin/perl
# Enhanced SpyGlass DFT Error Extraction with Statistics
# Usage: perl spg_dft_error_extract.pl <moresimple.rpt> <filter_file.txt> <tile_name> [output_dir] [ip_name]
#
# Outputs:
#   - Statistics to STDOUT (for spec file)
#   - Filtered violations to <output_dir>/spg_dft_filtered_<tile_name>.txt
#
# Filter file format:
#   [general]   - Patterns that apply to ALL projects
#   [<ip_name>] - Patterns that only apply to specific IP (e.g., [umc9_3])

use strict;
use warnings;

my $report_file = $ARGV[0] || die "Usage: $0 <moresimple.rpt> <filter_file.txt> <tile_name> [output_dir] [ip_name]\n";
my $filter_file = $ARGV[1] || die "Usage: $0 <moresimple.rpt> <filter_file.txt> <tile_name> [output_dir] [ip_name]\n";
my $tile_name = $ARGV[2] || "unknown_tile";
my $output_dir = $ARGV[3] || ".";
my $ip_name = $ARGV[4] || "";

# Read filters as regex patterns with section support
# Sections: [general] applies to all, [ip_name] applies only to matching IP
open(my $ffh, '<', $filter_file) or die "Could not open filter file '$filter_file' $!";
my @patterns;
my @pattern_texts;
my $current_section = "general";  # Default section

while (my $line = <$ffh>) {
    chomp $line;
    next if $line =~ /^\s*$/;     # Skip empty lines
    next if $line =~ /^\s*#/;     # Skip comments

    # Check for section header [section_name]
    if ($line =~ /^\s*\[(\w+)\]\s*$/) {
        $current_section = lc($1);
        next;
    }

    # Only include pattern if:
    # 1. It's in [general] section, OR
    # 2. It's in a section matching the ip_name
    my $ip_lower = lc($ip_name);
    if ($current_section eq "general" || $current_section eq $ip_lower) {
        push @patterns, qr/$line/;    # Compile as regex
        push @pattern_texts, "[$current_section] $line";  # Store with section info
    }
}
close($ffh);

# Counters
my $total_errors = 0;
my $filtered_errors = 0;
my $unfiltered_errors = 0;
my @unfiltered_lines = ();
my @filtered_lines = ();
my @filtered_patterns = ();  # Track which pattern matched each filtered line

# Open report file
open(my $rfh, '<', $report_file) or die "Could not open report file '$report_file' $!";

LINE: while (my $line = <$rfh>) {
    # Match Error/ERROR in severity column, not in text like "TransparentErrors"
    next unless $line =~ /\s+(Error|ERROR)\s+/;

    $total_errors++;

    # Check if line matches any filter pattern
    for (my $i = 0; $i < scalar(@patterns); $i++) {
        if ($line =~ $patterns[$i]) {
            $filtered_errors++;
            push @filtered_lines, $line;
            push @filtered_patterns, $pattern_texts[$i];
            next LINE;  # Skip line if it matches any pattern
        }
    }

    # If we get here, error was not filtered
    $unfiltered_errors++;
    push @unfiltered_lines, $line;
}

close($rfh);

# Write filtered violations to file
my $filtered_file = "$output_dir/spg_dft_filtered_$tile_name.txt";
open(my $ofh, '>', $filtered_file) or warn "Could not open output file '$filtered_file' $!";
if ($ofh) {
    print $ofh "=" x 70 . "\n";
    print $ofh "SpyGlass DFT Filtered Violations Report\n";
    print $ofh "=" x 70 . "\n";
    print $ofh "Tile: $tile_name\n";
    print $ofh "Report: $report_file\n";
    print $ofh "Filter: $filter_file\n";
    print $ofh "Total Filtered: $filtered_errors\n";
    print $ofh "=" x 70 . "\n\n";

    for (my $i = 0; $i < scalar(@filtered_lines); $i++) {
        my $num = $i + 1;
        print $ofh "[$num] Pattern: $filtered_patterns[$i]\n";
        print $ofh "    $filtered_lines[$i]";
        print $ofh "\n";
    }
    close($ofh);
}

# Print CSV statistics
print "#table#\n";
print "Tiles,Total_Errors,Filtered_Errors(RSMU/DFT),Unfiltered_Errors(RSMU/DFT),Filtered_List,Logfile\n";
print "$tile_name,$total_errors,$filtered_errors,$unfiltered_errors,$filtered_file,$report_file\n";
print "#table end#\n";

print "#text#\n";
# Print unfiltered errors
if (@unfiltered_lines > 0) {
    print "\n";
    print "=" x 70 . "\n";
    print "Unfiltered Error Details:\n";
    print "=" x 70 . "\n";
    print @unfiltered_lines;
}

# Exit with error if unfiltered errors found
exit ($unfiltered_errors > 0) ? 1 : 0;
