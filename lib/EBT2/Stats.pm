package EBT2::Stats;

use warnings;
use strict;
use utf8;
use 5.10.0;
use DateTime;
use Date::DayOfWeek;
use List::Util qw/first sum reduce/;
use List::MoreUtils qw/uniq zip/;
use Storable qw/thaw dclone/;
use MIME::Base64;
use EBT2::Util qw/serial_remove_meaningless_figures2/;
use EBT2::Data;
use EBT2::Constants ':all';

## whenever there are changes in any stats format, this has to be increased in order to detect users with old stats formats
our $STATS_VERSION = '20130128-01';
my $chunk_size = '10000n';

sub mean { return sum(@_)/@_; }

sub new {
    my ($class, %args) = @_;

    #my %attrs;
    #$attrs{$_} = delete $args{$_} for qw/foo/;
    #%args and die sprintf 'unrecognized parameters: %s', join ', ', sort keys %args;

    #exists $attrs{'foo'} or die "need a 'foo' parameter";
    #$attrs{'bar'} //= -default_value;

    bless {}, $class;
}

sub count {
    my ($self, $progress, $data) = @_;
    my %ret;

    $ret{'count'} = $data->note_count;

    return \%ret;
}

sub bundle_information {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    my %active_days;
    my $cursor;
    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }

            ## activity
            my $date_entered = (split ' ', $note->[DATE_ENTERED])[0];
            if (!$ret{'activity'}{'first_note'}) {
                $date_entered =~ /^(\d{4})-(\d{2})-(\d{2})$/;
                $cursor = DateTime->new (year => $1, month => $2, day => $3);
                $ret{'activity'}{'first_note'} = {
                    date    => $date_entered,
                    value   => $note->[VALUE],
                    city    => $note->[CITY],
                    country => $note->[COUNTRY],
                    id      => $note->[ID],
                };
            }
            $active_days{$date_entered}++;  ## number of notes

            ## total_value
            $ret{'total_value'} += $note->[VALUE];

            ## signatures
            $ret{'signatures'}{ $note->[SIGNATURE] }++;

            ## days_elapsed
            if (!exists $ret{'days_elapsed'}) {
                my $dt0 = DateTime->new (
                    zip @{[qw/year month day hour minute second/]}, @{[ split /[\s:-]/, $note->[DATE_ENTERED] ]}
                );
                $ret{'days_elapsed'} = DateTime->now->delta_days ($dt0)->delta_days;
            }

            ## notes_dates
            push @{ $ret{'notes_dates'} }, $note->[DATE_ENTERED];

            ## elem_notes_by_president
            $ret{'elem_notes_by_president'} .= $note->[SIGNATURE] . ',';
        }
    }
    chop $ret{'elem_notes_by_president'};

    my $today = DateTime->now->strftime ('%Y-%m-%d');
    my ($this_period_active,   $this_period_active_notes, $active_start_date,   $active_end_date)   = (0, 0, '', '');
    my ($this_period_inactive,                            $inactive_start_date, $inactive_end_date) = (0,    '', '');
    while (1) {
        my $cursor_fmt = $cursor->strftime ('%Y-%m-%d');

        if (exists $active_days{$cursor_fmt}) {
            $ret{'activity'}{'active_days_count'}++;

            ## activity
            $this_period_active++;
            $this_period_active_notes += $active_days{$cursor_fmt};
            $active_start_date ||= $cursor_fmt;
            $active_end_date = $cursor_fmt;

            if (
                !defined $ret{'activity'}{'longest_active_period'} or
                $this_period_active > $ret{'activity'}{'longest_active_period'}
            ) {
                $ret{'activity'}{'longest_active_period'}       = $this_period_active;
                $ret{'activity'}{'longest_active_period_notes'} = $this_period_active_notes;
                $ret{'activity'}{'longest_active_period_from'}  = $active_start_date;
                $ret{'activity'}{'longest_active_period_to'}    = $active_end_date;
            }

            ## inactivity
            $this_period_inactive = 0;
            $inactive_start_date = $inactive_end_date = '';

        } else {
            $ret{'activity'}{'inactive_days_count'}++;

            ## activity
            $this_period_active = 0;
            $this_period_active_notes = 0;
            $active_start_date = $active_end_date = '';

            ## inactivity
            $this_period_inactive++;
            $inactive_start_date ||= $cursor_fmt;
            $inactive_end_date = $cursor_fmt;
            if (
                !defined $ret{'activity'}{'longest_break'} or
                $this_period_inactive > $ret{'activity'}{'longest_break'}
            ) {
                $ret{'activity'}{'longest_break'}      = $this_period_inactive;
                $ret{'activity'}{'longest_break_from'} = $inactive_start_date;
                $ret{'activity'}{'longest_break_to'}   = $inactive_end_date;
            }
        }
        $ret{'activity'}{'total_days_count'}++;

        last if $today eq $cursor_fmt;
        $cursor->add (days => 1);
    }

    $ret{'activity'}{'current_active_period'}       = $this_period_active;
    $ret{'activity'}{'current_active_period_notes'} = $this_period_active_notes;
    $ret{'activity'}{'current_active_period_from'}  = $active_start_date;
    $ret{'activity'}{'current_active_period_to'}    = $active_end_date;
    $ret{'activity'}{'current_break'}               = $this_period_inactive;
    $ret{'activity'}{'current_break_from'}          = $inactive_start_date;
    $ret{'activity'}{'current_break_to'}            = $inactive_end_date;

    return \%ret;
}
sub activity     { goto &bundle_information; }
sub total_value  { goto &bundle_information; }
sub signatures   { goto &bundle_information; }
sub days_elapsed { goto &bundle_information; }
sub notes_dates  { goto &bundle_information; }
sub elem_notes_by_president { goto &bundle_information; }

sub notes_by_value {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }

            ## notes_by_value
            $ret{'notes_by_value'}{ $note->[VALUE] }++;

            ## elem_notes_by_value
            $ret{'elem_notes_by_value'} .= $note->[VALUE] . ',';
        }
    }
    chop $ret{'elem_notes_by_value'};

    return \%ret;
}
sub elem_notes_by_value { goto &notes_by_value; }

sub first_by_value {
    my ($self, $progress, $data) = @_;
    my $at = 0;
    my %ret;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $at++;
            if ($progress and 0 == $at % $EBT2::progress_every) { $progress->set ($at); }

            my %hr2 = zip @{[ COL_NAMES ]}, @$note;
            $ret{'first_by_value'}{ $note->[VALUE] } ||= { %hr2, at => $at };
        }
    }

    return \%ret;
}

sub notes_by_cc {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }
            my $cc = substr $note->[SERIAL], 0, 1;
            $ret{'notes_by_cc'}{$cc}{'total'}++;
            $ret{'notes_by_cc'}{$cc}{ $note->[VALUE] }++;
        }
    }

    return \%ret;
}

sub first_by_cc {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $at = 0;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $at++;
            if ($progress and 0 == $at % $EBT2::progress_every) { $progress->set ($at); }
            my %hr2 = zip @{[ COL_NAMES ]}, @$note;
            my $cc = substr $hr2{'serial'}, 0, 1;
            $ret{'first_by_cc'}{$cc} ||= { %hr2, at => $at };
        }
    }

    return \%ret;
}

sub notes_by_pc {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    while (my $chunk = $data->note_getter (interval => $chunk_size, filter => { year => '2002' })) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }
            my $pc = substr $note->[SHORT_CODE], 0, 1;
            $ret{'notes_by_pc'}{$pc}{'total'}++;
            $ret{'notes_by_pc'}{$pc}{ $note->[VALUE] }++;
        }
    }

    return \%ret;
}

sub first_by_pc {
    my ($self, $progress, $data) = @_;
    my $at = 0;
    my %ret;

    while (my $chunk = $data->note_getter (interval => $chunk_size, filter => { year => '2002' })) {
        foreach my $note (@$chunk) {
            $at++;
            if ($progress and 0 == $at % $EBT2::progress_every) { $progress->set ($at); }
            my %hr2 = zip @{[ COL_NAMES ]}, @$note;
            my $pc = substr $note->[SHORT_CODE], 0, 1;
            $ret{'first_by_pc'}{$pc} ||= { %hr2, at => $at };
        }
    }

    return \%ret;
}

