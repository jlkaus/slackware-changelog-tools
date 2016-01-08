#!/usr/bin/perl

use strict;
use warnings;
use POSIX;
use Time::Local;
use DateTime;
use DateTime::Format::Strptime;

# summary, overall, changes, all
my $display_mode = shift || "summary";

# send in the changelog on stdin


my @entries = ();
# each entry is a hashref:
#   timeline - timestamp string as shown in changelog
#   isotime - timestamp in iso fmt already
#   timestamp - timestamp converted to unix time
#   message - full message (if any) that is for the overall entry
#   [] changes
#       line - full line of change
#       linetype - linetype of change line
#       name  - filename changed (post)
#       changetype - rebuilt/upgraded/removed/added/patched (post)
#       changetypemod - sometimes it will say "Patched to avoid ..." sorts of things.  changetype would be patched, changetypemod would be the rest of it. 
#       message - full message (if any) associated with this change
#       securityfix - flag indicating that this change is for a security fix (last line in message is (* Security fix *) (post)
#       location - if this file appears to be an actual package, this is the path location of the package (post)
#       package - if this file appears to be an actual package, this is the short name of the package (no version, location, etc) (post)
#       version - if package, the version string (post)
#       arch - if package, the arch string (post)
#       build - if package, the build string (post)
#       ext - if package, the package extension (post)

# package change lines look like this:
# <location>/<package>-<version>-<arch>-<build>.<ext>:  <changetype>.

# changetype should be one of Upgraded, Rebuilt, Removed, Added.
# ext should be one of txz/tgz
# build should be text without spaces, dashes, or /
# arch should be text without spaces, dashes, or /
# version should be text without spaces, dashes, or /
# package should be text without spaces or /
# location should be text without spaces

# entries are seperated by +----------------------+ lines (not sure on the number of dashes there)
# they then start with a timestring line (left justified)
# then lines of the overall message (left justified or empty)
# change entry lines start with a left justified line that appears as above, and are followed by 0 or more lines indented by at least 2 spaces that are its message

my $cur_entry = {changes => []};
my $cur_change = undef;

my $cur_state = "want_date";

while(<>) {
	chomp;

	my $line_type = undef;
	if(/^[A-Z][a-z]{2} [A-Z][a-z]{2} [ 1-9][0-9] [0-9]{2}:[0-9]{2}:[0-9]{2} UTC [0-9]{4}$/) {
		$line_type = "date";
	} elsif(/^\+---------+\+$/) {
		$line_type = "entrysep";
	} elsif(/^$/) {
		$line_type = "empty";
	} elsif(/^([^\s]+\/)?\*:  [A-Z][a-z]+.*\.?$/) {
		$line_type = "change_star";
	} elsif(/^([^\s]+\/)?\*:$/) {
		$line_type = "change_star";
		$_ .= "  Upgraded.";
	} elsif(/^([^\s]+\/)?[^\s\/]+-[^\s\/-]+-[^\s\/-]+-[^\s\/-]+\.[^\s\/.-]+:  [A-Z][a-z]+.*\.?$/) {
		$line_type = "change_pkg";
	} elsif(/^([^\s]+\/)?[^\s\/]+:  [A-Z][a-z]+.*\.?$/) {
		$line_type = "change_other";
	} elsif(/^[^\s]+:\s+[A-Z][a-z]+.*\.?$/) {
		$line_type = "change_unknown";
	} elsif(/^\s+.*$/) {
		$line_type = "indented";
	} elsif($cur_state eq "want_change_msg") {

		if(/^([^\s]+\/)?\*$/) {
			$line_type = "change_star";
			$_ .= ":  Upgraded.";
		} elsif(/^([^\s]+\/)?[^\s\/]+-[^\s\/-]+-[^\s\/-]+-[^\s\/-]+\.[^\s\/.-]+$/) {
			$line_type = "change_pkg";
			$_ .= ":  Upgraded.";
		} elsif(/^([^\s]+\/)?[^\s\/]+$/) {
			$line_type = "change_other";
			$_ .= ":  Upgraded.";
		} elsif(/^[^\s]+$/) {
			$line_type = "change_unknown";
			$_ .= ":  Upgraded.";
		} else {
			$line_type = "justified";
		}
	} elsif(/^.*$/) {
		$line_type = "justified";
	}



	if($cur_state eq "want_date" && $line_type eq "date") {
		# this line should be in the date format, or abort
		my $dt = DateTime::Format::Strptime::strptime("%a %b%n%d %T UTC %Y", $_);
		$cur_entry->{timeline} = $_;
		$cur_entry->{isotime} = $dt->datetime()."Z";
		my $ts = $dt->epoch();
		$cur_entry->{timestring} = $_;
		$cur_entry->{timestamp} = $ts;
		$cur_state = "want_overall_msg";

	} elsif($cur_state eq "want_overall_msg" && ($line_type eq "justified" || $line_type eq "indented" || $line_type eq "empty")) {
		$cur_entry->{message} = "" if !defined $cur_entry->{message};
		$cur_entry->{message} .= "$_\n";

	} elsif($cur_state eq "want_change_msg" && ($line_type eq "justified")) {
		$cur_entry->{message} = "" if !defined $cur_entry->{message};
		$cur_entry->{message} .= "[LATER]\n$_\n";
		$cur_state = "want_overall_msg";

	} elsif($cur_state eq "want_change_msg" && ($line_type eq "indented" ||  $line_type eq "empty")) {
		$cur_change->{message} = "" if !defined $cur_change->{message};
		$cur_change->{message} .= "$_\n";

	} elsif($cur_state ne "want_date" && ($line_type eq "change_star" || $line_type eq "change_pkg" || $line_type eq "change_other")) {
		push @{$cur_entry->{changes}}, $cur_change if defined $cur_change;
		$cur_change = {line => $_, linetype => $line_type};
		$cur_state = "want_change_msg";

	} elsif($cur_state ne "want_date" && $line_type eq "entrysep") {
		push @{$cur_entry->{changes}}, $cur_change if defined $cur_change;
		$cur_change = undef;
		unshift @entries, $cur_entry if defined $cur_entry;
		$cur_entry = {changes=>[]};
		$cur_state = "want_date";

	} else {
		die "ERROR: Got an unexpected state/input combination: $cur_state state and $line_type line [$_] ($.) during parsing.\n";
	}	

}

