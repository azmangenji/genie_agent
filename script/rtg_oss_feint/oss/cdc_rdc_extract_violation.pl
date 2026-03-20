#!/usr/bin/perl
# Universal CDC/RDC extraction - supports both Orion and Arcadia
# Orion usage: perl script.pl <cdc_report.rpt> <rdc_report.rpt> <tile_name>
# Arcadia usage: perl script.pl <cdc_report.rpt> <rdc_report.rpt> <rdc_resetchecks.rpt> <tile_name>

use strict;
use warnings;

# Auto-detect Orion vs Arcadia based on number of arguments
my $is_arcadia = (scalar @ARGV == 4);
my ($cdc_file, $rdc_file, $rdc_checks_file, $tile_name);

if ($is_arcadia) {
    # Arcadia: 4 arguments
    $cdc_file = $ARGV[0];
    $rdc_file = $ARGV[1];
    $rdc_checks_file = $ARGV[2];
    $tile_name = $ARGV[3];
} else {
    # Orion: 3 arguments
    $cdc_file = $ARGV[0];
    $rdc_file = $ARGV[1];
    $tile_name = $ARGV[2];
    $rdc_checks_file = $rdc_file;  # Use same file for Orion
}

die "Usage: $0 <cdc_report.rpt> <rdc_report.rpt> [<rdc_resetchecks.rpt>] <tile_name>\n" unless $cdc_file && $rdc_file && $tile_name;