sub bundle_locations {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }
            ## notes_by_country
            $ret{'notes_by_country'}{ $note->[COUNTRY] }{'total'}++;
            $ret{'notes_by_country'}{ $note->[COUNTRY] }{ $note->[VALUE] }++;

            ## notes_by_city
            $ret{'notes_by_city'}{ $note->[COUNTRY] }{ $note->[CITY] }{'first_id'} //= $note->[ID];
            $ret{'notes_by_city'}{ $note->[COUNTRY] }{ $note->[CITY] }{'total'}++;
            $ret{'notes_by_city'}{ $note->[COUNTRY] }{ $note->[CITY] }{ $note->[VALUE] }++;

            ## elem_notes_by_city
            $ret{'elem_notes_by_city'} .= $note->[CITY] . '#';

            ## alphabets
            my $city = $note->[CITY];

            ## some Dutch cities have an abbreviated article at the beginning, ignore it
            if ($city =~ /^'s[- ](.*)/) {
                $city = $1;
            }
            ## ...probably more similar cases to be handled here...

            my $initial = uc substr $city, 0, 1;
            ## removing diacritics is a hard task; let's follow the KISS principle here
            $initial =~ tr/ÁÉÍÓÚÀÈÌÒÙÄËÏÖÜ/AEIOUAEIOUAEIOU/;

            $ret{'alphabets'}{ $note->[COUNTRY] }{$initial}++;

            ## travel_stats
            my $y = substr $note->[DATE_ENTERED], 0, 4;
            my $k = join '#', $note->[COUNTRY], $note->[CITY];
            $ret{'travel_stats'}{$k}{'first_seen'} ||= $note->[DATE_ENTERED];
            $ret{'travel_stats'}{$k}{'total'}++;
            $ret{'travel_stats'}{$k}{'visits'}{$y}++;
            $ret{'travel_stats'}{$k}{'country'} ||= $note->[COUNTRY];
        }
    }

    return \%ret;
}
sub notes_by_country   { goto &bundle_locations; }
sub notes_by_city      { goto &bundle_locations; }
sub elem_notes_by_city { goto &bundle_locations; }
sub alphabets          { goto &bundle_locations; }
sub travel_stats       { goto &bundle_locations; }

sub _alt_zip {
    my ($country, $zip) = @_;
    my $zip2;

    given ($country) {
        when ('mt') { length $zip > 3 and $zip2 = substr $zip, 0, 3; }
        when ('nl') { length $zip > 4 and $zip2 = substr $zip, 0, 4; }
        when ('pl') { $zip2 = (join '', $zip =~ /^(..)-(...)$/)||undef; }
        when ('pt') { length $zip > 4 and $zip2 = substr $zip, 0, 4; }
        when ('uk') { length $zip > 2 and $zip2 = substr $zip, 0, 2; }
        when ('us') { ($zip2) = $zip =~ /(\d{5})/; }
    }
    ## at this point $zip2 should be either something meaningful or undef. It shouldn't be '0', '', '-' or similar rubbish

    return $zip2;
}

sub regions {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    my $populate = sub {
        my ($cfg, $country, $str, $note) = @_;

        foreach my $entry (split /#/, $str) {
            my ($group_idx, $subgroup_idx, $loc_name) = split /,/, $entry, 3;
            my $group_name = $cfg->{'groups'}[$group_idx]{'name'};
            my $num_locs   = $cfg->{'groups'}[$group_idx]{'num_locs'};

            my ($subgroup_name, $flag_url);
            if (defined $cfg->{'subgroups'}[$subgroup_idx]{'name'}) {
                $subgroup_name = $cfg->{'subgroups'}[$subgroup_idx]{'name'};
                $flag_url      = $cfg->{'subgroups'}[$subgroup_idx]{'flag_url'};
            } else {
                ($subgroup_name, $flag_url) = ('__UNDEF__', undef);
            }

            $ret{'regions'}{$country}{$group_name}{'__num_locs'} = $num_locs;   ## this is uselessly done many times
            $ret{'regions'}{$country}{$group_name}{$subgroup_name}{$loc_name} or $ret{'regions'}{$country}{$group_name}{'__seen_locs'}++;
            $ret{'regions'}{$country}{$group_name}{$subgroup_name}{'flag_url'} ||= $flag_url;  ## maybe undef, that's ok
            $ret{'regions'}{$country}{$group_name}{$subgroup_name}{$loc_name}{'num_notes'}++;
            $ret{'regions'}{$country}{$group_name}{$subgroup_name}{$loc_name}{'id'} ||= $note->[ID];
        }
    };

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }

            my $matched = 0;
            my $country = $note->[COUNTRY];
            my $cfg = $EBT2::config{'regions'}{$country};
            my $city = $note->[CITY];
            my $zip = $note->[ZIP]; $zip =~ s/\s//g;
            my $zip2 = _alt_zip $country, $zip;

            my $str;
            if    (                  $zip  =~ /^\d+$/ and $str = $cfg->{'ranges'}[$zip])  { $matched = 1; $populate->($cfg, $country, $str, $note); }
            elsif (defined $zip2 and $zip2 =~ /^\d+$/ and $str = $cfg->{'ranges'}[$zip2]) { $matched = 1; $populate->($cfg, $country, $str, $note); }

            if    (                  $str = $cfg->{'zip_map'}{$zip})                      { $matched = 1; $populate->($cfg, $country, $str, $note); }
            elsif (defined $zip2 and $str = $cfg->{'zip_map'}{$zip2})                     { $matched = 1; $populate->($cfg, $country, $str, $note); }

            if    (                  $str = $cfg->{'specific'}{$zip}{$city})              { $matched = 1; $populate->($cfg, $country, $str, $note); }
            elsif (defined $zip2 and $str = $cfg->{'specific'}{$zip2}{$city})             { $matched = 1; $populate->($cfg, $country, $str, $note); }

            if    (                  $str = $cfg->{'specific'}{$city})                    { $matched = 1; $populate->($cfg, $country, $str, $note); }

            $matched or $ret{'hit_regions'}{$country}{'__unmatched'}{$zip} = undef;
        }
    }

    return \%ret;
}

sub huge_table {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }
            next if $note->[ERRORS];
            my $plate = substr $note->[SHORT_CODE], 0, 4;
            my $serial = serial_remove_meaningless_figures2 $note->[YEAR], $note->[VALUE], $note->[SHORT_CODE], $note->[SERIAL];
            my $num_stars = $serial =~ tr/*/*/;
            $serial = substr $serial, 0, 4+$num_stars;

            $ret{'huge_table'}{$plate}{ $note->[VALUE] }{$serial}{'count'}++;
            $ret{'huge_table'}{$plate}{ $note->[VALUE] }{$serial}{'recent'} = $note->[RECENT];  ## since @$chunk is ordered, we'll get the latest value
            #$ret{'huge_table'}{$plate}{ $note->[VALUE] }{$serial}{'last_id'} = $note->[ID];
        }
    }

    return \%ret;
}

sub fooest_short_codes {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }
            next if $note->[ERRORS];
            my %hr2 = zip @{[ COL_NAMES ]}, @$note;
            my $pc = substr $note->[SHORT_CODE], 0, 1;
            my $serial = serial_remove_meaningless_figures2 $note->[YEAR], $note->[VALUE], $note->[SHORT_CODE], $note->[SERIAL];
            my $num_stars = $serial =~ tr/*/*/;
            $serial = substr $serial, 0, 4+$num_stars;
            my $sort_key = sprintf '%s%s', $note->[SHORT_CODE], $serial;

            foreach my $value ('all', $note->[VALUE]) {
                foreach my $param (
                    [ -1, 'lowest_short_codes' ],
                    [ 1, 'highest_short_codes' ],
                ) {
                    my ($cmp_key, $hash_key) = @$param;
                    if (!exists $ret{$hash_key}{$pc}{$value}) {
                        $ret{$hash_key}{$pc}{$value} = { %hr2, sort_key => $sort_key };
                    } else {
                        if ($cmp_key == ($sort_key cmp $ret{$hash_key}{$pc}{$value}{'sort_key'})) {
                            $ret{$hash_key}{$pc}{$value} = { %hr2, sort_key => $sort_key };
                        }
                    }
                }
            }
        }
    }

    return \%ret;
}
sub lowest_short_codes  { goto &fooest_short_codes; }
sub highest_short_codes { goto &fooest_short_codes; }