push @{$cur_entry->{changes}}, $cur_change if defined $cur_change;
$cur_change = undef;
unshift @entries, $cur_entry if defined $cur_entry;
$cur_entry = undef;


foreach(@entries) {
	my $e = $_;

	my $oml = 0;
	my $cc = 0;
	my $cc_upgraded = 0;
	my $cc_added = 0;
	my $cc_patched = 0;
	my $cc_removed = 0;
	my $cc_rebuilt = 0;
	my $cc_moved = 0;
	#my $cc_other = 0;

	my $cc_s = 0;
	my $cc_p = 0;
	my $cc_o = 0;

	my $sec = 0;

	$oml = scalar (split /\n/, $e->{message}) if defined $e->{message};

	foreach(@{$e->{changes}}) {
		my $c = $_;

		if(defined $c->{message} && $c->{message} =~ /^  \(\* Security fix \*\)$/m) {
			$c->{securityfix} = 1;
			++$sec;
		}

		if($c->{line} =~ /^([^\s:]+):\s+([A-Z][a-z]+)(\s.*)?\.?$/) {
			$c->{name} = $1;
			$c->{changetype} = lc $2;
			++$cc;
			my $fixme = undef;

			if($c->{changetype} eq "patched") {
				++$cc_patched;
			} elsif($c->{changetype} eq "rebuilt") {
				++$cc_rebuilt;
			} elsif($c->{changetype} eq "removed") {
				++$cc_removed;
			} elsif($c->{changetype} eq "added") {
				++$cc_added;
			} elsif($c->{changetype} eq "upgraded") {
				++$cc_upgraded;
			} elsif($c->{changetype} eq "moved") {
				++$cc_moved;
			} else {
				$fixme = 1;

			#	++$cc_other;
			}

			if($3) {
				$c->{changetypemod} = $3;
				$c->{message} = "" if !defined $c->{message};
				$c->{message} = "  ".(ucfirst $c->{changetype}).$c->{changetypemod}."\n".$c->{message};
			}

			if($fixme) {
				$c->{changetype} = "upgraded";
				delete $c->{changetypemod};
				++$cc_upgraded;
			}
		}

		if($c->{linetype} eq "change_pkg") {
			if($c->{line} =~ /^(?:([^\s]+)\/)?([^\s\/]+)-([^\s\/-]+)-([^\s\/-]+)-([^\s\/-]+)\.([^\s\/.-]+):  [A-Z][a-z]+.*\.?$/) {
				$c->{location} = $1;
				$c->{package} = $2;
				$c->{version} = $3;
				$c->{arch} = $4;
				$c->{build} = $5;
				$c->{ext} = $6;
			} else {
				die "ERROR: While post processing a change_pkg line [$c->{line}], I got confused.\n";
			}
			++$cc_p;
		}

		if($c->{linetype} eq "change_star") {
			++$cc_s;
#			print "\tchange_star:  [$c->{name} $c->{changetype}]\n";
		}

		if($c->{linetype} eq "change_other") {
			++$cc_o;
#			print "\tchange_other: [$c->{name} $c->{changetype}]\n";
		}
	}

	my $split = sprintf("%4dp+%df", $cc_p, $cc_s+$cc_o);
	$split .= " " x (10 - length $split);
	my $adds = $cc_added ? sprintf("++%-3d", $cc_added):"     ";
	my $upgrades = $cc_upgraded ? sprintf("+%-3d", $cc_upgraded):"    ";
	my $patches = $cc_patched ? sprintf("p%-3d", $cc_patched):"    ";
	my $rebuilds = $cc_rebuilt ? sprintf("r%-3d", $cc_rebuilt):"    ";
	my $removes = $cc_removed ? sprintf("--%-3d", $cc_removed):"     ";
	my $moves = $cc_moved ? sprintf("m%-3d", $cc_moved):"    ";
	#my $others = $cc_other ? sprintf("?%-3d", $cc_other):"    ";

	printf("$e->{isotime}: %4d: (%3ds) $split:  $adds $upgrades $patches $rebuilds $moves $removes\n", $cc, $sec, $cc_p, $cc_s + $cc_o);

	my $summat_else = undef;

	if(($display_mode eq "overall" || $display_mode eq "changes" || $display_mode eq "all") && defined $e->{message}) {
		print "\t$_\n" foreach split /\n/, $e->{message};
		$summat_else = 1;
	}

	if($display_mode eq "changes" || $display_mode eq "all") {
		foreach(@{$e->{changes}}) {
			$summat_else = 1;
			my $c = $_;
			print "  $c->{name} $c->{changetype}\n";
			if($display_mode eq "all" && defined $c->{message}) {
				print "\t$_\n" foreach split /\n/, $c->{message};
			}
		}
	}

	print "\n" if $summat_else;
}





exit(0);

