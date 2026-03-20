#!/usr/bin/perl
#!/tool/pandora/bin/perl
#
# $Id: k12_summarize_timing_report_xv_all_groups.pl,v 1.7 2013-06-14 11:47:14-07 ikariapp Exp $
#
use strict;
use Getopt::Long;


####################
# Constants
####################

# gf14 (and prior)
# hdinxss\d+(u[hrls]c?)/Z
# hdbfxss\d+(u[hrls]c?)/Z

# tsmc7
# HDB([LS]VT|ULT)(08|11)_INV_\d+/X
# HDB([LS]VT|ULT)(08|11)_BUF_\d+/X

# gf7lp
# SC6T(\d+G)?_INVX\d+(_[A-Z])_DD[L](16|18)/Z
# SC6T(\d+G)?_BUFX\d+(_[A-Z])_DD[L](16|18)/Z
#use constant OUTPUT_PINS_RE => qr!/(Q|ZB|ZN)\s+\([^n]\w+!;
use constant OUTPUT_PINS_RE => qr!/(?:Z|ZN)\b\s+\([^n]\w+!;
use constant BUF_AND_INV_REGEX => '(inx|bfx|INV|BUF)';
#use constant BUF_REGEX => '(BUF)';
#use constant INV_REGEX => '(inx|bfx|INV|BUF)';
# Apply these to the extracted cell name (e.g., the token inside parentheses)
#use constant INV_REGEX          => qr/^(?:INV\w*)$/i;   # e.g., INVD2BWP136P5M156H3P48CPDLVT
#use constant BUF_REGEX          => qr/^(?:BUFF\w*)$/i;  # e.g., BUFFSR2SKFD10BWP136P5M156H3P48CPDLVT
#use constant BUF_REGEX => '(hdbfx|HDB([LS]VT|ULT)(08|11)_BUF_|SC6T(\d+G)?_BUFX|HDN6B([LS]VT|ULT)(08|11)_BUF_)';
use constant BUF_REGEX => '(hdbfx|BUFF*)';
use constant INV_REGEX => '(hdinx|INV*)';

#my @inverter_ids = qw(hdinx _INV_ _INVX);				# What gets marked in an inverter pair
my @orders = (" ", "K", "M", "G", "T", "P", "E");	# For displaying TNS more compactly
my $trans_threshold = .050;				# Anything higher get's marked with a ^
my $incr_threshold = .040;				# Anything higher get's marked with a ^

my @sort_list = qw(slack real_levels);

my $default_period = .300;
my @default_perc_list = (50, 20, 10, 5, 2);

$| = 1; # autoflush

# paullin : start
my $PERIOD;
my $hasRlmName = '';
my $range;
my $input_file;
my $blms_file;
my $sort_levels;
my $all_groups;
my $uniquify;
my $add_groups;
my $help;
my $logic_dom;
my $timescale;
GetOptions ( 
               "in=s" => \$input_file,
			   "period=s" => \$PERIOD,
               'hasRlmName!' => \$hasRlmName,
               "range=s" => \$range,
               "blms=s" => \$blms_file,
			   'level_sort' => \$sort_levels,
			   "all_groups=s" => \$all_groups,
			   "uniquify=s" => \$uniquify,
			   "add_groups=s" => \$add_groups,
			   "logic_dom!" => \$logic_dom,
			   "timescale!" => \$timescale,
			   'help|h' => \$help,
           );

if ($help) {
	print "\n";
	print "Summarize timing report:\n";
	print "	-in FILE\n";
	print "		The .rpt file to use, e.g. CCLK_max.rpt.gz\n";
	print "	-period NUM\n";
	print "		Modify the period to NUM. (Default = $default_period)\n";
	print "	-hasRlmName\n";
	print "		Ensure correct hierarchy being parsed out for rlm.sum\n";
	print "	-range LIST\n";
	print "		Change what LIST_OF_PERIOD_PERC gets assigned to. (Default = @default_perc_list)\n";
	print "	-blms LIST\n";
	print "		Split reports into BLM's according to given comma separated list, " .
				"e.g. '-blms lsadr,lsldq,lstlb,lsmab,lssqi,lssta,lsseg'\n";
	print "	-level_sort\n";
	print "		Create additional reports with paths sorted by real logic levels.\n";
	print "	-all_groups DIR\n";
	print "		Accumulate all the *_max.rpt(.gz) files within DIR of the groups in the qor.rpt into one summary report.\n";
	print "	-uniquify FILE\n";
	print "		Add additional s//'s for uniquifying start/endpoints.\n";
	print "			Example file (bpde_uniquify.pl):\n";
	print "				s/desdcdect\\d/desdcdect\#/;\n";
	print "				s/desdcdist\\d/desdcdist\#/;\n";
	print "				s/desdcsad\\d/desdcsad\#/;\n";
	print "				s/desdcuopqt\\d/desdcuopqt\#/;\n";
	print "	-add_groups LIST\n";
	print "		Specify a comma seperated list of groups to include in additon to the file specified by --in in the summary rpt.\n";
	print "		e.g. --in CCLK_max.rpt.gz --add_groups in2reg,reg2out,in2out\n";
	print " -logic_dom\n";
	print "		Only print out paths with levels > 20 and buffer/inverters < 4\n";
	print " -timescale\n";
	print "		Print out timing numbers in picoseconds instead of nanoseconds\n";
	print "	-h, --help\n";
	print "		Print this message.\n";
	print "\n";
	exit;
}
my $flag = 0;
if (!$PERIOD) { $PERIOD = $default_period;}
my @LIST_OF_PERIOD_PERC;
if ($range) {
	@LIST_OF_PERIOD_PERC = split ",", $range;
} else {
	@LIST_OF_PERIOD_PERC = @default_perc_list;
}
my $MINSLACK = 9999;

unless (defined $input_file || defined $all_groups) {
	print "Please give input report file or specify all_groups.\n";
	print "--help for command usage.\n";
	exit;
}

if (defined $all_groups) {
	$all_groups .= "/" if $all_groups =~ m/[^\/]$/;
	$input_file = "${all_groups}all_groups";
}

my $setup_input = $input_file;
$setup_input =~ s/[^\/]+$//;	# Getting the location of the rpts dir

my @qor_file;
my @qor_rpt;
@qor_file = (glob("${setup_input}*qor.rpt*"));
if($#qor_file < 0) {
	print "Can't find qor.rpt(.gz) in $setup_input\n";
	exit;
} elsif ($qor_file[0] =~ m/.*qor.rpt.gz$/) {
	@qor_rpt = `zcat $qor_file[0]`;
} elsif ($qor_file[0] =~ m/.*qor.rpt$/) {
	@qor_rpt = `cat $qor_file[0]`;
}

#print "QOR RPT $qor_file[0]";
#if (-e "${setup_input}qor.rpt") {
#	@qor_rpt = `cat ${setup_input}qor.rpt`;
#} elsif (-e "${setup_input}qor.rpt.gz") {
#	@qor_rpt = `zcat ${setup_input}qor.rpt.gz`;
#} else {
#	print "Can't find qor.rpt(.gz) in $setup_input\n";
#	exit;
#}

my %max_rpt_grps;
foreach (@qor_rpt) {
	#if (m/Timing Path Group '(\w+)'/) {
	if (/Timing Path Group '\*?\*?(\w+)\*?\*?'/){
		$max_rpt_grps{$1} = 1;
		#print "Max $1\n";
	}
}

my @input_files;
if (defined $all_groups) {
	
	if (!-d $all_groups) {
		print "Argument to all_groups must be the dir containing the *_max.rpt files.\n";
		exit;
	}
	
	foreach my $max_rpt (keys %max_rpt_grps) {
		my @rpt_files = (glob("${all_groups}*${max_rpt}*_max.rpt*"));
		#print "RPT @rpt_files \n";
		if($#rpt_files < 0) {
			print "Can't find ${max_rpt}_max.rpt(.gz) in $all_groups\n";
			exit unless $max_rpt eq "in2reg";
		} else {
			foreach my $rpt_file (@rpt_files) {
				my $search_str = quotemeta("${all_groups}")."(.+)".quotemeta("${max_rpt}")."_max.rpt.*";
				#print "Search $search_str\n";
				if ($rpt_file =~ m/$search_str.*/) {
					if ($1 eq "FINAL_") {
						push @input_files, $rpt_file;
					}
				} else {
					push @input_files, $rpt_file;
				}
			}
		}	
#		if (-e "${all_groups}${max_rpt}_max.rpt") {
#			push @input_files, "${all_groups}${max_rpt}_max.rpt";
#		} elsif (-e "${all_groups}${max_rpt}_max.rpt.gz") {
#			push @input_files, "${all_groups}${max_rpt}_max.rpt.gz";
#		} else {
#			print "Can't find ${max_rpt}_max.rpt(.gz) in $all_groups\n";
#			exit unless $max_rpt eq "in2reg";
#		}
	}
	
#	push @input_files, glob("${all_groups}*_max.rpt");
#	push @input_files, glob("${all_groups}*_max.rpt.gz");
	
} elsif (defined $input_file) {
	push @input_files, $input_file;
}

if (defined $add_groups) {
	foreach my $grp (split ",", $add_groups) {
		if (!exists $max_rpt_grps{$grp}) {
			print "Can't find $grp in qor.rpt, skipping.\n";
		} elsif ((!-e "${setup_input}${grp}_max.rpt") && (!-e "${setup_input}${grp}_max.rpt.gz")) {
			print "Can't find ${setup_input}${grp}_max.rpt(.gz), skipping.\n";
		} else {
			push @input_files, "${setup_input}${grp}_max.rpt" if -e "${setup_input}${grp}_max.rpt";
			push @input_files, "${setup_input}${grp}_max.rpt.gz" if -e "${setup_input}${grp}_max.rpt.gz";
		}
	}
	my $i = 1;
	$i++ while (-e "${setup_input}custom_grps_${i}.sum.sort_slack.endpts");
	$input_file = "${setup_input}custom_grps_${i}";
}

if (defined $uniquify) {
	if (-e "$uniquify") {
		$uniquify = `cat $uniquify`;
	} else {
		print "Can't find uniquify file $uniquify\n";
		exit;
	}
}

# Pull in data from setup_start(end)pts files
print "Parsing data ...\n";

my @setup_endpoints;
my %setup_endpoints_hash;
my @setup_startpoints;
my %setup_startpoints_hash;
my @setup_files = glob("${setup_input}*setup_endpoints*");
foreach my $sfile (@setup_files) {
	#print "sfile $sfile\n";
	my $scen = "none";
	my $search_str = quotemeta("$setup_input")."([A-Za-z_]+)setup.+";
	if ($sfile =~ m/$search_str/) { #DG case
		next if ($1 ne "FINAL_");
	} else { #targets that can have MCMM enabled
		if ($sfile =~ m/setup_endpoints.+(typrc.+)\.rpt.*/) {
			$scen = $1;
			$flag = 1;
		}
		elsif ($sfile =~ m/setup_endpoints.+(FuncTT.+)\.rpt.*/)
		{
			$scen = $1;
			$flag = 2;
			#print "$scen\n";
		}
		elsif ($sfile =~ m/FINAL_+(setup.+)\.rpt.*/)
		{
			$scen = $1;
			print "$scen\n";
			$flag = 3;
		}
	}
	my $cat_cmd = $sfile =~ /\.gz$/ ? "zcat" : "cat";
	open INPUT, "$cat_cmd $sfile |";
	print "Parsing $sfile\r";
	# Extract fan in and worst next slack from the rpt
	foreach (<INPUT>) {
		if (m/^([\w\][\/]+)\/([\S]+)\s+\(\w+\)\s+-?\d+\.\d+\s+(\d+)\s+(\S+)/) {
			$setup_endpoints_hash{fan_in}{$1}{$2}{$scen} = $3;
			$setup_endpoints_hash{next_slack}{$1}{$2}{$scen} = $4;
		}
	}
	print "Parsed $sfile \n";
	close INPUT;
}
@setup_files = glob("${setup_input}*setup_startpoints*");
foreach my $sfile (@setup_files) {
	my $scen = "none";
	#print "$sfile\n";
	my $search_str = quotemeta("$setup_input")."([A-Za-z_]+)setup.+";
	if ($sfile =~ m/$search_str/) { #DG case
		next if ($1 ne "FINAL_");
	} else { #targets that can have MCMM enabled
		#print "$1\n";
		if ($sfile =~ m/setup_startpoints.+(typrc.+)\.rpt.*/) {
			$scen = $1;
			#print "$scen\n";
			$flag = 1;
		}
		elsif ($sfile =~ m/setup_startpoints.+(FuncTT.+)\.rpt.*/)
		{
			$scen = $1;
			#print "$scen\n";
			$flag = 2;
		}
		elsif ($sfile =~ m/setup_startpoints.+\.rpt.*/)
		{
			$scen = $1;
			#print "$scen\n";
			$flag = 3;
		}
	}
	my $cat_cmd = $sfile =~ /\.gz$/ ? "zcat" : "cat";
	open INPUT, "$cat_cmd $sfile |";
	print "Parsing $sfile\r";
	# Extract fan in and worst next slack from the rpt
	foreach (<INPUT>) {
		if (m/^([\w\][\/]+)\/([\S]+)\s+\(\w+\)\s+-?\d+\.\d+\s+(\d+)\s+(\S+)/) {
			$setup_startpoints_hash{fan_out}{$1}{$2}{$scen} = $3;
			$setup_startpoints_hash{prev_slack}{$1}{$2}{$scen} = $4;
		}
	}
	print "Parsed $sfile \n";
	close INPUT;
}

my %nets; # for finding slow edge rate nets

my @blms = ".*"; # default matching any blm
if (defined $blms_file) {
	@blms = split ",",  $blms_file; 
}

my $startpt_str = "Startpoint";
my $endpt_str = "Endpoint";

# paullin: start
# variable declaration
my %rlmCount;
my %TotalCount;
# paullin: end

# Read in clock gating mapping file if exists
my $clk_gating_map = "";
if ( -e "cg_sinks.rpt" ) {
	$clk_gating_map = `cat cg_sinks.rpt`;
}

my %paths_hash = ();
my %groups_hash = ();

my $in_path = 0;
my $tns = 0;

my $cur_path;

my %key_hash;
my $i = 1;
my $total_files = scalar @input_files;
my $num_length = length $total_files;
foreach my $file (@input_files) {
	
	# check to see if it's a gzip or a regular file
	my $cat_cmd = $file =~ /\.gz$/ ? "zcat" : "cat";
	
	if (!-e $file) {
		die "File $file not found.\n";
	}
	
	open INPUT, "$cat_cmd $file |";
	
	printf "Parsing file $file (%${num_length}d/%d)\r", $i++, $total_files;
	
	# First loop through all the timing paths and store in hash with endpoint as key.
	foreach my $cur_line (<INPUT>) {
		if ( ! $in_path ) {
			if ( $cur_line =~ /Startpoint:/ ) {
				$in_path = 1;
				my $startpt = "NA";
				my $endpt   = "NA";
				my $slack   = 0.0;
				$cur_path = $cur_line;
			}
		} else {
			$cur_path .= $cur_line;
			
	#		if ( $cur_line =~ /slack \(MET\)/ ) {
	#			$in_path = 0;
	#		}
	
			if ( $cur_line =~ /slack \((?:VIOLATED|MET).*?\)\s+.*\s([-0-9.]+)\s*$/ ) {
				$in_path = 0;
				my $slack = $1;
				#print "$slack \t"; 
				next if ( $slack > $MINSLACK );
				$tns += $slack;
				my @cur_path_list = split /\n/, $cur_path;
	
				my @tmp_list = grep /Startpoint:/, @cur_path_list;
				my $startpt = $tmp_list[0];
				$startpt =~ s/$/ /; # add space to end so the next line works
				$startpt =~ m/Startpoint:\s+([^\s]+)/;
				$startpt = $1;
				#print "$startpt \t";	

				@tmp_list = grep /Endpoint:/, @cur_path_list;
				my $endpt = $tmp_list[0];
				$endpt =~ s/$/ /; # add space to end so the next line works
				$endpt =~ m/Endpoint:\s+([^\s]+)/;
				$endpt = $1;
				#print "$endpt \t";

				
				@tmp_list = grep /Path Group:/, @cur_path_list;
				my $group = $tmp_list[0];
				$group =~ m/Path Group:\s+(.+)\s*$/;
				$group = $1;
				#print "$group \t";
				
				##added 10/9/12

				@tmp_list = grep /Scenario:/, @cur_path_list;
				my $scenario = $tmp_list[0];
#				if ($scenario =~ m/Scenario:\s+(.+)\s*$/){
				if (defined ($scenario)){
					$scenario  =~ m/Scenario:\s+(.+)\s*$/;
					$scenario = $1;
				}
				else{
					$scenario = "";
				}
				#$endpt .= "-case".$scenario;
				#print "$scenario \n";
				my $fake_group = $group;
				$fake_group = "all_groups" if defined $all_groups or defined $add_groups;
				
				#@tmp_list = grep /\w+\/[XZ] \(\w+\)/, @cur_path_list;
				#@tmp_list = grep /\w+\/[ZA] \(\w+\)/, @cur_path_list;
                #perl -ne 'print if m!/([ZQXY][NB]?|ZB|ZN)\s+\([^n]\w+!' tmp.rpt
# ---------------------------------------------
# decide which rows mark ONE logic level
# ---------------------------------------------
#@tmp_list = grep OUTPUT_PINS_RE, @cur_path_list;   # <<<<<<  NEW / REPLACED LINE
@tmp_list = grep { /\/(?:ZN|Z)\b\s+\([^n]\w+/ && !/\(net\)/ && !/hdck/i } @cur_path_list;
                 
	            #@tmp_list = grep !/.*hdck.*/, @tmp_list;
				my $levels = @tmp_list;
				my @bfx_cells_list = grep $_ =~ BUF_AND_INV_REGEX, @tmp_list;
				my $bfx_cells = @bfx_cells_list;
				
				my $startpt_regex = make_regex($startpt);	# To find the start and endpoints with regular expressions
				my $endpt_regex = make_regex($endpt);
				my $temp = $cur_path;
				my $start_pin = "";
				my $end_pin = "";
				# Find the last listing for the startpt and listing for the endpt before "data arrival time" and record their pin names
				while ($temp =~ m/$startpt_regex\/(\S+)[^\n]*\n(.*?$endpt_regex)\/(\S+)([^\n]*\n\s*data arrival time)/s) {
					$start_pin = $1;
					$end_pin = $3;
					$temp = $2 . '/' . $3 . $4;
				}
				
				# Corner case when /CLK appears as startpoint
				if ($start_pin eq "") {
					$temp = $cur_path;
					$startpt =~ s/\/CLK//;
					$startpt_regex = make_regex($startpt);
					while ($temp =~ m/$startpt_regex\/(\S+)[^\n]*\n(.*?$endpt_regex)\/(\S+)([^\n]*\n\s*data arrival time)/s) {
						$start_pin = $1;
						$end_pin = $3;
						$temp = $2 . '/' . $3 . $4;
					}
				}
				
				# For in/out
				if ($start_pin eq "" and $end_pin eq "") {
					if ($startpt =~ m/\//) {
						$temp = $cur_path;
						while ($temp =~ m/$startpt_regex\/(\S+)[^\n]*\n(.*data arrival time)/s) {
							$start_pin = $1;
							$temp = $2;
						}
					}
					if ($endpt =~ m/\//) {
						$temp = $cur_path;
						while ($temp =~ m/$endpt_regex\/(\S+)[^\n]*\n(.*data arrival time)/s) {
							$end_pin = $1;
							$temp = $2;
						}
					}
				}
				my $worst_prev_slack = "";
				my $prev_slack = "";
				my $worst_next_slack = "";
				my $next_slack = "";
				my $worst_fan_out = "";
				my $worst_fan_in = "";
				my $setup_scen = $scenario;
				if ( $flag == 1)
				{
					$setup_scen =~ s/.+(typrc.+)/$1/;
				}
				elsif ($flag == 2)
				{
					$setup_scen =~ s/.+(FuncTT.+)/$1/;
				}
				elsif ($flag == 3)
				{
					$setup_scen =~ s/.+(setup.+)/$1/;
				}
				else
				{
					$setup_scen = "none";
				}
				#print "$setup_scen\n";
				if (defined $start_pin) {
					if (defined $setup_startpoints_hash{prev_slack}{$startpt}{$start_pin}{$setup_scen}) {
						$prev_slack = $setup_startpoints_hash{prev_slack}{$startpt}{$start_pin}{$setup_scen};		# Store for displaying later
						my @temp_array = split /,/, $setup_startpoints_hash{prev_slack}{$startpt}{$start_pin}{$setup_scen};	# Get each pin
						foreach (@temp_array) {
							$_ =~ s/^[^:]+://;						# Remove extra information
							if ($worst_prev_slack eq "" or $_ < $worst_prev_slack) {
								$worst_prev_slack = sprintf "%.3f", $_;			# Find the worst slack
							}
						}
					}
					if (defined $setup_startpoints_hash{fan_out}{$startpt}{$start_pin}{$setup_scen}) {
						$worst_fan_out = $setup_startpoints_hash{fan_out}{$startpt}{$start_pin}{$setup_scen};
					}
					$startpt .= "/$start_pin" unless $start_pin eq "";
				}
				if (defined $end_pin) {
					if (defined $setup_endpoints_hash{next_slack}{$endpt}{$end_pin}{$setup_scen}) {
						$next_slack = $setup_endpoints_hash{next_slack}{$endpt}{$end_pin}{$setup_scen};
						my @temp_array = split /,/, $setup_endpoints_hash{next_slack}{$endpt}{$end_pin}{$setup_scen};
						foreach (@temp_array) {
							$_ =~ s/^[^:]+://;
							if ($worst_next_slack eq "" or $_ < $worst_next_slack) {
								$worst_next_slack = sprintf "%.3f", $_;
							}
						}
					}
					if (defined $setup_endpoints_hash{fan_in}{$endpt}{$end_pin}{$setup_scen}) {
						$worst_fan_in = $setup_endpoints_hash{fan_in}{$endpt}{$end_pin}{$setup_scen};
					}
					$endpt .= "/$end_pin" unless $end_pin eq "";
				}
				##
                my $startpt_raw = $startpt;
                my $endpt_raw = $endpt;
				$endpt .= "-case".$scenario;
				$startpt .= "-case".$scenario;
				
				
				my $pin_regex = make_regex($start_pin);
				$cur_path =~ s/^(\s*$startpt_regex\/$pin_regex[^\n]*)\n/$1     Prev Slack   $prev_slack\n/sm;	# Add prev slack info to right of start pin
				$pin_regex = make_regex($end_pin);
				$cur_path =~ s/^(\s*$endpt_regex\/$pin_regex[^\n]*)\n/$1     Next Slack   $next_slack\n/sm;		# Add next slack info to right of end pin
				
				# done parsing path, store in hash of endpoints
				my $key = "$group:$endpt";
				my $start_key = "$group:$startpt";
	
				# only update the first time an endpoint shows up
				# this should be the worst case
	
				if ( !defined $paths_hash{$key}{SLACK} ) {
					$paths_hash{$key}{STARTPT_RAW} = $startpt_raw;
					$paths_hash{$key}{STARTPT} = $startpt;
					$paths_hash{$key}{ENDPT_RAW} = $endpt_raw;
					$paths_hash{$key}{ENDPT}   = $endpt;
					$paths_hash{$key}{SLACK}   = $slack;
					$paths_hash{$key}{GROUP}   = $group;
					$paths_hash{$key}{LEVELS}  = $levels;
					$paths_hash{$key}{BFX_CELLS} = $bfx_cells;
					$paths_hash{$key}{PATH}    = $cur_path;
					$groups_hash{$fake_group} = 1;
					
					$paths_hash{$key}{WORST_PREV_SLACK} = $worst_prev_slack;
					$paths_hash{$key}{WORST_NEXT_SLACK} = $worst_next_slack;
					$paths_hash{$key}{WORST_FAN_IN} = $worst_fan_in;
					$paths_hash{$key}{WORST_FAN_OUT} = $worst_fan_out;

					$paths_hash{$key}{SCENARIO} = $scenario;
					#print ("$paths_hash{$key}{SLACK} $paths_hash{$key}{GROUP} $paths_hash{$key}{SCENARIO}\n");
				}
				
				elsif ( !defined $key_hash{$start_key} ) {
					
					while (defined $paths_hash{$key}{SLACK} ) {
						$key .= " ";
					}
					
					$paths_hash{$key}{STARTPT_RAW} = $startpt_raw;
					$paths_hash{$key}{STARTPT} = $startpt;
					$paths_hash{$key}{ENDPT}   = $endpt;
					$paths_hash{$key}{ENDPT_RAW} = $endpt_raw;
					$paths_hash{$key}{SLACK}   = $slack;
					$paths_hash{$key}{GROUP}   = $group;
					$paths_hash{$key}{LEVELS}  = $levels;
					$paths_hash{$key}{BFX_CELLS} = $bfx_cells;
					$paths_hash{$key}{PATH}    = $cur_path;
					$groups_hash{$fake_group} = 1;
					
					$paths_hash{$key}{WORST_PREV_SLACK} = $worst_prev_slack;
					$paths_hash{$key}{WORST_NEXT_SLACK} = $worst_next_slack;
					$paths_hash{$key}{WORST_FAN_IN} = $worst_fan_in;
					$paths_hash{$key}{WORST_FAN_OUT} = $worst_fan_out;
					$paths_hash{$key}{SCENARIO} = $scenario;
				}
				
				if ( !defined $key_hash{$start_key} ) {
					$key_hash{$start_key} = $key;
				}
			}
		}
	}
	
	print "Parsed file $file \n";
#	print " " x (5 + 2*$num_length) . "\n";
	close INPUT;
}

print "Working ...\r";

foreach my $sort (@sort_list) {

if (!$sort_levels && $sort eq $sort_list[1]) {
	last;
}

foreach my $uniq_startpts ((0,1)) {
	
	my $suffix;
	if ($uniq_startpts) {
		$suffix = "startpts";
	} else {
		$suffix = "endpts";
	}
	
	# Now let's uniquify the endpoint hash.
	# We want to treat sig[#] (bus ports), sig_#__# (arrays), 
	# and sig_# (reg buses) as unique paths.
	foreach my $blm (@blms) {
		
		my %unique_endpts_hash = ();
		#my %unique_endpts_groups;
		
		my @sorted_endpts_list;
		# flip startpts/endpts
		if ( $uniq_startpts ) {
			@sorted_endpts_list = sort keys %key_hash;
			$endpt_str = "Startpoint";
			$startpt_str = "Endpoint";
		} else {
			@sorted_endpts_list = sort keys %paths_hash;
		}

		foreach my $cur_endpt ( @sorted_endpts_list ) {
			next if ($cur_endpt =~ m/ $/);
			
			my $hash_key = $uniq_startpts ? $key_hash{$cur_endpt} : $cur_endpt;
			
			if ($cur_endpt =~ /$blm/) {   # only for the blm; or if blm not defined, for everything
			
				my $group     = $paths_hash{$hash_key}{GROUP};
				my $slack     = $paths_hash{$hash_key}{SLACK};
				
				my $real_group = $group;
				$group = "all_groups" if defined $all_groups or defined $add_groups;
				
				# Uniquify
				if ( $cur_endpt =~ /(.*)\[\d+\\?\]/ ) {
					$cur_endpt = $1 . "[#]";
				} elsif ( $cur_endpt =~ /(reg_\d+__\d+)/ ) {
					$cur_endpt =~ s/$1/reg_\#__\#/;
				} elsif ( $cur_endpt =~ /(reg_\d+)/ ) {
					$cur_endpt =~ s/$1/reg_\#/;
				}
                $cur_endpt =~ s/_\d+/_\#/g;
				

#				$cur_endpt =~ s/deim\d/deim\#/;
#				$cur_endpt =~ s/desdcdect\d/desdcdect\#/;
#				$cur_endpt =~ s/desdcdist\d/desdcdist\#/;
#				$cur_endpt =~ s/desdcsad\d/desdcsad\#/;
#				$cur_endpt =~ s/desdcuopqt\d/desdcuopqt\#/;
#				$cur_endpt =~ s/I_DeimmCtl\d_DI0/I_DeimmCtl\#_DI0/;
#				$cur_endpt =~ s/depict\d/depict\#/;
#				$cur_endpt =~ s/defdct\d/defdct\#/;
#				$cur_endpt =~ s/defdcdec\d/defdcdec\#/;
#				$cur_endpt =~ s/defdcuopq\d/defdcuopq\#/;
#				$cur_endpt =~ s/I_UopqEntry\d/I_UopqEntry\#/;
#				$cur_endpt =~ s/I_E[01]InsLen_DE1/I_E\#InsLen_DE1/;
#				$cur_endpt =~ s/I_O[01]InsLen_DE1/I_O\#InsLen_DE1/;
#				$cur_endpt =~ s/defdcc[01]/defdcc\#/;
#				$cur_endpt =~ s/dedisc[01]/dedisc\#/;
#				$cur_endpt =~ s/deimmc[01]/deimmc\#/;
#				$cur_endpt =~ s/I_SlotVal\d_DI0/I_SlotVal\#_DI0/;
#				$cur_endpt =~ s/I_DispatchCtlDec\d_DI0/I_DispatchCtlDec\#_DI0/;
#				$cur_endpt =~ s/uopqSlot\d/uopqSlot\#/;
#				$cur_endpt =~ s/acsSlot\d/acsSlot\#/;
#				$cur_endpt =~ s/desdcdecc[01]/desdcdecc\#/;
#				$cur_endpt =~ s/I_StCamHit\d_DE3/I_StCamHit\#_DE3/;
#				$cur_endpt =~ s/I_LdCamHit\d_DE3/I_LdCamHit\#_DE3/;
#				$cur_endpt =~ s/depicc[01]/depicc\#/;
#				$cur_endpt =~ s/I_CamEntry\d+/I_CamEntry\#/;
#				$cur_endpt =~ s/dermsseqt[01]/dermsseqt\#/;
#				$cur_endpt =~ s/I_EAQEntry\d_DE6/I_EAQEntry\#_DE6/;
#				
#				$cur_endpt =~ s/bplft\/bpb2blft\/data\d{1,2}/bplft\/bpb2blft\/data\#/;
#				$cur_endpt =~ s/bpbot\/bpb2b\/tagbank\d{1,2}/bpbot\/bpb2b\/tagbank\#/;
#				$cur_endpt =~ s/bpbot\/bpb2b\/lru0\/data\d/bpbot\/bpb2b\/lru0\/data\#/;
#				$cur_endpt =~ s/bpbot\/bpita\/bank0\/Bank\d/bpbot\/bpita\/bank0\/Bank\#/;
#				$cur_endpt =~ s/bpmid\/bpb1b\/Bnk\d\d/bpmid\/bpb1b\/Bnk\#/;
#				$cur_endpt =~ s/bppht\/ptn\d/bppht\/ptn\#/;
#				$cur_endpt =~ s/bppht\/bank\d/bppht\/bank\#/;
#				$cur_endpt =~ s/bppht\/PtnLoFifoC\d/bppht\/PtnLoFifoC\#/;
#				$cur_endpt =~ s/bpctl\/I_Vid\d/bpctl\/I_Vid\#/;
#				$cur_endpt =~ s/bpctl\/I_FlpV\d/bpctl\/I_FlpV\#/;
#				$cur_endpt =~ s/bpctl\/bankt\d/bpctl\/bankt\#/;
#				$cur_endpt =~ s/bpctl\/I_Cl\d/bpctl\/I_Cl\#/;
#				$cur_endpt =~ s/bpctl\/bpnpclpp\d/bpctl\/bpnpclpp\#/;
#				
#				$cur_endpt =~ s/bp0_ic0_BP_PrqLinAddr_BP0_\d{1,2}___bp0_0/bp0_ic0_BP_PrqLinAddr_BP0_\#___bp0_0/;
#				$cur_endpt =~ s/bp0_ic0_BP_PrqL2EndLinAddr_BP4_\d{1,2}___bp0_0/bp0_ic0_BP_PrqL2EndLinAddr_BP4_\#___bp0_0/;
#				
#				# PDA SMT
#				$cur_endpt =~ s/de[01]\//de\#\//;
#				$cur_endpt =~ s/DEPICT[01]/DEPICT\#/;
				
				if (defined $uniquify) {
					$_ = $cur_endpt;
					eval $uniquify;
					$cur_endpt = $_;
				}
				
				# Check for inx pairs
				my $path = $paths_hash{$hash_key}{PATH};
				my @path_array = split /\n/, $path;
				my $searching = 1;
				my $prev_cell = "";
				my $num_pairs = 0;
				my $prev_inx = "";
				my @lines = ();
				my $num_bfx = 0;
				foreach my $line (@path_array) {
                   # my $regex = '^  \S+\/[XZ]\s+\('.BUF_REGEX ;
my $regex = '^  \S+\/Z(?:n)?\s+\(' . BUF_REGEX;
                    
					if ($line =~ m/$regex/) {
						$num_bfx += 1;			# Count the buffers
					}
					# Go through the cells and if two inx's appear with only nets seperating them, count and highlight them
					if ($searching) {
						#if ($line =~ m/^\s*(\S+\/[XZ])\s+\(([^\)]+)\)/) {
if ($line =~ m/^\s*(\S+\/Z(?:n)?)\s+\(([^\)]+)\)/i) {
                            
							$prev_inx = $1;
							my $id = $2;
							if (is_inverter($id)) {
								$searching = 0;
								@lines = ();
							}
						}
					} else {
						#if ($line =~ m/^\s*(\S+\/[XZ])\s+\(([^\)]+)\)/) {
if ($line =~ m/^\s*(\S+\/Z(?:n)?)\s+\(([^\)]+)\)/i) {
							my $cur_inx = $1;
							my $id = $2;
							if (is_inverter($id)) {
								$cur_inx = make_regex($cur_inx);
								$prev_inx = make_regex($prev_inx);
								$path =~ s/^  ($prev_inx)/->$1/sm;
								foreach my $cur_line (@lines) {
									$cur_line =~ s/^  //;
									$cur_line = make_regex($cur_line);
									$path =~ s/^  ($cur_line)/| $1/sm;
								}
								$path =~ s/^  ($cur_inx)/->$1/sm;
								$num_pairs += 1;
							}
							$searching = 1;
						}
						push @lines, $line;
					}
				}
				
				if ( defined $unique_endpts_hash{$group}{$cur_endpt} ) {
					# already exists
					# see if it's the worst slack and store that one
					$unique_endpts_hash{$group}{$cur_endpt}{NUM}++;
					if ( $slack < 0 ) {
						$unique_endpts_hash{$group}{$cur_endpt}{TOTSLACK} += $slack;
					}
					if ( $slack < $unique_endpts_hash{$group}{$cur_endpt}{SLACK} ) {
						if ($uniq_startpts) {
							$unique_endpts_hash{$group}{$cur_endpt}{ENDPT}    = $paths_hash{$hash_key}{STARTPT};
							$unique_endpts_hash{$group}{$cur_endpt}{STARTPT}  = $paths_hash{$hash_key}{ENDPT};
							
							$unique_endpts_hash{$group}{$cur_endpt}{WORST_PREV_SLACK} = $paths_hash{$hash_key}{WORST_PREV_SLACK};
							$unique_endpts_hash{$group}{$cur_endpt}{WORST_NEXT_SLACK} = $paths_hash{$hash_key}{WORST_NEXT_SLACK};
							$unique_endpts_hash{$group}{$cur_endpt}{WORST_FAN_IN} = $paths_hash{$hash_key}{WORST_FAN_IN};
							$unique_endpts_hash{$group}{$cur_endpt}{WORST_FAN_OUT} = $paths_hash{$hash_key}{WORST_FAN_OUT};
						} else {
							$unique_endpts_hash{$group}{$cur_endpt}{STARTPT}    = $paths_hash{$hash_key}{STARTPT};
							$unique_endpts_hash{$group}{$cur_endpt}{STARTPT_RAW}    = $paths_hash{$hash_key}{STARTPT_RAW};
							$unique_endpts_hash{$group}{$cur_endpt}{ENDPT}      = $paths_hash{$hash_key}{ENDPT};
							$unique_endpts_hash{$group}{$cur_endpt}{ENDPT_RAW}      = $paths_hash{$hash_key}{ENDPT_RAW};
							
							$unique_endpts_hash{$group}{$cur_endpt}{WORST_PREV_SLACK} = $paths_hash{$hash_key}{WORST_PREV_SLACK};
							$unique_endpts_hash{$group}{$cur_endpt}{WORST_NEXT_SLACK} = $paths_hash{$hash_key}{WORST_NEXT_SLACK};
							$unique_endpts_hash{$group}{$cur_endpt}{WORST_FAN_IN} = $paths_hash{$hash_key}{WORST_FAN_IN};
							$unique_endpts_hash{$group}{$cur_endpt}{WORST_FAN_OUT} = $paths_hash{$hash_key}{WORST_FAN_OUT};
						}
						$unique_endpts_hash{$group}{$cur_endpt}{SLACK}      = $paths_hash{$hash_key}{SLACK};
						$unique_endpts_hash{$group}{$cur_endpt}{LEVELS}     = $paths_hash{$hash_key}{LEVELS};
						$unique_endpts_hash{$group}{$cur_endpt}{BFX_CELLS}  = $paths_hash{$hash_key}{BFX_CELLS};
						$unique_endpts_hash{$group}{$cur_endpt}{PATH}       = $paths_hash{$hash_key}{PATH};
						$unique_endpts_hash{$group}{$cur_endpt}{BFX}		= $num_bfx;
						$unique_endpts_hash{$group}{$cur_endpt}{INX_PAIRS}	= $num_pairs;
						$unique_endpts_hash{$group}{$cur_endpt}{REAL_LEVELS} = $paths_hash{$hash_key}{LEVELS} - ($num_bfx + 2*$num_pairs);
						
						$unique_endpts_hash{$group}{$cur_endpt}{GROUP} = $real_group;
						$unique_endpts_hash{$group}{$cur_endpt}{SCENARIO}   = $paths_hash{$hash_key}{SCENARIO};
					}
				} else {
					# new
					if ( $slack < 0 ) {
						$unique_endpts_hash{$group}{$cur_endpt}{TOTSLACK} = $slack;
					} else {
						$unique_endpts_hash{$group}{$cur_endpt}{TOTSLACK} = 0;
					}
					
					if ($uniq_startpts) {
						$unique_endpts_hash{$group}{$cur_endpt}{ENDPT}    = $paths_hash{$hash_key}{STARTPT};
						$unique_endpts_hash{$group}{$cur_endpt}{STARTPT}  = $paths_hash{$hash_key}{ENDPT};
						
						$unique_endpts_hash{$group}{$cur_endpt}{WORST_PREV_SLACK} = $paths_hash{$hash_key}{WORST_PREV_SLACK};
						$unique_endpts_hash{$group}{$cur_endpt}{WORST_NEXT_SLACK} = $paths_hash{$hash_key}{WORST_NEXT_SLACK};
						$unique_endpts_hash{$group}{$cur_endpt}{WORST_FAN_IN} = $paths_hash{$hash_key}{WORST_FAN_IN};
						$unique_endpts_hash{$group}{$cur_endpt}{WORST_FAN_OUT} = $paths_hash{$hash_key}{WORST_FAN_OUT};
					} else {
						$unique_endpts_hash{$group}{$cur_endpt}{STARTPT}    = $paths_hash{$hash_key}{STARTPT};
						$unique_endpts_hash{$group}{$cur_endpt}{STARTPT_RAW}    = $paths_hash{$hash_key}{STARTPT_RAW};
						$unique_endpts_hash{$group}{$cur_endpt}{ENDPT}      = $paths_hash{$hash_key}{ENDPT};
						$unique_endpts_hash{$group}{$cur_endpt}{ENDPT_RAW}      = $paths_hash{$hash_key}{ENDPT_RAW};
						
						$unique_endpts_hash{$group}{$cur_endpt}{WORST_PREV_SLACK} = $paths_hash{$hash_key}{WORST_PREV_SLACK};
						$unique_endpts_hash{$group}{$cur_endpt}{WORST_NEXT_SLACK} = $paths_hash{$hash_key}{WORST_NEXT_SLACK};
						$unique_endpts_hash{$group}{$cur_endpt}{WORST_FAN_IN} = $paths_hash{$hash_key}{WORST_FAN_IN};
						$unique_endpts_hash{$group}{$cur_endpt}{WORST_FAN_OUT} = $paths_hash{$hash_key}{WORST_FAN_OUT};
					}
					
					$unique_endpts_hash{$group}{$cur_endpt}{SLACK}      = $paths_hash{$hash_key}{SLACK};
					$unique_endpts_hash{$group}{$cur_endpt}{LEVELS}     = $paths_hash{$hash_key}{LEVELS};
					$unique_endpts_hash{$group}{$cur_endpt}{BFX_CELLS}  = $paths_hash{$hash_key}{BFX_CELLS};
					$unique_endpts_hash{$group}{$cur_endpt}{NUM}        = 1;
					$unique_endpts_hash{$group}{$cur_endpt}{PATH}       = $paths_hash{$hash_key}{PATH};
					
					$unique_endpts_hash{$group}{$cur_endpt}{BFX}		= $num_bfx;
					$unique_endpts_hash{$group}{$cur_endpt}{INX_PAIRS}	= $num_pairs;
					$unique_endpts_hash{$group}{$cur_endpt}{REAL_LEVELS} = $paths_hash{$hash_key}{LEVELS} - ($num_bfx + 2*$num_pairs);
					
					$unique_endpts_hash{$group}{$cur_endpt}{GROUP} = $real_group;
					$unique_endpts_hash{$group}{$cur_endpt}{SCENARIO}   = $paths_hash{$hash_key}{SCENARIO};
				}
			}
		}
		
		if (scalar keys %unique_endpts_hash == 0) {
			print "Blm '$blm' not found, skipping\n";
			next;
		}
		
		my $output_file;
        my $out_pathpts_file;
		my $output_histo_file;
		
		my $rpt_gen;
		if ($blm eq ".*"){
			$output_file = $input_file . ".sum.sort_" . $sort . ".$suffix";
			$output_histo_file = $input_file . ".all" . ".hist.sort_" . $sort . ".$suffix";
			$rpt_gen = "sort_${sort}.$suffix report for all paths";
			print "Generating $rpt_gen ...\r";
		}
		else{
			$output_file = $input_file . ".$blm" . ".sum.sort_" . $sort . ".$suffix";
			$output_histo_file = $input_file . ".$blm" . ".hist.sort_" . $sort . ".$suffix";
			$rpt_gen = "sort_${sort}.$suffix report for $blm";
			print "Generating $rpt_gen ...\r";
		}
		
        my $PATHPTS_OUTFILE;
		open OUTFILE, ">$output_file" or die "ERROR:  Cannot open $output_file\n";
        
		
		my $format_hdr = "Group: %s\n"
			       . "%-5s %-15.15s %-22s %-55s %-58s %-7s %-8s %-5s %-5s %-8s %-5s %-10s %-12s %-12s %-12s %-12s\n" x 3;
		#my $format= "#%-4d %-15.15s %-15s %-55s %-55s %-6s %-4d %-4d %-4d %-6s %-3s %-6s %-6s %-6s %-6s %-6s\n";
		my $format = "#%-5d %-15.15s %-22s %-55s %-55s %-10s %-8s %-5s %-5s %-8s %-5s %-10s %-12s %-12s %-12s %-12s\n";
		if(!$timescale) {
			#$format = "#%-4d %-15.15s %-15s %-55s %-55s %-6.3f %-4d %-4d %-4d %-6s %-3s %-6s %-6s %-6s %-6s %-6s\n";
			$format = "#%-5d %-15.15s %-22s %-55s %-55s %-10s %-8s %-5s %-5s %-8s %-5s %-10s %-12s %-12s %-12s %-12s\n";
		}
		###            #    start/end  slack lvls real inx pairs path tns prev out  next  in
		my $paths      = "";
		my $endpt_coll = "";
		my $total_path_num = 1;

		my %period_perc_cnt;
		my %period_unique_perc_cnt;
		
        if($suffix eq "endpts")
        {
            $out_pathpts_file = "$input_file."."pathpts";
            open($PATHPTS_OUTFILE, '>', $out_pathpts_file) or die "ERROR: endpts file could not be opened.\n";
            print "Generating $out_pathpts_file... (for the GTECH automachine)...\n";
        }
			
		foreach my $cur_group ( sort keys %groups_hash ) {
			
			foreach my $cur_perc ( @LIST_OF_PERIOD_PERC ) {
				$period_perc_cnt{$cur_perc} = 0;
				$period_unique_perc_cnt{$cur_perc} = 0;
			}
			my $group_total_failing = 0;
			my $group_unique_total_failing = 0;
			
			print OUTFILE "-" x 275, "\n";
			
			 
			my $out_str = sprintf $format_hdr, $cur_group,
							   "", "", "", "", "",
							   "", "", "", "", "(bfx +", "Num", "", "Worst", "Start", "Worst", "End",
							   "", "", "", "", "",
							   "", "", "Real", "inx/", "inx", "Pa-", "", "Prev", "Fan", "Next", "Fan",
							   "", "Path Group", "Corner", "Uniquified $endpt_str", "Worst $startpt_str",
							   "Slack", "Lvls", "Lvls", "bfx", "pairs)", "ths", "TNS", "Slack", "Out", "Slack", "In";

			print OUTFILE $out_str;
			#printf OUTFILE ("%15s %15s %25s %30s %25s %15s %15s %15s %15s %15s %15s %15s %15s %15s %15s", $path1, $corner1,$end1,$start1,$slk1,$lvl1,$real1,$inx1,$bfx1,$num_path1,$tns1,$wps1,$sfo1,$wns1,$efi1); 
			print OUTFILE "-" x 275, "\n";
			
			my @cur_endpts_list = ();
			
			if ($sort eq "slack") {
				@cur_endpts_list = sort 
					{$unique_endpts_hash{$cur_group}{$b}{SCENARIO} cmp $unique_endpts_hash{$cur_group}{$a}{SCENARIO} || $unique_endpts_hash{$cur_group}{$a}{SLACK} <=> $unique_endpts_hash{$cur_group}{$b}{SLACK} } keys %{$unique_endpts_hash{$cur_group}};
			}
			
			if ($sort eq "real_levels") {
				@cur_endpts_list = sort 
					{$unique_endpts_hash{$cur_group}{$b}{REAL_LEVELS} <=> $unique_endpts_hash{$cur_group}{$a}{REAL_LEVELS}
					or $unique_endpts_hash{$cur_group}{$a}{SLACK} <=> $unique_endpts_hash{$cur_group}{$b}{SLACK} }
						keys %{$unique_endpts_hash{$cur_group}};
			}


			%nets = ();
			foreach my $cur_endpt ( @cur_endpts_list )  {
				my $startpt     = $unique_endpts_hash{$cur_group}{$cur_endpt}{STARTPT};
				my $org_endpt   = $unique_endpts_hash{$cur_group}{$cur_endpt}{ENDPT};
				my $slack       = $unique_endpts_hash{$cur_group}{$cur_endpt}{SLACK};
				$slack = $timescale ? $slack*1000 : $slack;
				my $levels      = $unique_endpts_hash{$cur_group}{$cur_endpt}{LEVELS};
				my $bfx_cells   = $unique_endpts_hash{$cur_group}{$cur_endpt}{BFX_CELLS};
				my $num         = $unique_endpts_hash{$cur_group}{$cur_endpt}{NUM};
				my $real_lvls   = $unique_endpts_hash{$cur_group}{$cur_endpt}{REAL_LEVELS}; 
				
				my $real_group  = $unique_endpts_hash{$cur_group}{$cur_endpt}{GROUP};
				
				my $worst_prev_slack = $unique_endpts_hash{$cur_group}{$cur_endpt}{WORST_PREV_SLACK};
				$worst_prev_slack = ($timescale && ($worst_prev_slack ne "")) ? $worst_prev_slack*1000 : $worst_prev_slack;
				my $worst_next_slack = $unique_endpts_hash{$cur_group}{$cur_endpt}{WORST_NEXT_SLACK};
				$worst_next_slack = ($timescale && ($worst_next_slack ne "")) ? $worst_next_slack*1000 : $worst_next_slack;
				my $worst_fan_in = $unique_endpts_hash{$cur_group}{$cur_endpt}{WORST_FAN_IN};
				my $worst_fan_out = $unique_endpts_hash{$cur_group}{$cur_endpt}{WORST_FAN_OUT};
				
				my $cur_corner   =	$unique_endpts_hash{$cur_group}{$cur_endpt}{SCENARIO}; 
				my $tns		= $unique_endpts_hash{$cur_group}{$cur_endpt}{TOTSLACK} * -1;
				$tns = $timescale ? $tns*1000 : $tns;
				my $index = 0;
				next if($logic_dom && ($levels < 20 || $bfx_cells > 6));
				while ($tns >= 1000) {				# Make TNS fit into it's column by calculating the order of magnitude
					last if ($index + 1 >= scalar @orders);
					$tns /= 1000;
					$index += 1;
				}
				if ($tns < 10) {
					$tns = sprintf "%.3f$orders[$index]", $tns;
				} else {
					$tns = sprintf "%.0f$orders[$index]", $tns;
				}
				
				$paths .= "  \#$total_path_num\n"; #print "$total_path_num\n";
				my $path = $unique_endpts_hash{$cur_group}{$cur_endpt}{PATH};

                if($suffix eq "endpts")
                {

                    #foreach my $group (sort(keys(%unique_endpts_hash)))
                    #{
                    #    foreach my $cur_endpt (%{$unique_endpts_hash{$group}})
                    my $startpt; 
                    my $endpt; 

                    if(defined($unique_endpts_hash{$cur_group}{$cur_endpt}{STARTPT_RAW}))
                    {
                        $startpt = $unique_endpts_hash{$cur_group}{$cur_endpt}{STARTPT_RAW};
                    }

                    if(defined($unique_endpts_hash{$cur_group}{$cur_endpt}{ENDPT_RAW}))
                    {
                        $endpt =$unique_endpts_hash{$cur_group}{$cur_endpt}{ENDPT_RAW};
                    }

                    if($startpt eq "" || $endpt eq "")
                    {
                        next;
                    }
                    #chop($startpt); chop($endpt);

                    # Sanitize out pin and process
                    #$startpt =~ /(.*)\/.*/;
                    #if($1 ne "")
                    #{
                    #    $startpt = $1;
                    #}
                    #$endpt =~ /(.*)\/.*/;
                    #if($1 ne "")
                    #{
                    #    $endpt = $1;
                    #}
                    print $PATHPTS_OUTFILE "$startpt,$endpt\n";
                    
                    #}
                }
				
				# Swap variables if working on the startpts rpt
				if ( $uniq_startpts ) {
					($startpt, $org_endpt) = ($org_endpt, $startpt);
				}
				
				my @path_array = split /\n/, $path;
				
				my $searching = 1;
				my $module;
				my $save_line;
				my $flag = 0;
				my $prev_line = "";
				# Highlight slow trans and incr
				foreach my $line (@path_array) {
					last if ($line =~ m/data arrival time/);
					if ($line =~ m/^(\s*\S+\/[XZ]\s+\(\w+\))\s+(\d+\.\d+)\s+(\d+\.\d+)/smg) {
						my $id = $1;
						my $trans = $2;
						my $incr = $3;
						
						$module = $id;
						
						$id = make_regex($id);
						my $trans_regex = make_regex($trans);
						my $incr_regex = make_regex($incr);
						
						if ($incr > $incr_threshold) {
							$path =~ s/^($id\s+$trans_regex\s+$incr_regex) /$1\^/sm;
							
							#check for slow edge rate nets between modules
							if ($searching) {
								$searching = 0;
								$flag = 0;
							} elsif ($flag) {
								$flag = 0;
								$prev_line =~ s/^\s*\S+\s+\(\w+\)\s+(\d+\.\d+).*/$1/;
								$nets{$save_line} = $prev_line;
								$nets{slacks}{$save_line} = $slack;
							}
							$module =~ s/\s*(\S+)\/[^\/]+\/[XZ].*/$1/;
							#$module = make_regex($module);
						} else {
							$searching = 1;
						}
						
						if ($trans > $trans_threshold) {
							$path =~ s/^($id\s+$trans_regex) /$1\^/sm;
						}
					} elsif (!$searching && !$flag) {
						if ($line =~ m/^\s*(\S+)\/[^\/]+\s+\(net\)/smg) {
							my $tmp = $1;
							$tmp =~ s/\s*(\S+)\/[^\/]+\/[XZ].*/$1/;
							if ($tmp ne $module) {
								$save_line = $line;
								$flag = 1;
							}
						}
					}
					$prev_line = $line;
				}
				
				my $num_pairs = "($unique_endpts_hash{$cur_group}{$cur_endpt}{BFX}+$unique_endpts_hash{$cur_group}{$cur_endpt}{INX_PAIRS})";
				
				# Highlight bfx's
                my $regex = '^  (\S+\/[XZ]\s+\('.BUF_REGEX.')';
				$path =~ s/$regex/->$1/smg;
				
				# paullin : start
				# total up group summary by starting blm
				my $startBlmName = $startpt;
				unless ($startpt =~ m/\//) {
					$startBlmName = $real_group;
				} elsif ($hasRlmName) {
					$startBlmName =~ s/.*?\/(.*?)\/.*$/$1/;
				} else {
					$startBlmName =~ s/\/.*$//;
				}
				
				if (not exists $rlmCount{$cur_group}{$startBlmName}) {
					foreach my $cur_perc ( @LIST_OF_PERIOD_PERC ) {
						$rlmCount{$cur_group}{$startBlmName}{$cur_perc} = 0;
					}
				}
				# paullin : end
				
				# Swap back vars
				if ( $uniq_startpts ) {
					($startpt, $org_endpt) = ($org_endpt, $startpt);
				}
				
				$paths .= $path . "\n";
				
				my $tmp_startpt = $startpt;
	#			$tmp_startpt =~ s/^[^\/]+\/[^\/]+\///;
				$tmp_startpt   =~ s/-case\w*//;
				$tmp_startpt   =~ s/\S+://;
				$tmp_startpt = substr $tmp_startpt, 0, 55;
				my $tmp_endpt   = $cur_endpt;
	#			$tmp_endpt   =~ s/^[^\/]+\/[^\/]+\///;
				##added 10.9.1
				$tmp_endpt   =~ s/-case\w*//;
				$tmp_endpt   =~ s/\S+://;
				$tmp_endpt   = substr $tmp_endpt, 0, 55;
				$cur_corner =~ s/(setup|hold)_(\w+)_\w+_\w+/$2/;
				my $out_str = sprintf $format, $total_path_num, $real_group, $cur_corner, $tmp_endpt, $tmp_startpt,
							    $slack, $levels, $real_lvls, $bfx_cells, $num_pairs, $num, $tns,
							    $worst_prev_slack, $worst_fan_out, $worst_next_slack, $worst_fan_in;
				print OUTFILE $out_str;
				#printf OUTFILE ("%s %10s %15s %15s %25s %30s %25s %15s %15s %15s %15s %15s %15s %15s %15s %15s %15s", $format, $total_path_num, $real_group, $cur_corner, $tmp_endpt, $tmp_startpt,$slack, $levels, $real_lvls, $bfx_cells, $num_pairs, $num, $tns,$worst_prev_slack, $worst_fan_out, $worst_next_slack, $worst_fan_in);
				$total_path_num++;
				$group_unique_total_failing++;
		
				# print clock gating mapping
				if ( $tmp_endpt =~ /(\S+RC_CG_HIER_INST\S+)/ ) {
					$tmp_endpt = $1;
					if ( $clk_gating_map =~ m/(\-\-$tmp_endpt.+?INFO:\s+Total\s+\d+\n)/sm ) {
						my $cur_gated_flops = $1;
						my @cur_gated_flops_list = split /\n/, $cur_gated_flops;
						print OUTFILE "      --" . $cur_gated_flops_list[1] . "\n";
						print OUTFILE "      --" . $cur_gated_flops_list[@cur_gated_flops_list-1] . "\n\n";
					}
				}
				
				foreach my $cur_perc ( @LIST_OF_PERIOD_PERC ) {
					my $tmp_slack = 0.0;
					$tmp_slack = $slack;
					my $tmp_cmp   = $PERIOD * $cur_perc / 100 * -1.0;
					if ( $tmp_slack < $tmp_cmp ) {
						$period_perc_cnt{$cur_perc} += $num;
						$period_unique_perc_cnt{$cur_perc}++;
						$group_total_failing += $num;
						# paullin : start
						$rlmCount{$cur_group}{$startBlmName}{$cur_perc}++;
						# paullin : end
						last;
					}
				}
				
				if ( $org_endpt =~ /_reg_\d+__\d+$/ or $org_endpt =~ /_reg_\d+$/ or $org_endpt =~ /_reg$/ ) {
					$endpt_coll .= "$org_endpt/D \\\n";
				} else {
					$endpt_coll .= "$org_endpt \\\n";
				}

			}
			
			$paths .= "\nSlow edge rate nets between modules:\n";
			$paths .= "                                              Fanout       Cap     Trans      Incr       Path      Location / Load        Attributes     Voltage\n";
			$paths .=   "--------------------------------------------------------------------------------------------------------------------------------------------\n";
			my @nets = sort sort_nets(keys(%nets));
			foreach my $net (@nets) {
				next if $net eq "slacks";
				$paths .= "$net\n";
				$paths .= "\tTrans of 2nd cell = $nets{$net}\n";
				$paths .= "\tSlack for above net's path = $nets{slacks}{$net}\n";
			}
			
			print OUTFILE "\n";
	 	
			print OUTFILE "Group Summary ($cur_group) Total Failing ${endpt_str}s:  $group_total_failing (uniquified $group_unique_total_failing)\n\n";
			print OUTFILE "${endpt_str}s Over Target           Total      Uniquified\n";
			my $group_summary_format = "%-5s%s -(%5sps-%5sps)       %-10d %-10d\n";
			my $prev_perc = "+";
			my $prev_perc_slack = "";
			foreach my $cur_perc ( @LIST_OF_PERIOD_PERC ) {
				my $cur_perc_slack = sprintf "%.2f", $PERIOD * $cur_perc / 100;
				my $out_str = sprintf $group_summary_format, "$cur_perc$prev_perc", "%", $cur_perc_slack, $prev_perc_slack,
									  $period_perc_cnt{$cur_perc}, $period_unique_perc_cnt{$cur_perc};
				print OUTFILE $out_str;
				$prev_perc = "-$cur_perc";
				$prev_perc_slack = $cur_perc_slack;
			}
			
			print OUTFILE "\n";
			
			my $print_rlm = 1;
			$print_rlm = 0 if ((defined $all_groups) || ($sort eq $sort_list[1]) || (defined $add_groups));
						
			# paullin : start
			my $file = "${setup_input}rlm.sum.${suffix}.${cur_group}";
			$file .= ".$blm" if defined $blms_file;
			if (-e "$file") {
				print "File $file already exists. Not generating a new one.\n";
				$print_rlm = 0;
			}
			open RLMSUM, ">> $file" or die "Cannot open $file for writting:$!" if $print_rlm;
			my $header_str = "Path Group: $cur_group\nSlack Distribution by percentage of negative slack\n";
			$header_str .= sprintf "%-20s", "Slack %";
			foreach my $cur_perc ( @LIST_OF_PERIOD_PERC ) {
				$header_str .= sprintf "%5d%%", -1*$cur_perc;
			}
			$header_str .= sprintf " | %-5s", "Total";
			print RLMSUM "$header_str\n" if $print_rlm;
			print RLMSUM "-"x60 . "\n" if $print_rlm;
			foreach my $blm (sort keys %{$rlmCount{$cur_group}}) {
				my $blm_total = 0;
				my $out_str = sprintf "%-20s", $blm;
				foreach my $cur_perc ( @LIST_OF_PERIOD_PERC ) {
					$out_str .= sprintf "%6d", $rlmCount{$cur_group}{$blm}{$cur_perc}; 
					$rlmCount{$cur_group}{"Total"}{$cur_perc} += $rlmCount{$cur_group}{$blm}{$cur_perc};
					$blm_total += $rlmCount{$cur_group}{$blm}{$cur_perc};
					$TotalCount{$blm}{$cur_perc} += $rlmCount{$cur_group}{$blm}{$cur_perc};
				}
				print RLMSUM "$out_str" if $print_rlm;
				printf RLMSUM " | %5d\n", $blm_total if $print_rlm;
			}
			print RLMSUM "-"x60 . "\n" if $print_rlm;
			my $footer_str = sprintf "%-20s", "Total";
			my $rlm_total = 0;
			foreach my $cur_perc ( @LIST_OF_PERIOD_PERC ) {
				$footer_str .= sprintf "%6d", $rlmCount{$cur_group}{"Total"}{$cur_perc};
				$rlm_total += $rlmCount{$cur_group}{"Total"}{$cur_perc};
			}
			print RLMSUM "$footer_str" if $print_rlm;
			printf RLMSUM " | %5d\n\n", $rlm_total if $print_rlm;
			close RLMSUM if $print_rlm;
			# paullin : end
			
		} # end foreach $cur_group
		
		{
		my $file = "${setup_input}rlm.sum.${suffix}";
		$file .= ".$blm" if defined $blms_file;
		if (-e "$file") {
			print "File $file already exists. Not generating a new one.\n";
			last;
		}
		# paullin : start
		# print summary for each starting blm for all periods
		open RLMSUM, ">> $file" or die "Cannot open $file for writting:$!";
		#print RLMSUM "="x60 . "\n";
		#Note: the path group name determine how the final comapre results are presented
		my $header_str = "Path Group: All_Groups\nSlack Distribution by percentage of negative slack\n";
		$header_str .= sprintf "%-20s", "Slack %";
		foreach my $cur_perc ( @LIST_OF_PERIOD_PERC ) {
			$header_str .= sprintf "%5d%%", -1*$cur_perc;
		}
		$header_str .= sprintf " | %-5s", "Total";
		print RLMSUM "$header_str\n";
		print RLMSUM "-"x60 . "\n";
		foreach my $blm (sort keys %TotalCount) {
			my $blm_total = 0;
			my $out_str = sprintf "%-20s", $blm;
			foreach my $cur_perc ( @LIST_OF_PERIOD_PERC ) {
				$out_str .= sprintf "%6d", $TotalCount{$blm}{$cur_perc}; 
				$blm_total += $TotalCount{$blm}{$cur_perc}; 
				$TotalCount{"Total"}{$cur_perc} += $TotalCount{$blm}{$cur_perc};
			}
			print RLMSUM "$out_str";
			printf RLMSUM " | %5d\n", $blm_total;
		}
		print RLMSUM "-"x60 . "\n";
		my $footer_str = sprintf "%-20s", "Total";
		my $rlm_total = 0;
		foreach my $cur_perc ( @LIST_OF_PERIOD_PERC ) {
			$footer_str .= sprintf "%6d", $TotalCount{"Total"}{$cur_perc};
			$rlm_total += $TotalCount{"Total"}{$cur_perc};
		}
		print RLMSUM "$footer_str";
		printf RLMSUM " | %5d\n\n", $rlm_total;
		close RLMSUM;
		# paullin : end
		}
		
		# fix total number since we increment every loop
		$total_path_num--;
		print OUTFILE "Total Number of Uniquified $endpt_str Paths:  $total_path_num\n";
		print OUTFILE "Total Negative Slack:                       $tns ps\n\n";
		
		print OUTFILE "-" x160, "\n";
		print OUTFILE $paths;
		close OUTFILE;
        if(defined($PATHPTS_OUTFILE))
        {
            close($PATHPTS_OUTFILE);
        }
		print "Generated $rpt_gen     \n";
	} #end foreach $blm

} #end foreach $unique_startpts

} #end foreach $sort

