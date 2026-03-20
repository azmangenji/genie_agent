#!/usr/bin/perl
# Universal Lint Extraction - Auto-detects LEDA or SpyGlass
# Usage: perl lint_universal_extract.pl <lint_report> <tile_name>

use strict;
use warnings;

my $input_file = $ARGV[0] || die "Usage: $0 <lint_report> <tile_name>\n";
my $tile_name = $ARGV[1] || "unknown_tile";

# Auto-detect file type
my $is_leda = ($input_file =~ /leda_waiver/i);
my $is_spyglass = ($input_file =~ /spyglass|vc_spyglass/i);

die "Cannot determine lint tool type from filename: $input_file\n" unless ($is_leda || $is_spyglass);

if ($is_leda) {
    extract_leda_waivers($input_file, $tile_name);
} else {
    extract_spyglass_lint($input_file, $tile_name);
}

sub extract_leda_waivers {
    my ($file, $tile) = @_;
    
    open(my $fh, '<', $file) or die "Cannot open $file: $!\n";
    
    my $in_unwaived = 0;
    my $in_unused = 0;
    my $in_waived = 0;
    my $unwaived_count = 0;
    my $unused_count = 0;
    my $waived_count = 0;
    my $filtered_count = 0;
    my @unwaived_details = ();
    
    while (my $line = <$fh>) {
        if ($line =~ /^Unwaived\s*$/) {
            $in_unwaived = 1;
            $in_unused = 0;
            $in_waived = 0;
            next;
        }
        
        if ($line =~ /^Unused Waivers\s*$/) {
            $in_unwaived = 0;
            $in_unused = 1;
            $in_waived = 0;
            next;
        }
        
        if ($line =~ /^Waived\s*$/) {
            $in_unwaived = 0;
            $in_unused = 0;
            $in_waived = 1;
            next;
        }
        
        # Match lines with pipe-separated fields containing a line number (digits) or wildcards
        # Pattern: | digits | for actual violations, | -------- | or | .* | for regex-based waivers
        # For unwaived/waived: require digits (actual line numbers)
        # For unused: accept digits, dashes, or .* (regex waivers have no line numbers)

        my $has_digits = ($line =~ /\|\s+\d+\s+\|/);
        my $has_wildcard = ($line =~ /\|\s+(-{2,}|\.\*)\s+\|/);

        if ($has_digits || ($in_unused && $has_wildcard)) {
            if ($in_unwaived && $has_digits) {
                $unwaived_count++;
                my @fields = split(/\s*\|\s*/, $line);
                # LEDA has 6 fields, but code may contain | characters
                # Extract from right: msg, line, filename, type, error, then rest is code
                if (@fields >= 6) {
                    my $msg = pop @fields;  # Last field
                    my $line_num = pop @fields;  # 5th field
                    my $filename = pop @fields;  # 4th field
                    my $type = pop @fields;  # 3rd field
                    my $error = pop @fields;  # 2nd field
                    my $code = join(" | ", @fields);  # Everything else is code

                    # Filter out rsmu and dft files
                    if ($filename =~ /rsmu|dft/i) {
                        $filtered_count++;
                        next;
                    }

                    push @unwaived_details, {
                        code => $code || '',
                        error => $error || '',
                        type => $type || '',
                        filename => $filename || '',
                        line => $line_num || '',
                        msg => $msg || ''
                    };
                }
            } elsif ($in_unused) {
                $unused_count++;
            } elsif ($in_waived && $has_digits) {
                $waived_count++;
            }
        }
    }
    
    close($fh);
    
    # Get unresolved count
    my $lint_dir = $file;
    $lint_dir =~ s/\/[^\/]+$//;
    my $unresolved_count = count_unresolved_modules($lint_dir);
    
    # Print CSV summary
    my $total = $unwaived_count + $unused_count + $waived_count;
    my $unfiltered_count = $unwaived_count - $filtered_count;
    print "#table#\n";
    print "Tiles,Unwaived,Filtered_RSMU/DFT,Unfiltered_RSMU/DFT,Unused_Waivers,Waived,Total,Unresolved_Modules,Logfile\n";
    print "$tile,$unwaived_count,$filtered_count,$unfiltered_count,$unused_count,$waived_count,$total,$unresolved_count,$file\n";
    print "#table end#\n";

    # Extract unresolved modules first
    extract_unresolved_modules($lint_dir, $tile);
    
    # Print unwaived violation details
    if (@unwaived_details > 0) {
        print "\n";
        print "=" x 70 . "\n";
        print "LEDA Unwaived Violation Details for $tile:\n";
        print "=" x 70 . "\n";
        print "#table#\n";
        print "Code,Error,Type,Filename,Line,Message\n";
        foreach my $detail (@unwaived_details) {
            # Remove commas from fields to prevent CSV column issues
            my $code = $detail->{code};
            my $error = $detail->{error};
            my $type = $detail->{type};
            my $filename = $detail->{filename};
            my $line = $detail->{line};
            my $msg = $detail->{msg};
            
            # Remove commas but keep the content
            $code =~ s/,/ /g;
            $msg =~ s/,/ /g;
            
            print "$code,$error,$type,$filename,$line,$msg\n";
        }
        print "#table end#\n";

    }
    
    exit ($unwaived_count > 0) ? 1 : 0;
}