sub _serial_niceness {
    my ($serial) = @_;
    my $prev_digit;
    my @consecutives;
    my %digits_present;

    my $idx = 0;
    foreach my $digit (split //, $serial) {
        $digits_present{$digit} = 1;

        if (!defined $prev_digit or $digit != $prev_digit) {
            push @consecutives, { key => $digit, start => $idx, length => 1 };
        } else {
            $consecutives[-1]{'length'}++;
        }

        $prev_digit = $digit;
        $idx++;
    }
    ## not the same as the preferred 'reverse sort { $a <=> $b }' due to repeated elements
    @consecutives = sort { $b->{'length'} <=> $a->{'length'} } @consecutives;

    my $longest = $consecutives[0]{'length'};
    my $product = reduce { $a * $b } map { $_->{'length'} } @consecutives;
    my $different_digits = keys %digits_present;

    ## this initial algorithm was devised in 10 minutes. There are probably better alternatives
    my $niceness =
        1000000 * (11 - @consecutives) +
        10000   * $longest +
        100     * (11 - $different_digits) +
        1       * $product;

    my $visible_serial = $serial;
    my $repl_char = 'A';
    my %chars_changed;
    foreach my $elem (grep { 1 != $_->{'length'} } @consecutives) {
        next if $chars_changed{ $elem->{'key'} }++;
        $visible_serial =~ s/$elem->{'key'}/$repl_char/g;
        #substr $visible_serial, $elem->{'start'}, $elem->{'length'}, $repl_char x $elem->{'length'};
        $repl_char++;
    }
    $visible_serial =~ s/[0-9]/*/g;

    return $niceness, $longest, $different_digits, $visible_serial;
}

sub nice_serials {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx;
    my $num_elems = 10;
    my @nicest;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }

            my %hr2 = zip @{[ COL_NAMES ]}, @$note;
            my ($score, $longest, $different_digits, $visible_serial) = _serial_niceness substr $note->[SERIAL], 1;
            if (@nicest < $num_elems or $score > $nicest[-1]{'score'}) {
                ## this is a quicksort on an almost sorted list, I read
                ## quicksort coughs on that so let's see how this performs
                @nicest = reverse sort {
                    $a->{'score'} <=> $b->{'score'}
                } @nicest, {
                    %hr2,
                    score          => $score,
                    visible_serial => "*$visible_serial",
                };
                @nicest >= $num_elems and splice @nicest, $num_elems;
            }
            $longest > 1 and $ret{'numbers_in_a_row'}{$longest}++;
            $ret{'different_digits'}{$different_digits}++;
        }
    }
    $ret{'nice_serials'} = \@nicest;

    return \%ret;
}
sub numbers_in_a_row { goto &nice_serials; }
sub different_digits { goto &nice_serials; }

sub coords_bingo {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }
            next if $note->[ERRORS];
            my $coords = substr $note->[SHORT_CODE], 4, 2;
            $ret{'coords_bingo'}{ $note->[VALUE] }{$coords}++;
            $ret{'coords_bingo'}{ 'all' }{$coords}++;
        }
    }

    return \%ret;
}

sub bundle_time {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }

            my ($y, $m, $d, $H, $M, $S) = map { sprintf '%02d', $_ } split /[\s:-]/, $note->[DATE_ENTERED];
            ## notes_per_year
            #my $y = substr $note->[DATE_ENTERED], 0, 4;
            $ret{'notes_per_year'}{$y}{'total'}++;
            $ret{'notes_per_year'}{$y}{ $note->[VALUE] }++;

            ## notes_per_month
            my $ym = substr $note->[DATE_ENTERED], 0, 7;
            $ret{'notes_per_month'}{$ym}{'total'}++;
            $ret{'notes_per_month'}{$ym}{ $note->[VALUE] }++;

            ## top10days
            my $ymd = substr $note->[DATE_ENTERED], 0, 10;
            $ret{'top10days'}{$ymd}{'total'}++;
            $ret{'top10days'}{$ymd}{ $note->[VALUE] }++;

            ## top10months
            $ret{'top10months'}{$ym}{'total'}++;
            $ret{'top10months'}{$ym}{ $note->[VALUE] }++;

            ## time_analysis
            #my ($y, $m, $d, $H, $M, $S) = map { sprintf '%02d', $_ } split /[\s:-]/, $note->[DATE_ENTERED];
            my $dow = $note->[DOW];
            $ret{'time_analysis'}{'cal'}{$m}{$d}++;
            $ret{'time_analysis'}{'hh'}{$H}++;
            $ret{'time_analysis'}{'mm'}{$M}++;
            $ret{'time_analysis'}{'ss'}{$S}++;
            $ret{'time_analysis'}{'hhmm'}{$H}{$M}++;
            $ret{'time_analysis'}{'mmss'}{$M}{$S}++;
            $ret{'time_analysis'}{'hhmmss'}{$H}{$M}{$S}++;
            $ret{'time_analysis'}{'dow'}{$dow}++;    ## XXX: this partially replaces notes_by_dow below
            $ret{'time_analysis'}{'dowhh'}{$dow}{$H}++;
            $ret{'time_analysis'}{'dowhhmm'}{$dow}{$H}{$M}++;

            ## notes_by_dow
            #my ($Y, $m, $d) = (split /[\s:-]/, $note->[DATE_ENTERED])[0..2];
            #my $dow = 1 + dayofweek $d, $m, $Y;
            $ret{'notes_by_dow'}{$dow}{'total'}++;
            $ret{'notes_by_dow'}{$dow}{ $note->[VALUE] }++;
        }
    }

    ## postfix: top10days (keep the 10 highest and delete the other ones)
    my @sorted_days = sort {
        $ret{'top10days'}{$b}{'total'} <=> $ret{'top10days'}{$a}{'total'} ||
        $b cmp $a
    } keys %{ $ret{'top10days'} };
    delete @{ $ret{'top10days'}  }{ @sorted_days[10..$#sorted_days] };

    ## postfix: top10months (keep the 10 highest and delete the other ones)
    my @sorted_months = sort {
        $ret{'top10months'}{$b}{'total'} <=> $ret{'top10months'}{$a}{'total'} ||
        $b cmp $a
    } keys %{ $ret{'top10months'} };
    delete @{ $ret{'top10months'}  }{ @sorted_months[10..$#sorted_months] };

    return \%ret;
}
sub notes_per_year  { goto &bundle_time; }
sub notes_per_month { goto &bundle_time; }
sub top10days       { goto &bundle_time; }
sub top10months     { goto &bundle_time; }
sub time_analysis   { goto &bundle_time; }
sub notes_by_dow    { goto &bundle_time; }

## module should calculate combs at the finest granularity (value*cc*plate*sig), it is up to the app to aggregate the pieces
## 20120406: no, that should be here, to prevent different apps from performing the same work
sub missing_combs_and_history {
    my ($self, $progress, $data) = @_;
    my %ret;

    my $num_note = 0;
    my $hist_idx = 0;
    my @history;
    my %combs = %{ \%EBT2::combs_pc_cc_val };
    my %sigs;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $num_note++;
            if ($progress and 0 == $num_note % $EBT2::progress_every) { $progress->set ($num_note); }

            next if $note->[ERRORS];

            my $p = substr $note->[SHORT_CODE], 0, 1;
            my $c = substr $note->[SERIAL], 0, 1;
            my $v = $note->[VALUE];
            my $s = (split ' ', $note->[SIGNATURE])[0];

            my $k = sprintf '%s%s%03d', $p, $c, $v;
            if (!$combs{$k}) {
                push @history, {
                    index   => ++$hist_idx,
                    pname   => EBT2->printers ($p),
                    cname   => EBT2->countries ($c),
                    pc      => $p,
                    cc      => $c,
                    value   => $note->[VALUE],
                    num     => $num_note,
                    date    => (split ' ', $note->[DATE_ENTERED])[0],
                    city    => $note->[CITY],
                    country => $note->[COUNTRY],
                };
            }
            $combs{$k}++;
            $sigs{$s}{$k}++;
        }
    }

    ## gather missing combinations
    my %missing_pcv;
    my %entirely_missing_pairs;
    my $num_total_combs = my $num_missing_combs = 0;
    foreach my $k (sort keys %combs) {
        $num_total_combs++;

        my $at_least_one_value = 0;
        foreach my $value (sort { $a <=> $b } map { substr $_, 2 } $k) {
            if ($combs{$k}) {
                $at_least_one_value = 1;
                next;
            }
            $num_missing_combs++;
            $missing_pcv{$k} = 1;
        }
        $entirely_missing_pairs{$k} = 0 + !$at_least_one_value;
    }

    $ret{'missing_combs_and_history'}{'entirely_missing_pairs'} = keys %entirely_missing_pairs;
    $ret{'missing_combs_and_history'}{'num_total_combs'} = $num_total_combs;
    $ret{'missing_combs_and_history'}{'num_missing_combs'} = $num_missing_combs;
    $ret{'missing_combs_and_history'}{'missing_pcv'} = \%missing_pcv;
    $ret{'missing_combs_and_history'}{'history'} = \@history;
    $ret{'missing_combs_and_history'}{'sigs'} = \%sigs;

    return \%ret;
}

sub notes_by_combination {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }

            next if $note->[ERRORS];
            my $comb1 = sprintf '%s%s',   (substr $note->[SHORT_CODE], 0, 1), (substr $note->[SERIAL], 0, 1);
            #my $comb2 = sprintf '%s%s%s', (substr $note->[SHORT_CODE], 0, 1), (substr $note->[SERIAL], 0, 1), $note->[VALUE];
            my ($sig) = $note->[SIGNATURE] =~ /^(\w+)/ or next;

            $ret{'notes_by_combination'}{'any'}{$comb1}{'total'}++;
            $ret{'notes_by_combination'}{'any'}{$comb1}{ $note->[VALUE] }{'count'}++;
            $ret{'notes_by_combination'}{'any'}{$comb1}{ $note->[VALUE] }{'last_id'} = $note->[ID];
            #$ret{'notes_by_combination_with_value'}{'any'}{$comb2}{ $note->[VALUE] }++;

            $ret{'notes_by_combination'}{$sig}{$comb1}{'total'}++;
            $ret{'notes_by_combination'}{$sig}{$comb1}{ $note->[VALUE] }{'count'}++;
            $ret{'notes_by_combination'}{$sig}{$comb1}{ $note->[VALUE] }{'last_id'} = $note->[ID];
            #$ret{'notes_by_combination_with_value'}{$sig}{$comb2}{ $note->[VALUE] }++;
        }
    }

    return \%ret;
}

sub plate_bingo {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    ## prepare
    foreach my $v (keys %{ $EBT2::config{'sigs'} }) {
        foreach my $cc (keys %{ $EBT2::config{'sigs'}{$v} }) { 
            foreach my $plate (keys %{ $EBT2::config{'sigs'}{$v}{$cc} }) { 
                $ret{'plate_bingo'}{$v}{$plate}{'count'} = 0;
                $ret{'plate_bingo'}{'all'}{$plate}{'count'} = 0;
            }    
        }    
    }

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }

            next if $note->[ERRORS];
            my $plate = substr $note->[SHORT_CODE], 0, 4;
            $ret{'plate_bingo'}{ $note->[VALUE] }{$plate}{'count'}++;
            $ret{'plate_bingo'}{ $note->[VALUE] }{$plate}{'last_id'} = $note->[ID];
            $ret{'plate_bingo'}{ 'all' }{$plate}{'count'}++;
            $ret{'plate_bingo'}{ 'all' }{$plate}{'last_id'} = $note->[ID];
        }
    }

    return \%ret;
}

sub bad_notes {
    my ($self, $progress, $data) = @_;
    my %ret;
    my $idx = 0;

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }

            if ($note->[ERRORS]) {
                my %hr2 = zip @{[ COL_NAMES ]}, @$note;
                push @{ $ret{'bad_notes'} }, {
                    %hr2,
                    errors => [ split ';', decode_base64 $note->[ERRORS] ],
                };
            }
        }
    }

    return \%ret;
}

sub hit_list {
    my ($self, $progress, $data, $whoami) = @_;
    my %ret;
    my $idx = 0;

    my %hit_list;
    my %passive_pending;    ## passive hits info is filled later. We save them here in the meanwhile
    my $pp_changed;         ## if %passive_pending is unchanged, we skip a sort operation
    my @pas_hits;           ## result of the sort, we don't touch it unless $pp_changed

    my $note_no = 0;
    my $notes_elapsed = 0;
    my $hit_no = 0;   ## only interesting
    my $hit_no2 = 0;  ## including moderated
    my $notes_between = -1;
    my $prev_hit_dt;

    my $fill_passive_pending = sub {
        my ($note) = @_;

        if ($pp_changed) {
            @pas_hits = sort { $a->{'hit_date'} cmp $b->{'hit_date'} } values %passive_pending;
            $pp_changed = 0;
        }

        ## this $note is earlier than the earliest hit_date in %pas_hits. Don't enter the loop as it will do nothing
        return if $note and 1 != ($note->[DATE_ENTERED] cmp $pas_hits[0]{'hit_date'});

        my @pas2remove;
        foreach my $pas_hit (@pas_hits) {
            if ($note) { next if 1 != ($note->[DATE_ENTERED] cmp $pas_hit->{'hit_date'}); }
            push @pas2remove, $pas_hit->{'serial'};

            $pas_hit->{'moderated'} or $hit_no++;
            $hit_no2++;

            if (!$pas_hit->{'moderated'}) {
                $pas_hit->{'hit_no'} = $hit_no;
                $pas_hit->{'hit_no2'} = $hit_no2;
                $pas_hit->{'notes'} = $notes_elapsed-1;
                $pas_hit->{'old_hit_ratio'} = ($hit_no > 1 ? ($notes_elapsed-1)/($hit_no-1) : undef);
                $pas_hit->{'new_hit_ratio'} = ($notes_elapsed-1)/$hit_no;
                $pas_hit->{'notes_between'} = $notes_between;
                $pas_hit->{'days_between'}  = DateTime->new (
                    zip @{[qw/year month day hour minute second/]}, @{[ split /[\s:-]/, $pas_hit->{'hit_date'} ]}
                )->delta_days ($prev_hit_dt)->delta_days;
                $pas_hit->{'days_between'}-- if $pas_hit->{'days_between'};
                $prev_hit_dt = DateTime->new (
                    zip @{[qw/year month day hour minute second/]}, @{[ split /[\s:-]/, $pas_hit->{'hit_date'} ]}
                );

                push @{ $ret{'hits_dates'} }, $pas_hit->{'hit_date'};
                $ret{'elem_travel_days'} .= $pas_hit->{'days'} . ',';
                $ret{'elem_travel_km'} .= $pas_hit->{'km'} . ',';
                push @{ $ret{'elem_ratio'} }, sprintf '%s=%05s=%s', $pas_hit->{'hit_date'}, $hit_no2, $pas_hit->{'new_hit_ratio'}//0;
                $notes_between = 0;     ## 0 because it would be -1 plus 1 for having already started another loop iteration
            }
        }
        if (@pas2remove) {
            delete @passive_pending{@pas2remove};
            $pp_changed = 1;
        }
    };

    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }

            $notes_between++;
            $notes_elapsed++;
            my $hit = $note->[HIT] ? thaw decode_base64 $note->[HIT] : undef;
            if (1 == $note->[NOTE_NO]) {
                my $base_date = $hit ? $hit->{'hit_date'} : $note->[DATE_ENTERED];
                $prev_hit_dt = DateTime->new (
                    zip @{[qw/year month day hour minute second/]}, @{[ split /[\s:-]/, $base_date ]}
                );
            }

            ## if current note is more recent than any pending passive hits, then they have just occurred. Fill their data in
            if (%passive_pending) { $fill_passive_pending->($note); }

            ## this ratio is incorrect if this is an active interesting hit, we'll change it later
            push @{ $ret{'elem_ratio'} }, sprintf '%s=%05s=%s', $note->[DATE_ENTERED], $hit_no2, $hit_no ? $notes_elapsed/$hit_no : 0;

            next unless $hit;

            my $active = $whoami->{'id'} eq $hit->{'parts'}[-1]{'user_id'};
            my $passive = !$active;

            if ($active) {
                $hit->{'moderated'} or $hit_no++;
                $hit_no2++;
            }
            my $entry = {
                hit_no          => ($hit->{'moderated'} ? undef : $hit_no),
                hit_no2         => $hit_no2,
                dates           => [ map { $_->{'date_entered'} } @{ $hit->{'parts'} } ],
                hit_date        => $hit->{'hit_date'},
                dow             => $hit->{'dow'},
                value           => $note->[VALUE],
                serial          => $note->[SERIAL],
                short_code      => $note->[SHORT_CODE],
                id              => $note->[ID],
                countries       => [ map { $_->{'country'} } @{ $hit->{'parts'} } ],
                cities          => [ map { $_->{'city'} } @{ $hit->{'parts'} } ],
                zips            => [ map { $_->{'zip'} } @{ $hit->{'parts'} } ],
                km              => $hit->{'tot_km'},
                days            => $hit->{'tot_days'},
                hit_partners    => [ map { $_->{'user_name'} } @{ $hit->{'parts'} } ],
                hit_partner_ids => [ map { $_->{'user_id'} } @{ $hit->{'parts'} } ],
                note_no         => $note->[NOTE_NO],
                moderated       => $hit->{'moderated'},
            };
            if (!$hit->{'moderated'} and $active) {
                $entry->{'notes'} = $notes_elapsed;

                $entry->{'old_hit_ratio'} = ($hit_no > 1 ? ($notes_elapsed-1)/($hit_no-1) : undef);
                $entry->{'new_hit_ratio'} = $notes_elapsed/$hit_no;

                $entry->{'notes_between'} = $notes_between;
                $notes_between = -1;

                $entry->{'days_between'}  = DateTime->new (
                    zip @{[qw/year month day hour minute second/]}, @{[ split /[\s:-]/, $hit->{'hit_date'} ]}
                )->delta_days ($prev_hit_dt)->delta_days;
                $entry->{'days_between'}-- if $entry->{'days_between'};
                $prev_hit_dt = DateTime->new (
                    zip @{[qw/year month day hour minute second/]}, @{[ split /[\s:-]/, $hit->{'hit_date'} ]}
                );

                ## hits_dates
                push @{ $ret{'hits_dates'} }, $hit->{'hit_date'};

                ## elem_travel_days
                $ret{'elem_travel_days'} .= $entry->{'days'} . ',';

                ## elem_travel_km
                $ret{'elem_travel_km'} .= $entry->{'km'} . ',';

                ## elem_ratio, replace last value
                $ret{'elem_ratio'}[-1] = sprintf '%s=%05s=%s', $entry->{'hit_date'}, $hit_no2, $entry->{'new_hit_ratio'}//0;
            }
            push @{ $hit_list{ $hit->{'hit_date'} } }, $entry;
            if ($passive) {
                $passive_pending{ $note->[SERIAL] } = $hit_list{ $hit->{'hit_date'} }[-1];
                $pp_changed = 1;
            }
        }
    }

    ## passive hits could occur after the last note in the database. Take care of them
    if (%passive_pending) { $fill_passive_pending->(); }

    foreach my $date (sort keys %hit_list) {
        push @{ $ret{'hit_list'} }, sort { $a->{'hit_no2'} <=> $b->{'hit_no2'} } @{ $hit_list{$date} };
    }
    if (!defined $ret{'hits_dates'}) {
        $ret{'hit_list'} = [];
        $ret{'hits_dates'} = [];
        $ret{'elem_travel_days'} = '';
        $ret{'elem_travel_km'} = '';
        $ret{'elem_ratio'} = [];
    } else {
        ## triple hits can cause the list to be unsorted. TODO: test case. I found about this with a hit "someone -> giulcenc -> someone"
        @{ $ret{'hits_dates'} } = sort @{ $ret{'hits_dates'} };
        chop $ret{'elem_travel_days'};
        chop $ret{'elem_travel_km'};
        $ret{'elem_ratio'} = [ sort @{ $ret{'elem_ratio'} } ];
    }

    return \%ret;
}
sub hits_dates       { goto &hit_list; }
sub elem_ratio       { goto &hit_list; }
sub elem_travel_days { goto &hit_list; }
sub elem_travel_km   { goto &hit_list; }

sub hit_times {
    my ($self, $progress, $data, $hit_list) = @_;
    my %ret;

    foreach my $hit (@$hit_list) {
        next if $hit->{'moderated'};

        my ($y, $m, $d, $H, $M, $S) = map { sprintf '%02d', $_ } split /[\s:-]/, $hit->{'hit_date'};
        my $dow = $hit->{'dow'};
        $ret{'hit_times'}{'cal'}{$m}{$d}++;
        $ret{'hit_times'}{'hh'}{$H}++;
        $ret{'hit_times'}{'mm'}{$M}++;
        $ret{'hit_times'}{'ss'}{$S}++;
        $ret{'hit_times'}{'hhmm'}{$H}{$M}++;
        $ret{'hit_times'}{'mmss'}{$M}{$S}++;
        $ret{'hit_times'}{'hhmmss'}{$H}{$M}{$S}++;
        $ret{'hit_times'}{'dow'}{$dow}++;
        $ret{'hit_times'}{'dowhh'}{$dow}{$H}++;
        $ret{'hit_times'}{'dowhhmm'}{$dow}{$H}{$M}++;
    }

    return \%ret;
}

sub hit_regions {
    my ($self, $progress, $data, $whoami, $hit_list) = @_;
    my %ret;
    my $idx = 0;

    my $populate = sub {
        my ($cfg, $country, $partner, $mine, $str, $hit) = @_;

        foreach my $entry (split /#/, $str) {
            my ($group_idx, $subgroup_idx, $loc_name) = split /,/, $entry, 3;
            my $group_name = $cfg->{'groups'}[$group_idx]{'name'};
            my $num_locs   = $cfg->{'groups'}[$group_idx]{'num_locs'};

            my ($subgroup_name, $flag_url);
            if (defined $cfg->{'subgroups'}[$subgroup_idx]{'name'}) {
                $subgroup_name = $cfg->{'subgroups'}[$subgroup_idx]{'name'};
                $flag_url      = $cfg->{'subgroups'}[$subgroup_idx]{'flag_url'};
            } else {
                ($subgroup_name, $flag_url) = ('__UNDEF__', undef);
            }

            $ret{'hit_regions'}{$country}{$group_name}{'__num_locs'} = $num_locs;   ## this is uselessly done many times
            $ret{'hit_regions'}{$country}{$group_name}{$subgroup_name}{$loc_name} or $ret{'hit_regions'}{$country}{$group_name}{'__seen_locs'}++;
            $ret{'hit_regions'}{$country}{$group_name}{$subgroup_name}{'flag_url'} ||= $flag_url;  ## maybe undef, that's ok
            if ($mine) {
                $ret{'hit_regions'}{$country}{$group_name}{$subgroup_name}{$loc_name}{'our_side'}{ $hit->{'serial'} } = undef;
            } else {
                $ret{'hit_regions'}{$country}{$group_name}{$subgroup_name}{$loc_name}{'their_side'}{ $hit->{'serial'} } = undef;
                $ret{'hit_regions'}{$country}{$group_name}{$subgroup_name}{$loc_name}{'partners'}{ $partner } = undef;
            }
            $ret{'hit_regions'}{$country}{$group_name}{$subgroup_name}{$loc_name}{'id'} ||= $hit->{'id'};
        }
    };

    foreach my $hit (@$hit_list) {
        next if $hit->{'moderated'};
        foreach my $idx (0..$#{ $hit->{'dates'} }) {
            my $country = $hit->{'countries'}[$idx];
            my $cfg = $EBT2::config{'regions'}{$country};
            my $city = $hit->{'cities'}[$idx];
            my $partner = $hit->{'hit_partners'}[$idx];
            my $mine = $partner eq $whoami->{'name'};
            my $zip = $hit->{'zips'}[$idx]; $zip =~ s/\s//g;
            my $zip2 = _alt_zip $country, $zip;

            my $str;
            if    (                  $zip  =~ /^\d+$/ and $str = $cfg->{'ranges'}[$zip])  { $populate->($cfg, $country, $partner, $mine, $str, $hit); }
            elsif (defined $zip2 and $zip2 =~ /^\d+$/ and $str = $cfg->{'ranges'}[$zip2]) { $populate->($cfg, $country, $partner, $mine, $str, $hit); }

            if    (                  $str = $cfg->{'zip_map'}{$zip})                      { $populate->($cfg, $country, $partner, $mine, $str, $hit); }
            elsif (defined $zip2 and $str = $cfg->{'zip_map'}{$zip2})                     { $populate->($cfg, $country, $partner, $mine, $str, $hit); }

            if    (                  $str = $cfg->{'specific'}{$zip}{$city})              { $populate->($cfg, $country, $partner, $mine, $str, $hit); }
            elsif (defined $zip2 and $str = $cfg->{'specific'}{$zip2}{$city})             { $populate->($cfg, $country, $partner, $mine, $str, $hit); }

            if    (                  $str = $cfg->{'specific'}{$city})                    { $populate->($cfg, $country, $partner, $mine, $str, $hit); }
        }
    }

    return \%ret;
}

sub hit_analysis {
    my ($self, $progress, $data, $hit_list) = @_;
    my %ret;
    my $idx = 0;

    my %notes_per_day;
    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }

            my $date = (split ' ', $note->[DATE_ENTERED])[0];
            my $hit = $note->[HIT] ? thaw decode_base64 $note->[HIT] : undef;
            if (defined $hit) {
                if ($hit->{'moderated'}) {
                    undef $hit;
                } else {
                    $hit = first { $_->{'serial'} eq $hit->{'serial'} } @$hit_list;   ## grep within a loop, expensive?
                }
            }
            push @{ $notes_per_day{$date}{'notes'} }, $hit;
        }
    }

    ## post process %notes_per_day
    foreach my $date (keys %notes_per_day) {
        $notes_per_day{$date}{'date'} = $date;
        $notes_per_day{$date}{'num_notes'} = scalar @{ $notes_per_day{$date}{'notes'} };
        $notes_per_day{$date}{'hits'} = [ grep defined, @{ $notes_per_day{$date}{'notes'} } ];
        $notes_per_day{$date}{'num_hits'} = scalar @{ $notes_per_day{$date}{'hits'} };
        $notes_per_day{$date}{'ratio'} = $notes_per_day{$date}{'num_hits'} ? $notes_per_day{$date}{'num_notes'} / $notes_per_day{$date}{'num_hits'} : 0;
        delete $notes_per_day{$date}{'notes'};
    }

    ## build lucky_bundles and other_hit_potential
    foreach my $date (keys %notes_per_day) {
        my $num_hits = $notes_per_day{$date}{'num_hits'};
        next unless $num_hits;

        push @{ $ret{'hit_analysis'}{'other_hit_potential'} }, $notes_per_day{$date};
        if ($num_hits >= 2) {
            push @{ $ret{'hit_analysis'}{'lucky_bundles'} }, $notes_per_day{$date};
        }
    }
    $ret{'hit_analysis'}{'lucky_bundles'} ||= [];
    $ret{'hit_analysis'}{'other_hit_potential'} ||= [];

    ## sort lucky_bundles and other_hit_potential
    $ret{'hit_analysis'}{'lucky_bundles'} = [ sort {
        #$a->{'num_hits'}  <=> $b->{'num_hits'} or $a->{'num_notes'} <=> $b->{'num_notes'}
        $a->{'ratio'} <=> $b->{'ratio'}
    } @{ $ret{'hit_analysis'}{'lucky_bundles'} } ];
    $ret{'hit_analysis'}{'other_hit_potential'} = [ reverse sort {
        $a->{'ratio'} <=> $b->{'ratio'}
    } @{ $ret{'hit_analysis'}{'other_hit_potential'} } ];

    ## longest km/days
    foreach my $what (
        [ qw/longest km/ ],
        [ qw/oldest days/ ],
    ) {
        my ($key1, $key2) = @$what;
        $ret{'hit_analysis'}{$key1} = [
            grep defined,
            (
                reverse sort { $a->{$key2} <=> $b->{$key2} }
                grep { !$_->{'moderated'} }
                @$hit_list
            )[0..9]
        ];
    }

    return \%ret;
}

sub hit_summary {
    my ($self, $progress, $data, $whoami, $activity, $count, $hit_list) = @_;
    my %ret;
    my $last_hit;

    $ret{'hit_summary'}{'active'} = 0;
    $ret{'hit_summary'}{'passive'} = 0;

    foreach my $hit (@$hit_list) {
        ## total, national, international, moderated
        if ($hit->{'moderated'}) {
            $ret{'hit_summary'}{'moderated'}++;
            next;
        }
        $last_hit = $hit;
        $ret{'hit_summary'}{'total'}++;
        if (1 == @{[ uniq @{ $hit->{'countries'} } ]}) {
            $ret{'hit_summary'}{'national'}++;
        } else {
            $ret{'hit_summary'}{'international'}++;
        }

        ## normal, triple, quad, pent
        my $k = sprintf '%dway', scalar @{ $hit->{'dates'} };
        $ret{'hit_summary'}{$k}++;

        ## best/current/worst ratio
        if ($hit->{'new_hit_ratio'} < ($ret{'hit_summary'}{'ratio'}{'best'} // ~0)) {
            $ret{'hit_summary'}{'ratio'}{'best'} = $hit->{'new_hit_ratio'};
        }
        if (($hit->{'old_hit_ratio'} // 0) > ($ret{'hit_summary'}{'ratio'}{'worst'} // 0)) {
            $ret{'hit_summary'}{'ratio'}{'worst'} = $hit->{'old_hit_ratio'};
        }

        ## finder/maker - giver/getter
        if ($whoami->{'name'} eq $hit->{'hit_partners'}[0]) {
            $ret{'hit_summary'}{'passive'}++;
        } else {
            $ret{'hit_summary'}{'active'}++;
        }
        ## XXX: in the case of "someone -> you -> someone", it counts only as active

        ## notes between/days between best/avg/cur/worst (notes avg == hit ratio), days forecast
        foreach my $what (qw/notes days/) {
            my $k = "${what}_between";

            if ($hit->{$k} < ($ret{'hit_summary'}{$k}{'best'} // ~0)) {
                $ret{'hit_summary'}{$k}{'best'} = $hit->{$k};
            }
            if ($hit->{$k} > ($ret{'hit_summary'}{$k}{'worst'} // 0)) {
                $ret{'hit_summary'}{$k}{'worst'} = $hit->{$k};
            }
            push @{ $ret{'hit_summary'}{$k}{'elems'} }, $hit->{$k};
        }

        ## min/avg/max of $hit->{'days'} and $hit->{'km'}, speed too
        foreach my $what (qw/days km/) {
            if ($hit->{$what} < ($ret{'hit_summary'}{$what}{'min'} // ~0)) {
                $ret{'hit_summary'}{$what}{'min'} = $hit->{$what};
            }
            if ($hit->{$what} > ($ret{'hit_summary'}{$what}{'max'} // 0)) {
                $ret{'hit_summary'}{$what}{'max'} = $hit->{$what};
            }
            push @{ $ret{'hit_summary'}{$what}{'elems'} }, $hit->{$what};
        }
        my $speed = $hit->{'days'} ? $hit->{'km'} / $hit->{'days'} : 0;
        if ($speed < ($ret{'hit_summary'}{'speed'}{'min'} // ~0)) {
            $ret{'hit_summary'}{'speed'}{'min'} = $speed;
        }
        if ($speed > ($ret{'hit_summary'}{'speed'}{'max'} // 0)) {
            $ret{'hit_summary'}{'speed'}{'max'} = $speed;
        }
        push @{ $ret{'hit_summary'}{'speed'}{'elems'} }, $speed;

        ## TODO: charts of the above

        ## total hit/hitless days
        my $hd = (split ' ', $hit->{'hit_date'})[0];
        $ret{'hit_summary'}{'hit_dates'}{$hd} = 1;

        ## current/longest period of consecutive hit/hitless days

        ## list of consecutive hit days

        ## TODO: hit ratio/avg travel days/avg km, by value

        ## hits by combination
        my $pc = substr $hit->{'short_code'}, 0, 1;
        my $cc = substr $hit->{'serial'}, 0, 1;
        my $combo = "$pc/$cc";
        $ret{'hit_summary'}{'hits_by_combo'}{$combo} = {
            pc => $pc,
            cc => $cc,
            count => ($ret{'hit_summary'}{'hits_by_combo'}{$combo}{'count'} // 0) + 1,
        };

        ## frequent hit partner (min: 2 hits)
        map { $ret{'hit_summary'}{'partners'}{$_}++ } @{ $hit->{'hit_partners'} };

        ## TODO: hits with top 200 users

        ## hit with same km and days
        if ($hit->{'days'} != 0 and $hit->{'days'} == $hit->{'km'}) {
            $ret{'hit_summary'}{'equal_km_days'}{ $hit->{'km'} }++;
        }
    }
    my ($y, $m, $d);

    ## postfix: best/current/worst ratio (calculate current hit ratio)
    $ret{'hit_summary'}{'ratio'}{'current'} = $ret{'hit_summary'}{'total'} ? ($count / $ret{'hit_summary'}{'total'}) : undef;

    ## postfix: notes between/days between best/avg/cur/worst (notes avg == hit ratio), days forecast (cur/avg days/notes, days forecast)
    if ($ret{'hit_summary'}{'total'}) {
        ($y, $m, $d) = $last_hit->{'dates'}[-1] =~ /^(\d{4})-(\d{2})-(\d{2})/;
        my $last_hit_date = DateTime->new (year => $y, month => $m, day => $d);
        $ret{'hit_summary'}{'days_between'}{'current'} = $last_hit_date->delta_days (DateTime->now)->delta_days;
        $ret{'hit_summary'}{'notes_between'}{'current'} = $count - ($last_hit->{'notes'}//0);
        $ret{'hit_summary'}{'days_between'}{'avg'}  = mean @{ $ret{'hit_summary'}{'days_between'}{'elems'} };
        $ret{'hit_summary'}{'notes_between'}{'avg'} = mean @{ $ret{'hit_summary'}{'notes_between'}{'elems'} };
        $ret{'hit_summary'}{'days_forecast'} = $last_hit_date->add (days => $ret{'hit_summary'}{'days_between'}{'avg'})->strftime ('%Y-%m-%d');
    } else {
        $ret{'hit_summary'}{'days_between'}{'current'} = undef;
        $ret{'hit_summary'}{'notes_between'}{'current'} = undef;
        $ret{'hit_summary'}{'days_between'}{'avg'}  = undef;
        $ret{'hit_summary'}{'notes_between'}{'avg'} = undef;
        $ret{'hit_summary'}{'days_forecast'} = undef;
    }

    ## postfix: min/avg/max of $hit->{'days'} and $hit->{'km'}, speed too (calculate averages)
    if ($ret{'hit_summary'}{'total'}) {
        $ret{'hit_summary'}{'days'}{'avg'}  = mean @{ $ret{'hit_summary'}{'days'}{'elems'} };
        $ret{'hit_summary'}{'km'}{'avg'}    = mean @{ $ret{'hit_summary'}{'km'}{'elems'} };
        $ret{'hit_summary'}{'speed'}{'avg'} = mean @{ $ret{'hit_summary'}{'speed'}{'elems'} };
    } else {
        $ret{'hit_summary'}{'days'}{'avg'}  = undef;
        $ret{'hit_summary'}{'km'}{'avg'}    = undef;
        $ret{'hit_summary'}{'speed'}{'avg'} = undef;
    }
    delete $ret{'hit_summary'}{'days'}{'elems'};
    delete $ret{'hit_summary'}{'km'}{'elems'};
    delete $ret{'hit_summary'}{'speed'}{'elems'};

    ## postfix: total hit/hitless days
    ## postfix: current/longest period of consecutive hit/hitless days
    ## postfix: list of consecutive hit days
    ($y, $m, $d) = $activity->{'first_note'}{'date'} =~ /^(\d{4})-(\d{2})-(\d{2})/;
    my $dt = DateTime->new (year => $y, month => $m, day => $d);
    my $now = DateTime->now;
    $ret{'hit_summary'}{'hit_dates'}{'consecutive'}{'hist'} = [ { len => 0 } ];
    $ret{'hit_summary'}{'hit_dates'}{'consecutive'}{'longest'} = {};
    my $cons = $ret{'hit_summary'}{'hit_dates'}{'consecutive'};  ## abbreviation
    while (1) {
        last if $dt > $now;
        my $str = $dt->strftime ('%Y-%m-%d');
        if (!exists $ret{'hit_summary'}{'hit_dates'}{$str}) {
            $ret{'hit_summary'}{'hit_dates'}{$str} = 0;
            exists $cons->{'hist'}[-1]{'start'} and push @{ $cons->{'hist'} }, { len => 0 };
        } else {
            $cons->{'hist'}[-1]{'start'} //= $str;
            $cons->{'hist'}[-1]{'end'} = $str;
            $cons->{'hist'}[-1]{'len'}++;
        }
        if (($cons->{'hist'}[-1]{'len'} // 0) > ($cons->{'longest'}{'len'} // 0)) {
            $cons->{'longest'} = $cons->{'hist'}[-1];
        }
        $dt->add (days => 1);
    }
    $ret{'hit_summary'}{'hit_days'}{'total'}     = grep { 1 == $ret{'hit_summary'}{'hit_dates'}{$_} } keys %{ $ret{'hit_summary'}{'hit_dates'} };
    $ret{'hit_summary'}{'hitless_days'}{'total'} = grep { 0 == $ret{'hit_summary'}{'hit_dates'}{$_} } keys %{ $ret{'hit_summary'}{'hit_dates'} };
    $ret{'hit_summary'}{'total_days'} = scalar keys %{ $ret{'hit_summary'}{'hit_dates'} };

    ## postfix: frequent hit partner (min: 2 hits) (remove myself, build data structure)
    if ($ret{'hit_summary'}{'total'}) {
        delete $ret{'hit_summary'}{'partners'}{ $whoami->{'name'} };
        foreach my $p (keys %{ $ret{'hit_summary'}{'partners'} }) {
            next if 1 == $ret{'hit_summary'}{'partners'}{$p};
            $ret{'hit_summary'}{'freq_partners'}{$p} = {
                partner => $p,
                hits    => $ret{'hit_summary'}{'partners'}{$p},
            };
        }
        delete $ret{'hit_summary'}{'partners'};
    }

    return \%ret;
}

sub calendar {
    my ($self, $progress, $data) = @_;
    my %ret;
    my %calendar_data;
    my %total_notes;
    my $total_amount; my $total_amount_target = 10e3;
    my @hits;
    my $idx = 0;

    my $cursor;
    while (my $chunk = $data->note_getter (interval => $chunk_size)) {
        foreach my $note (@$chunk) {
            $idx++;
            if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx); }
            my $date_entered = (split ' ', $note->[DATE_ENTERED])[0];

            $calendar_data{$date_entered}{'num_notes'}++;
            $calendar_data{$date_entered}{'amount'} += $note->[VALUE];
            push @{ $calendar_data{$date_entered}{'countries'} }, $note->[COUNTRY];

            $total_notes{'all'}++;
            $total_notes{ $note->[VALUE] }++;
            foreach my $value ('all', $note->[VALUE]) {
                if (
                    0 == $total_notes{$value} % 1000 or
                    ($total_notes{$value} < 1000 and 0 == $total_notes{$value} % 100)
                ) {
                    ## if the 1000th and 2000th note is entered on the same day, let the 2000th overwrite the 1000th
                    $calendar_data{$date_entered}{'events'}{'notes'}{$value} = { total => $total_notes{$value}, id => $note->[ID] };
                }
            }

            $total_amount += $note->[VALUE];
            if ($total_amount >= $total_amount_target) {
                $calendar_data{$date_entered}{'events'}{'amount'} = { total => $total_amount_target, id => $note->[ID] };
                if ($total_amount_target < 100e3) {
                    $total_amount_target += 10e3;
                } else {
                    $total_amount_target += 100e3;
                }
            }

            if (my $hit = $note->[HIT] ? thaw decode_base64 $note->[HIT] : undef) {
                if (!$hit->{'moderated'}) {
                    my $date = (split ' ', $hit->{'hit_date'})[0];
                    $calendar_data{$date}{'num_hits'}++;
                    push @hits, {
                        date => $date,
                        id => $note->[ID],
                    };
                }
            }

            if (!$cursor) {
                $date_entered =~ /^(\d{4})-(\d{2})-(\d{2})$/;
                $cursor ||= DateTime->new (year => $1, month => $2, day => $3);
                $calendar_data{$date_entered}{'events'}{'first_day'} = 1;
            }
        }
    }

    my $total_hits;
    foreach my $hit (sort { $a->{'date'} cmp $b->{'date'} } @hits) {
        $total_hits++;
        if (0 == $total_hits % 10 or $total_hits < 10) {
            $calendar_data{ $hit->{'date'} }{'events'}{'hits'} = { total => $total_hits, id => $hit->{'id'} };
        }
    }

    my $cursor_copy = dclone $cursor;
    $cursor->set_day (1);
    my $end = DateTime->now->add (months => 3)->set_day (1)->subtract (days => 1)->strftime ('%Y-%m-%d');
    while (1) {
        my $cursor_fmt = $cursor->strftime ('%Y-%m-%d');
        my ($y, $m, $d) = split '-', $cursor_fmt;
        my $cursor_dow = dayofweek $d, $m, $y; $cursor_dow = 1 + ($cursor_dow-1) % 7;

        if (exists $calendar_data{$cursor_fmt}) {
            my $cd = $calendar_data{"$y-$m-$d"};
            $ret{'calendar'}{$y}{$m}{'days'}{$d} = {
                countries => [ uniq @{ $cd->{'countries'} } ],
                num_notes => $cd->{'num_notes'},
                amount    => $cd->{'amount'},
                num_hits  => $cd->{'num_hits'},
                events    => $cd->{'events'},
            };
        }
        $ret{'calendar'}{$y}{$m}{'days'}{$d}{'dow'} = $cursor_dow;

        last if $end eq $cursor_fmt;
        $cursor->add (days => 1);
    }

    $cursor = (dclone $cursor_copy)->subtract (days => 1);
    my $days_added;
    while (1) {
        $cursor->add (days => 100);
        $days_added += 100;

        my $cursor_fmt = $cursor->strftime ('%Y-%m-%d');
        my ($y, $m, $d) = split '-', $cursor_fmt;

        last if !exists $ret{'calendar'}{$y} or !exists $ret{'calendar'}{$y}{$m};
        $ret{'calendar'}{$y}{$m}{'days'}{$d}{'events'}{'100th_days'} = { days => $days_added };
    }

    $cursor = (dclone $cursor_copy);
    my $years_added;
    while (1) {
        $cursor->add (years => 1);
        $years_added++;

        my $cursor_fmt = $cursor->strftime ('%Y-%m-%d');
        my ($y, $m, $d) = split '-', $cursor_fmt;

        last if !exists $ret{'calendar'}{$y} or !exists $ret{'calendar'}{$y}{$m};
        $ret{'calendar'}{$y}{$m}{'days'}{$d}{'events'}{'anniversary'} = { years => $years_added };
    }

    return \%ret;
}

1;

__END__

sub palindrome_serials {
    my ($self) = @_;
    $self->{'palindrome_serials7'} = {};
    $self->{'palindrome_serials8'} = {};
    $self->{'palindrome_serials9'} = {};
    $self->{'palindrome_serials10'} = {};

    #return $self if $self->{'palindrome_serials'};  ## if already done

    my $iter = $self->note_getter (one_result_aref => 0, one_result_full_data => 0);
    while (my $hr = $iter->()) {
        my $num = substr $hr->{'serial'}, 1, -1;
        if ($num =~ /^ (.)(.)(.)(.)(.) \5\4\3\2\1 /x) {
            $self->{'palindrome_serials10'}{'total'}++;
            $self->{'palindrome_serials10'}{ $hr->{'value'} }++;
        } elsif ($num =~ / (.)(.)(.)(.) . \4\3\2\1 /x) {
            $self->{'palindrome_serials9'}{'total'}++;
            $self->{'palindrome_serials9'}{ $hr->{'value'} }++;
        } elsif ($num =~ / (.)(.)(.)(.) \4\3\2\1 /x) {
            $self->{'palindrome_serials8'}{'total'}++;
            $self->{'palindrome_serials8'}{ $hr->{'value'} }++;
        } elsif ($num =~ / (.)(.)(.) . \3\2\1 /x) {
            $self->{'palindrome_serials7'}{'total'}++;
            $self->{'palindrome_serials7'}{ $hr->{'value'} }++;
        }
    }

    foreach my $v ('total', @values) {
        $self->{'palindrome_serials'}{$v} =
            ($self->{'palindrome_serials7'}{$v}//0) +
            ($self->{'palindrome_serials8'}{$v}//0) +
            ($self->{'palindrome_serials9'}{$v}//0) +
            ($self->{'palindrome_serials10'}{$v}//0);
        delete $self->{'palindrome_serials'}{$v} if !$self->{'palindrome_serials'}{$v};
    }

    return $self;
}
sub palindrome_serials7 { goto &palindrome_serials; }
sub palindrome_serials8 { goto &palindrome_serials; }
sub palindrome_serials9 { goto &palindrome_serials; }
sub palindrome_serials10 { goto &palindrome_serials; }

my $primes_hash;
sub primes_init { -f $primes_file and $primes_hash = retrieve $primes_file; }
sub is_prime {
    my ($number) = @_;

    return $primes_hash->{$number}     if exists $primes_hash->{$number};
    return $primes_hash->{$number} = 0 unless $number % 2;

    my ($div, $sqrt) = (3, sqrt $number);
    while (1) {
        return $primes_hash->{$number} = 0 unless $number % $div;
        return $primes_hash->{$number} = 1 if $div >= $sqrt;
        $div += 2;
    }
}
sub primes_end { store $primes_hash, $primes_file; }

sub prime_serials {
    my ($self) = @_;
    $self->{'prime_serials'} = {};

    #return $self if $self->{'prime_serials'};  ## if already done

    primes_init;
    my $iter = $self->note_getter (one_result_aref => 0, one_result_full_data => 0);
    while (my $hr = $iter->()) {
        my $num = substr $hr->{'serial'}, 1, -1;
        if (is_prime $num) {
            $self->{'prime_serials'}{'total'}++;
            $self->{'prime_serials'}{ $hr->{'value'} }++;
        }
    }
    primes_end;

    return $self;
}

sub square_serials {
    my ($self) = @_;
    $self->{'square_serials'} = {};

    #return $self if $self->{'square_serials'};  ## if already done

    my $iter = $self->note_getter (one_result_aref => 0, one_result_full_data => 0);
    while (my $hr = $iter->()) {
        my $num = substr $hr->{'serial'}, 1, -1;
        if (sqrt $num == int sqrt $num) {
            $self->{'square_serials'}{'total'}++;
            $self->{'square_serials'}{ $hr->{'value'} }++;
        }
    }

    return $self;
}

sub rare_notes {
    my ($self) = @_;

    #return $self if $self->{'rare_notes'};  ## if already done

    my $iter = $self->note_getter (one_result_aref => 0, one_result_full_data => 0);
    while (my $hr = $iter->()) {
        my $cc = substr $hr->{'serial'}, 0, 1;
        my $pc = substr $hr->{'short_code'}, 0, 1;
        my $plate = substr $hr->{'short_code'}, 0, 4;
        my $v  = $hr->{'value'};
        my $comb1 = "$pc$cc";
        my $comb2 = sprintf '%s%s%03d', $pc, $cc, $v;
        my $comb3 = sprintf '%s%s%03d', $plate, $cc, $v;

        ## cdiffs: country diffs
        ## pdiffs: printer diffs
        ## comb1diffs: combination diffs
        ## comb2diffs: combination (including value) diffs
        ## comb3diffs: combination (including value and plate) diffs
        ##
        ## "diff": gap between two notes that have the same country/printer/comb1/comb2/comb3 (as in "34 notes between a G/F and the next")
        ## "cur": current

        ## push only to the proper place (the current note's cc, pc and combs)
        push @{ $self->{'rare_notes'}{'cdiffs'}{$cc} },        defined $self->{'rare_notes'}{'ccur_diff'}{$cc}        ? $self->{'rare_notes'}{'ccur_diff'}{$cc}        : 0;
        push @{ $self->{'rare_notes'}{'pdiffs'}{$pc} },        defined $self->{'rare_notes'}{'pcur_diff'}{$pc}        ? $self->{'rare_notes'}{'pcur_diff'}{$pc}        : 0;
        push @{ $self->{'rare_notes'}{'comb1diffs'}{$comb1} }, defined $self->{'rare_notes'}{'comb1cur_diff'}{$comb1} ? $self->{'rare_notes'}{'comb1cur_diff'}{$comb1} : 0;
        push @{ $self->{'rare_notes'}{'comb2diffs'}{$comb2} }, defined $self->{'rare_notes'}{'comb2cur_diff'}{$comb2} ? $self->{'rare_notes'}{'comb2cur_diff'}{$comb2} : 0;
        push @{ $self->{'rare_notes'}{'comb3diffs'}{$comb3} }, defined $self->{'rare_notes'}{'comb3cur_diff'}{$comb3} ? $self->{'rare_notes'}{'comb3cur_diff'}{$comb3} : 0;

        ## increase all current diffs for cc's, pc's and combs, as if they all weren't seen
        foreach my $k (keys %{EBT->countries }) { $self->{'rare_notes'}{'ccur_diff'}{$k}++; }
        foreach my $k (keys %{EBT->printers })  { $self->{'rare_notes'}{'pcur_diff'}{$k}++; }
        foreach my $k (keys %combs1)            { $self->{'rare_notes'}{'comb1cur_diff'}{$k}++; }
        foreach my $k (keys %combs2)            { $self->{'rare_notes'}{'comb2cur_diff'}{$k}++; }
        foreach my $k (keys %combs3)            { $self->{'rare_notes'}{'comb3cur_diff'}{$k}++; }

        ## except for the ones we've just seen, for which we reset the diff (overwrite the previous increase)
        $self->{'rare_notes'}{'ccur_diff'}{$cc}        = 0;
        $self->{'rare_notes'}{'pcur_diff'}{$pc}        = 0;
        $self->{'rare_notes'}{'comb1cur_diff'}{$comb1} = 0;
        $self->{'rare_notes'}{'comb2cur_diff'}{$comb2} = 0;
        $self->{'rare_notes'}{'comb3cur_diff'}{$comb3} = 0;
    }

    foreach my $cc (keys %{ EBT->countries }) {
        push @{ $self->{'rare_notes'}{'cdiffs'}{$cc} }, $self->{'rare_notes'}{'ccur_diff'}{$cc};
        $self->{'rare_notes'}{'diff_counts'}{'c'}{$cc} = @{ $self->{'rare_notes'}{'cdiffs'}{$cc} };

        my $sum = sum @{ $self->{'rare_notes'}{'cdiffs'}{$cc} };
        my $mean = sprintf '%.0f', $sum/@{ $self->{'rare_notes'}{'cdiffs'}{$cc} };
        $self->{'rare_notes'}{'remaining_days'}{'c'}{$cc} = $mean - $self->{'rare_notes'}{'ccur_diff'}{$cc};
    }
    foreach my $pc (keys %{ EBT->printers }) {
        push @{ $self->{'rare_notes'}{'pdiffs'}{$pc} }, $self->{'rare_notes'}{'pcur_diff'}{$pc};
        $self->{'rare_notes'}{'diff_counts'}{'p'}{$pc} = @{ $self->{'rare_notes'}{'pdiffs'}{$pc} };

        my $sum = sum @{ $self->{'rare_notes'}{'pdiffs'}{$pc} };
        my $mean = sprintf '%.0f', $sum/@{ $self->{'rare_notes'}{'pdiffs'}{$pc} };
        $self->{'rare_notes'}{'remaining_days'}{'p'}{$pc} = $mean - $self->{'rare_notes'}{'pcur_diff'}{$pc};
    }
    foreach my $comb1 (keys %combs1) {
        push @{ $self->{'rare_notes'}{'comb1diffs'}{$comb1} }, $self->{'rare_notes'}{'comb1cur_diff'}{$comb1};
        $self->{'rare_notes'}{'diff_counts'}{'comb1'}{$comb1} = @{ $self->{'rare_notes'}{'comb1diffs'}{$comb1} };

        my $sum = sum @{ $self->{'rare_notes'}{'comb1diffs'}{$comb1} };
        my $mean = sprintf '%.0f', $sum/@{ $self->{'rare_notes'}{'comb1diffs'}{$comb1} };
        $self->{'rare_notes'}{'remaining_days'}{'comb1'}{$comb1} = $mean - $self->{'rare_notes'}{'comb1cur_diff'}{$comb1};
    }
    foreach my $comb2 (keys %combs2) {
        push @{ $self->{'rare_notes'}{'comb2diffs'}{$comb2} }, $self->{'rare_notes'}{'comb2cur_diff'}{$comb2};
        $self->{'rare_notes'}{'diff_counts'}{'comb2'}{$comb2} = @{ $self->{'rare_notes'}{'comb2diffs'}{$comb2} };

        my $sum = sum @{ $self->{'rare_notes'}{'comb2diffs'}{$comb2} };
        my $mean = sprintf '%.0f', $sum/@{ $self->{'rare_notes'}{'comb2diffs'}{$comb2} };
        $self->{'rare_notes'}{'remaining_days'}{'comb2'}{$comb2} = $mean - $self->{'rare_notes'}{'comb2cur_diff'}{$comb2};
    }
    foreach my $comb3 (keys %combs3) {
        push @{ $self->{'rare_notes'}{'comb3diffs'}{$comb3} }, $self->{'rare_notes'}{'comb3cur_diff'}{$comb3};
        $self->{'rare_notes'}{'diff_counts'}{'comb3'}{$comb3} = @{ $self->{'rare_notes'}{'comb3diffs'}{$comb3} };

        my $sum = sum @{ $self->{'rare_notes'}{'comb3diffs'}{$comb3} };
        my $mean = sprintf '%.0f', $sum/@{ $self->{'rare_notes'}{'comb3diffs'}{$comb3} };
        $self->{'rare_notes'}{'remaining_days'}{'comb3'}{$comb3} = $mean - $self->{'rare_notes'}{'comb3cur_diff'}{$comb3};
    }

    return $self;
}
