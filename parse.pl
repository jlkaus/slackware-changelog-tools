#!/usr/bin/perl

use strict;
use warnings;
use POSIX;
use Time::Local;
use DateTime;
use DateTime::Format::Strptime;
use Getopt::Long;

# Display modes:
#   No date --no-date
#   Summary line --summary, -s
#   Overall messages --overall, -o
#   Changed Packages  --changes, -c
#   Changed Package details --details, -d
#   Skip empty date blocks (If --date or --summary) --skip-empty
#
# Change Type Filters:
#   No filter (display all types) [DEFAULT]
#   --rebuilds
#   --upgrades
#   --updates
#   --removals
#   --adds
#   --patches
#   --moves
#   --other
# Security Filters:
#   No filter (display security fixes and others) [DEFAULT]
#   --security
#   --non-security
# Package Filters:
#   No filter (display all packages) [DEFAULT]
#   --pkg PACKAGENAME (-p PKGNAME)
# Exclude locations:
#   --exclude-location LOCATION

my $display_date = 1;
my $display_summary = undef;
my $display_overall = undef;
my $display_changes = undef;
my $display_details = undef;
my $skip_empty = undef;

my $include_rebuilds = undef;
my $include_upgrades = undef;
my $include_updates = undef;
my $include_adds = undef;
my $include_removes = undef;
my $include_patches = undef;
my $include_moves = undef;
my $include_other = undef;

my $include_security = undef;
my $include_non_security = undef;

my @package_list = ();
my @location_exclusions = ();

GetOptions('p|pkg=s' => \@package_list,
           'exclude-location=s' => \@location_exclusions,
           'date!' => \$display_date,
           's|summary' => \$display_summary,
           'o|overall' => \$display_overall,
           'c|changes' => \$display_changes,
           'd|details' => \$display_details,
           'skip-empty' => \$skip_empty,
           'rebuilds|rebuilt' => \$include_rebuilds,
           'upgrades|upgraded' => \$include_upgrades,
           'updates|updated' => \$include_updates,
           'adds|added' => \$include_adds,
           'removes|removed' => \$include_removes,
           'patches|patched' => \$include_patches,
           'moves|moved' => \$include_moves,
           'other' => \$include_other,
           'security' => \$include_security,
           'non-security' => \$include_non_security,
    ) or die "Usage: parse.pl [--date] [-s|--summary] [-c|--changes] [-d|--details] [-o|--overall] [--skip-empty] [--rebuilds] [--patches] [--upgrades] [--moves] [--updates] [--adds] [--removes] [--other] [--security] [--non-security] [--pkg PKGNAME]* [--exclude-location LOCATION]*\n";

if(defined $include_security || defined $include_non_security || scalar @package_list || defined $include_rebuilds || defined $include_upgrades || defined $include_updates || defined $include_moves || defined $include_adds || defined $include_removes || defined $include_other || defined $include_patches) {
    $display_changes = 1;
}

if(defined $display_details) {
    $display_changes = 1;
}

if(!defined $include_security && !defined $include_non_security) {
    $include_security = 1;
    $include_non_security = 1;
}

if(!defined $include_rebuilds && !defined $include_upgrades && !defined $include_updates && !defined $include_moves && !defined $include_patches && !defined $include_adds && !defined $include_removes && !defined $include_other) {
    $include_rebuilds = 1;
    $include_upgrades = 1;
    $include_updates = 1;
    $include_adds = 1;
    $include_removes = 1;
    $include_patches = 1;
    $include_other = 1;
}