###################################

sub is_inverter
{
	my $id = shift;
	#foreach (@inverter_ids) {
	#	return 1 if (substr($id, 0, length $_) eq $_);
	#}
    if($id =~ INV_REGEX) {
        return 1;
    }
	return 0;
}

sub make_regex
{
	my $input = shift;
	$input =~ s/\\/\\\\/g;
	$input =~ s/\//\\\//g;
	$input =~ s/\[/\\\[/g;
	$input =~ s/\]/\\\]/g;
	$input =~ s/\(/\\\(/g;
	$input =~ s/\)/\\\)/g;
	$input =~ s/\./\\\./g;
	$input =~ s/\*/\\\*/g;
	$input =~ s/\?/\\\?/g;
	$input =~ s/\+/\\\+/g;
	$input =~ s/\^/\\\^/g;
	$input =~ s/\$/\\\$/g;
	return $input;
}

sub sort_nets {
   no warnings 'numeric';
   $nets{$b} <=> $nets{$a} || $nets{$b} cmp $nets{$a};
}

#
# $Log: k12_summarize_timing_report_xv_all_groups.pl,v $
# Revision 1.7  2013-06-14 11:47:14-07  ikariapp
# Fixed TNS display bug
#
# Revision 1.6  2013-06-13 11:42:45-07  ikariapp
# Fixed bug with some endpoints not showing next slack
#
# Revision 1.5  2013-06-11 15:36:12-07  ikariapp
# Added support for multiple corner setup timing files
#
# Revision 1.3  2013-06-06 14:18:21-07  ikariapp
# Added revision to only take in FINAL_* Dg timing rpts.
# Added -timescale option to change units to ps
# Added -logic_dom option to view only logic dominated paths in timing report
#
# Revision 1.2  2013/05/29 17:38:12  hon-hin
# .added imad version to fix the files that has corner with the names. also fix it so that i can do with the FINAL prefixes in Dg reports.
#
#