sub extract_spyglass_lint {
    my ($file, $tile) = @_;
    
    open my $fh, '<', $file or die "Could not open file '$file': $!";
    
    my $total_errors = 0;
    my $total_waived = 0;
    my $total_count = 0;
    my $extraction_state = 0;
    my $separator_pattern = qr/^-{5,}$/;
    my @violation_details = ();
    
    while (my $line = <$fh>) {
        if ($line =~ /^\s*Total\s+\d+\s+(\d+)\s+\d+\s+\d+\s+(\d+)/) {
            $total_errors = $1;
            $total_waived = $2;
        }
        
        if ($extraction_state == 0) {
            if ($line =~ /Total/i) {
                $total_count++;
                if ($total_count == 2) {
                    $extraction_state = 1;
                }
            }
            next;
        }
        
        if ($extraction_state == 1) {
            chomp $line;
            my $cleaned_line = $line;
            $cleaned_line =~ s/^\s+|\s+$//g;
            
            if ($cleaned_line =~ $separator_pattern) {
                $extraction_state = 2;
            }
            next;
        }
        
        elsif ($extraction_state == 2) {
            chomp $line;
            push @violation_details, "$line\n";
        }
    }
    
    close $fh;
    
    # Get unresolved count
    my $lint_dir = $file;
    $lint_dir =~ s/\/[^\/]+$//;
    my $unresolved_count = count_unresolved_modules($lint_dir);
    
    # Print CSV summary
    print "#table#\n";
    print "Tiles,Errors,Waived,Unresolved_Modules,Logfile\n";
    print "$tile,$total_errors,$total_waived,$unresolved_count,$file\n";
    print "#table end#\n";

    # Extract unresolved modules first
    extract_unresolved_modules($lint_dir, $tile);
    
    # Print violation details
    if (@violation_details > 0) {
        print "\n";
        print "=" x 70 . "\n";
        print "SpyGlass Lint Violation Details for $tile:\n";
        print "=" x 70 . "\n";
        print @violation_details;
    }
    
    exit ($total_errors > 0) ? 1 : 0;
}

sub count_unresolved_modules {
    my ($lint_dir) = @_;
    
    my $unresolved_file = "$lint_dir/List_unresolved_refs.txt";
    return 0 unless (-e $unresolved_file);
    
    open(my $fh, '<', $unresolved_file) or return 0;
    
    my %modules;
    while (my $line = <$fh>) {
        if ($line =~ /BB Module:\s*(\S+)/) {
            $modules{$1}++;
        }
    }
    close($fh);
    
    # Count unique (grouping memory as 1)
    my (@std_cells, @memory, @rtl);
    foreach my $mod (keys %modules) {
        if ($mod =~ /^trfp/i) {
            push @memory, $mod;
        } elsif ($mod =~ /BWP|AMDBWP|LVT$/i) {
            push @std_cells, $mod;
        } else {
            push @rtl, $mod;
        }
    }
    
    return scalar(@std_cells) + scalar(@rtl) + (@memory > 0 ? 1 : 0);
}

sub extract_unresolved_modules {
    my ($lint_dir, $tile) = @_;
    
    my $unresolved_file = "$lint_dir/List_unresolved_refs.txt";
    return unless (-e $unresolved_file);
    
    open(my $fh, '<', $unresolved_file) or return;
    
    my %modules;
    while (my $line = <$fh>) {
        if ($line =~ /BB Module:\s*(\S+)/) {
            $modules{$1}++;
        }
    }
    close($fh);
    
    return unless %modules;
    
    # Separate standard cells and memory modules
    my (@std_cells, @memory, @rtl);
    foreach my $mod (sort keys %modules) {
        if ($mod =~ /^trfp/i) {
            push @memory, $mod;
        } elsif ($mod =~ /BWP|AMDBWP|LVT$/i) {
            push @std_cells, $mod;
        } else {
            push @rtl, $mod;
        }
    }
    
    # Group memory modules
    my $memory_str = "";
    if (@memory > 0) {
        # Find common prefix
        my $prefix = "";
        if ($memory[0] =~ /^(trfp[^0-9]+)/) {
            $prefix = $1;
        }
        $memory_str = $prefix . "*(" . scalar(@memory) . ")";
    }
    
    # Build module list
    my @module_list = (@std_cells, @rtl);
    push @module_list, $memory_str if $memory_str;
    
    print "\n#text#\n";
    print "=" x 70 . "\n";
    print "Lint Unresolved Modules for $tile:\n";
    print "=" x 70 . "\n";
    print "Unresolved Modules: " . join(" ", @module_list) . "\n";
}