if(!defined $display_overall && !defined $display_changes && !defined $display_details) {
    $display_summary = 1;
}



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
#       pkg - if this file appears to be an actual package, this is the short name of the package (no version, location, etc) (post)
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
# pkg should be text without spaces or /
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
        $line_type = "date1";
    } elsif(/^[A-Z][a-z]{2} [ 0-9][0-9] [A-Z][a-z]{2} [0-9]{4} [ 0-9]{2}:[0-9]{2}:[0-9]{2}\s+[AP]M UTC$/) {
        $line_type = "date2";
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



    if($cur_state eq "want_date" && ($line_type eq "date1" || $line_type eq "date2")) {
        # this line should be in the date format, or abort
        my $dt = $line_type eq "date1" ?
            DateTime::Format::Strptime::strptime("%a %b%n%d %T UTC %Y", $_) :
            DateTime::Format::Strptime::strptime("%a%n%d %b %Y %I:%M:%S%t%p UTC", $_);
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
            } elsif($c->{changetype} eq "updated") {
                ++$cc_upgraded;
            } else {
                $fixme = 1;
                die "ERROR: Processing $c->{name} found unexpected change type [$c->{changetype}]\n";
                # ++$cc_other;
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
                $c->{pkg} = $2;
                $c->{version} = $3;
                $c->{arch} = $4;
                $c->{build} = $5;
                $c->{ext} = $6;

                $c->{primary_location} = $c->{location};
                $c->{primary_location} =~ s/\/.*$//;
            } else {
                die "ERROR: While post processing a change_pkg line [$c->{line}], I got confused.\n";
            }
            ++$cc_p;
        }

        if($c->{linetype} eq "change_star") {
            ++$cc_s;
            # print "\tchange_star:  [$c->{name} $c->{changetype}]\n";
            my @parts = split /\//, $c->{name};
            $c->{primary_location} = (scalar @parts) > 1 ? $parts[0] : "";
            $c->{pkg} = pop @parts;
            $c->{location} = join('/', @parts);
        }

        if($c->{linetype} eq "change_other") {
            ++$cc_o;
            # print "\tchange_other: [$c->{name} $c->{changetype}]\n";
            my @parts = split /\//, $c->{name};
            $c->{primary_location} = (scalar @parts) > 1 ? $parts[0] : "";
            $c->{pkg} = pop @parts;
            $c->{location} = join('/', @parts);
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
    # my $others = $cc_other ? sprintf("?%-3d", $cc_other):"    ";

    my $first_line = undef;
    my @later_lines = ();

    if($display_date) {
        $first_line = $e->{isotime};
        if($display_summary) {
            $first_line .= ": ";
        }
    }
    if($display_summary) {
        $first_line = "" if !defined $display_date;
        $first_line .= sprintf("%4d: (%3ds) $split:  $adds $upgrades $patches $rebuilds $moves $removes", $cc, $sec);
    }

    my $summat_else = undef;

    if($display_overall && defined $e->{message}) {
        my $prefix = "";
        if($display_date || $display_summary) {
            $prefix =  "\t";
        }
        push @later_lines, "$prefix$_\n" foreach split /\n/, $e->{message};
        $summat_else = 1;
    }

    if($display_changes) {
        my $prefix = "";
        if($display_date || $display_summary) {
            $prefix =  "  ";
        }

        foreach(@{$e->{changes}}) {
            my $c = $_;
            my $candl = undef;
            if($c->{changetype} eq "patched") {
                $candl = $include_patches;
            } elsif($c->{changetype} eq "rebuilt") {
                $candl = $include_rebuilds;
            } elsif($c->{changetype} eq "removed") {
                $candl = $include_removes;
            } elsif($c->{changetype} eq "added") {
                $candl = $include_adds;
            } elsif($c->{changetype} eq "upgraded") {
                $candl = $include_upgrades;
            } elsif($c->{changetype} eq "moved") {
                $candl = $include_moves;
            } elsif($c->{changetype} eq "updated") {
                $candl = $include_updates;
            } else {
                $candl = $include_other;
            }

            if($c->{securityfix}) {
                $candl = $candl && $include_security;
            } else {
                $candl = $candl && $include_non_security;
            }

            if($candl && scalar @package_list) {
                $candl = undef;
                LOOPFIND: foreach(@package_list) {
                    if((defined $c->{pkg} && $_ eq $c->{pkg}) || (!defined $c->{pkg} && $_ eq $c->{name})) {
                        $candl = 1;
                        last LOOPFIND;
                    }
                }
            }

            if($candl && scalar @location_exclusions) {
                LOOPFIND2: foreach(@location_exclusions) {
                    if(defined $c->{primary_location} && $_ eq $c->{primary_location}) {
                        $candl = undef;
                        last LOOPFIND2;
                    }
                }
            }

            if($candl) {
                $summat_else = 1;
                push @later_lines, "$prefix$c->{name} $c->{changetype}";
                if($display_details && defined $c->{message}) {
                    push @later_lines, "$prefix$_" foreach split /\n/, $c->{message};
                }
            }
        }
    }

    if(defined $first_line && defined $skip_empty && scalar @later_lines == 0) {
        # Don't display!
    } else {
        if(defined $first_line) {
            print $first_line;
            print "\n";
        }
        print "$_\n" foreach @later_lines;
        print "\n" if $summat_else && ($display_date || $display_summary);
    }
}





exit(0);