sub extract_violations {
    my ($file, $report_type) = @_;
    
    open(my $fh, '<', $file) or die "Cannot open $file: $!\n";
    
    my $violations_count = 0;
    my $caution_count = 0;
    my $recording = 0;
    my @buffered_lines;
    my $has_none = 0;
    my $total_violations = 0;
    my $total_inferred = 0;
    my $in_summary_section = 0;
    
    while (my $line = <$fh>) {
        # Look for appropriate summary section
        if ($report_type eq 'CDC' && $line =~ /Clock Group Summary/) {
            $in_summary_section = 1;
        }
        if ($report_type eq 'RDC' && $line =~ /Reset Tree Summary/) {
            $in_summary_section = 1;
        }
        
        if ($line =~ /^Violations?\s*\((\d+)\)/) {
            $total_violations = $1;
        }
        
        # Extract inferred from correct section
        if ($in_summary_section && $line =~ /^\s*2\.\s*Inferred\s*[:\(]\s*\((\d+)\)/) {
            $total_inferred = $1;
            $in_summary_section = 0;
        }
        
        if ($line =~ /Violation/) {
            $violations_count++;
            if ($violations_count == 2) {
                $recording = 1;
                next;
            }
        }
        
        if ($line =~ /Caution/) {
            $caution_count++;
            if ($caution_count == 2 && $recording) {
                last;
            }
        }
        
        if ($recording) {
            push @buffered_lines, $line;
            $has_none = 1 if $line =~ /None/i;
        }
    }
    
    close($fh);
    
    return (\@buffered_lines, $has_none, $total_violations, $total_inferred);
}

sub extract_rdc_resetchecks {
    my ($file) = @_;
    
    open(my $fh, '<', $file) or die "Cannot open $file: $!\n";
    
    my $error_count = 0;
    my $warning_count = 0;
    my $recording = 0;
    my @buffered_lines;
    my $has_none = 0;
    
    while (my $line = <$fh>) {
        if ($line =~ /Error\s*\((\d+)\)/) {
            $error_count++;
            if ($error_count == 2) {
                $recording = 1;
                next;
            }
        }
        
        if ($line =~ /Warning\s*\((\d+)\)/) {
            $warning_count++;
            if ($warning_count == 2 && $recording) {
                last;
            }
        }
        
        if ($recording) {
            push @buffered_lines, $line;
            $has_none = 1 if $line =~ /None/i;
        }
    }
    
    close($fh);
    
    return (\@buffered_lines, $has_none);
}

sub extract_blackbox_unresolved {
    my ($file) = @_;
    
    open(my $fh, '<', $file) or die "Cannot open $file: $!\n";
    
    my $num_blackboxes = 0;
    my $num_unresolved = 0;
    my @blackbox_modules = ();
    my @unresolved_modules = ();
    my $in_blackbox_section = 0;
    my $in_unresolved_section = 0;
    
    while (my $line = <$fh>) {
        if ($line =~ /Number\s+of\s+blackboxes\s*=\s*(\d+)/) {
            $num_blackboxes = $1;
        }
        
        if ($line =~ /Number\s+of\s+Unresolved\s+Modules\s*=\s*(\d+)/) {
            $num_unresolved = $1;
        }
        
        if ($line =~ /^Empty Black Boxes:\s*$/) {
            my $next_line = <$fh>;
            $next_line = <$fh>;
            $in_blackbox_section = 1;
            next;
        }
        
        if ($in_blackbox_section && $line =~ /^(\S+)\s+\d+\s+\//) {
            push @blackbox_modules, $1;
        }
        
        if ($in_blackbox_section && ($line =~ /^\s*$/ || $line =~ /^Detail Design Information/)) {
            $in_blackbox_section = 0;
        }
        
        if ($line =~ /^Unresolved Modules:\s*$/) {
            $in_unresolved_section = 1;
            next;
        }
        
        if ($in_unresolved_section && $line =~ /^(\S+)\s+\d+\s+Unresolved Module/) {
            push @unresolved_modules, $1;
        }
        
        if ($in_unresolved_section && $line =~ /^\s*Definition\s*:/) {
            $in_unresolved_section = 0;
        }
    }
    
    close($fh);
    
    my $blackbox_list = (@blackbox_modules > 0) ? join(" ", @blackbox_modules) : "None";
    my $unresolved_list = (@unresolved_modules > 0) ? join(" ", @unresolved_modules) : "None";
    
    return ($num_blackboxes, $num_unresolved, $blackbox_list, $unresolved_list);
}

# Extract CDC violations and stats
my ($cdc_lines, $cdc_has_none, $cdc_violations, $cdc_inferred) = extract_violations($cdc_file, 'CDC');
my ($cdc_blackboxes, $cdc_unresolved, $cdc_bb_list, $cdc_unres_list) = extract_blackbox_unresolved($cdc_file);

# Extract RDC summary
my ($rdc_lines, $rdc_has_none, $rdc_violations, $rdc_inferred) = extract_violations($rdc_file, 'RDC');

# Extract RDC violation details (Arcadia uses separate file, Orion uses same file)
my ($rdc_detail_lines, $rdc_detail_has_none);
if ($is_arcadia) {
    ($rdc_detail_lines, $rdc_detail_has_none) = extract_rdc_resetchecks($rdc_checks_file);
} else {
    # For Orion, use the same violations from rdc_report.rpt
    $rdc_detail_lines = $rdc_lines;
    $rdc_detail_has_none = $rdc_has_none;
}

# Print CSV summary
print "#table#\n";
print "Types,Tiles,Inferred,Violation,Blackboxes,Unresolved,Logfile\n";
print "CDC,$tile_name,$cdc_inferred,$cdc_violations,$cdc_blackboxes,$cdc_unresolved,$cdc_file\n";
print "RDC,$tile_name,$rdc_inferred,$rdc_violations,N/A,N/A,$rdc_file\n";
print "#table end#\n";

print "\n";
print "#text#\n";
print "Blackbox Modules: $cdc_bb_list\n";
print "Unresolved Modules: $cdc_unres_list\n";

print "\n";

# Print CDC violation details
if (!$cdc_has_none && @$cdc_lines <= 200 && @$cdc_lines > 0) {
    print "=" x 70 . "\n";
    print "CDC $tile_name Violation Details:\n";
    print "=" x 70 . "\n";
    print @$cdc_lines;
    print "\n";
}

# Print RDC violation details
if (!$rdc_detail_has_none && @$rdc_detail_lines <= 200 && @$rdc_detail_lines > 0) {
    print "=" x 70 . "\n";
    print "RDC $tile_name Violation Details:\n";
    print "=" x 70 . "\n";
    print @$rdc_detail_lines;
}

# Exit with error if any violations found
exit ((!$cdc_has_none && @$cdc_lines > 0) || (!$rdc_detail_has_none && @$rdc_detail_lines > 0)) ? 1 : 0;
