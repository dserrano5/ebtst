package EBT2::Stats;

use warnings;
use strict;
use utf8;
use DateTime;
use Date::DayOfWeek;
use List::Util qw/sum reduce/;
use List::MoreUtils qw/zip/;
use EBT2::Data;
use EBT2::NoteValidator;

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

sub activity {
    my ($self, $data) = @_;
    my %ret;

    my %active_days;
    my $cursor;
    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $date_entered = (split ' ', $hr->{'date_entered'})[0];
        if (!$ret{'activity'}{'first_note'}) {
            $date_entered =~ /^(\d{4})-(\d{2})-(\d{2})$/;
            $cursor = DateTime->new (year => $1, month => $2, day => $3);
            $ret{'activity'}{'first_note'} = {
                date    => $cursor->strftime ('%Y-%m-%d'),
                value   => $hr->{'value'},
                city    => $hr->{'city'},
                country => $hr->{'country'},
            };
        }
        $active_days{$date_entered}++;  ## number of notes
    }

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

=pod

sub count {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        $ret{'count'}++;
        $ret{'total_value'} += $hr->{'value'};
        $ret{'signatures'}{ $hr->{'signature'} }++;
    }

    return \%ret;
}
sub total_value { goto &count; }
sub signatures  { goto &count; }

sub days_elapsed {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    my $date = $iter->()->{'date_entered'};
    my $dt0 = DateTime->new (
        zip @{[qw/year month day hour minute second/]}, @{[ split /[\s:-]/, $date ]}
    );
    $ret{'days_elapsed'} = DateTime->now->delta_days ($dt0)->delta_days;

    return \%ret;
}

sub notes_by_value {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        $ret{'notes_by_value'}{ $hr->{'value'} }++;
    }

    return \%ret;
}

sub notes_by_cc {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $cc = substr $hr->{'serial'}, 0, 1;
        $ret{'notes_by_cc'}{$cc}{'total'}++;
        $ret{'notes_by_cc'}{$cc}{ $hr->{'value'} }++;
    }

    return \%ret;
}

sub first_by_cc {
    my ($self, $data) = @_;
    my %ret;
    my $at = 0;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        $at++;
        my $cc = substr $hr->{'serial'}, 0, 1;
        next if exists $ret{'first_by_cc'}{$cc};
        $ret{'first_by_cc'}{$cc} = { %$hr, at => $at };
    }

    return \%ret;
}

sub notes_by_country {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        $ret{'notes_by_country'}{ $hr->{'country'} }{'total'}++;
        $ret{'notes_by_country'}{ $hr->{'country'} }{ $hr->{'value'} }++;
    }

    return \%ret;
}

sub notes_by_city {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        $ret{'notes_by_city'}{ $hr->{'country'} }{ $hr->{'city'} }{'total'}++;
        $ret{'notes_by_city'}{ $hr->{'country'} }{ $hr->{'city'} }{ $hr->{'value'} }++;
    }

    return \%ret;
}

sub notes_by_pc {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $pc = substr $hr->{'short_code'}, 0, 1;
        $ret{'notes_by_pc'}{$pc}{'total'}++;
        $ret{'notes_by_pc'}{$pc}{ $hr->{'value'} }++;
    }

    return \%ret;
}

sub first_by_pc {
    my ($self, $data) = @_;
    my $at = 0;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        $at++;
        my $pc = substr $hr->{'short_code'}, 0, 1;
        next if exists $ret{'first_by_pc'}{$pc};
        $ret{'first_by_pc'}{$pc} = { %$hr, at => $at };
    }

    return \%ret;
}

sub huge_table {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $plate = substr $hr->{'short_code'}, 0, 4;
        my $serial = EBT2::Data::serial_remove_meaningless_figures2 $hr->{'short_code'}, $hr->{'serial'};
        my $num_stars = $serial =~ tr/*/*/;
        $serial = substr $serial, 0, 4+$num_stars;

        $ret{'huge_table'}{$plate}{ $hr->{'value'} }{$serial}{'count'}++;
    }

    return \%ret;
}

sub alphabets {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $city = $hr->{'city'};

        ## some Dutch cities have an abbreviated article at the beginning, ignore it
        if ($city =~ /^'s[- ](.*)/) {
            $city = $1;
        }
        ## probably more to do here

        my $initial = uc substr $city, 0, 1;
        $ret{'alphabets'}{ $hr->{'country'} }{$initial}++;
    }

    return \%ret;
}

sub fooest_short_codes {
    my ($self, $data, $cmp_key, $hash_key) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $pc = substr $hr->{'short_code'}, 0, 1;
        my $serial = EBT2::Data::serial_remove_meaningless_figures2 $hr->{'short_code'}, $hr->{'serial'};
        $serial =~ s/^([A-Z]\**\d{3}).*$/$1/;
        my $sort_key = sprintf '%s%s', $hr->{'short_code'}, $serial;

        for my $value ('all', $hr->{'value'}) {
            if (!exists $ret{$hash_key}{$pc}{$value}) {
                $ret{$hash_key}{$pc}{$value} = { %$hr, sort_key => $sort_key };
            } else {
                if ($cmp_key == ($sort_key cmp $ret{$hash_key}{$pc}{$value}{'sort_key'})) {
                    $ret{$hash_key}{$pc}{$value} = { %$hr, sort_key => $sort_key };
                }
            }
        }
    }

    return \%ret;
}

sub lowest_short_codes {
    my ($self, $data) = @_;

    return $self->fooest_short_codes ($data, -1, 'lowest_short_codes');
}

sub highest_short_codes {
    my ($self, $data) = @_;

    return $self->fooest_short_codes ($data, 1, 'highest_short_codes');
}

=cut

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
    foreach my $elem (grep { 1 != $_->{'length'} } @consecutives) {
        $visible_serial =~ s/$elem->{'key'}/$repl_char/g;
        #substr $visible_serial, $elem->{'start'}, $elem->{'length'}, $repl_char x $elem->{'length'};
        $repl_char++;
    }
    $visible_serial =~ s/[0-9]/*/g;

    return $niceness, $longest, $visible_serial;
}

sub nice_serials {
    my ($self, $data) = @_;
    my %ret;
    my $num_elems = 10;
    my @nicest;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my ($score, $longest, $visible_serial) = _serial_niceness substr $hr->{'serial'}, 1;
        if (@nicest < $num_elems or $score > $nicest[-1]{'score'}) {
            ## this is a quicksort on an almost sorted list, I read
            ## quicksort coughs on that so let's see how this performs
            @nicest = reverse sort {
                $a->{'score'} <=> $b->{'score'}
            } @nicest, {
                %$hr,
                score          => $score,
                visible_serial => "*$visible_serial",
            };
            @nicest >= $num_elems and splice @nicest, $num_elems;
        }
        $longest > 1 and $ret{'numbers_in_a_row'}{$longest}++;
    }
    $ret{'nice_serials'} = \@nicest;

    return \%ret;
}
sub numbers_in_a_row { goto &nice_serials; }

=pod

sub coords_bingo {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $coords = substr $hr->{'short_code'}, 4, 2;
        $ret{'coords_bingo'}{ $hr->{'value'} }{$coords}++;
        $ret{'coords_bingo'}{ 'all' }{$coords}++;
    }

    return \%ret;
}

sub notes_per_year {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $y = substr $hr->{'date_entered'}, 0, 4;
        $ret{'notes_per_year'}{$y}{'total'}++;
        $ret{'notes_per_year'}{$y}{ $hr->{'value'} }++;
        #push @{ $ret{'avgs_by_year'}{$y} }, $hr->{'value'};
    }

    ## compute the average value of notes
    #foreach my $year (keys %{ $ret{'avgs_by_year'} }) {
    #    $ret{'avgs_by_year'}{$year} = mean @{ $ret{'avgs_by_year'}{$year} };
    #}

    return \%ret;
}
#sub avgs_by_year { goto &notes_per_year; }

sub notes_per_month {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $m = substr $hr->{'date_entered'}, 0, 7;
        $ret{'notes_per_month'}{$m}{'total'}++;
        $ret{'notes_per_month'}{$m}{ $hr->{'value'} }++;
        #push @{ $ret{'avgs_by_month'}{$m} }, $hr->{'value'};
    }

    ## compute the average value of notes
    #foreach my $month (keys %{ $ret{'avgs_by_month'} }) {
    #    $ret{'avgs_by_month'}{$month} = mean @{ $ret{'avgs_by_month'}{$month} };
    #}

    return \%ret;
}
#sub avgs_by_month { goto &notes_per_month; }

sub top10days {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $d = substr $hr->{'date_entered'}, 0, 10;
        $ret{'top10days'}{$d}{'total'}++;
        $ret{'top10days'}{$d}{ $hr->{'value'} }++;
        #push @{ $ret{'avgs_top10'}{$d} }, $hr->{'value'};
    }

    ## keep the 10 highest (delete the other ones)
    my @sorted_days = sort {
        $ret{'top10days'}{$b}{'total'} <=> $ret{'top10days'}{$a}{'total'} ||
        $b cmp $a
    } keys %{ $ret{'top10days'} };
    delete @{ $ret{'top10days'}  }{ @sorted_days[10..$#sorted_days] };
    #delete @{ $ret{'avgs_top10'} }{ @sorted_days[10..$#sorted_days] };

    ## compute the average value of notes
    #foreach my $d (keys %{ $ret{'top10days'} }) {
    #    $ret{'avgs_top10'}{$d} = mean @{ $ret{'avgs_top10'}{$d} };
    #}

    return \%ret;
}
sub avgs_top10 { goto &top10days; }

sub time_analysis {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my ($y, $m, $d, $H, $M, $S) = map { sprintf '%02d', $_ } split /[\s:-]/, $hr->{'date_entered'};
        my $dow = 1 + dayofweek $d, $m, $y;
        $ret{'time_analysis'}{'hh'}{$H}++;
        $ret{'time_analysis'}{'mm'}{$M}++;
        $ret{'time_analysis'}{'ss'}{$S}++;
        $ret{'time_analysis'}{'hhmm'}{$H}{$M}++;
        $ret{'time_analysis'}{'mmss'}{$M}{$S}++;
        $ret{'time_analysis'}{'hhmmss'}{$H}{$M}{$S}++;
        $ret{'time_analysis'}{'dow'}{$dow}++;    ## XXX: this partially replaces notes_by_dow below
        $ret{'time_analysis'}{'dowhh'}{$dow}{$H}++;
        $ret{'time_analysis'}{'dowhhmm'}{$dow}{$H}{$M}++;
    }

    return \%ret;
}

sub notes_by_dow {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my ($Y, $m, $d) = (split /[\s:-]/, $hr->{'date_entered'})[0..2];
        my $dow = 1 + dayofweek $d, $m, $Y;
        $ret{'notes_by_dow'}{$dow}{'total'}++;
        $ret{'notes_by_dow'}{$dow}{ $hr->{'value'} }++;
    }

    return \%ret;
}

=cut

## module should calculate combs at the finest granularity (value*cc*plate*sig), it is up to the app to aggregate the pieces
## 20120406: no, that should be here, to prevent different apps from performing the same work
sub missing_combs_and_history {
    my ($self, $data) = @_;
    my %ret;

    my $num_note = 0;
    my $hist_idx = 0;
    my @history;
    my %combs = %{ \%EBT2::combs_pc_cc_val };
    my %sigs;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        $num_note++;
        next if $hr->{'invalid'};

        my $p = substr $hr->{'short_code'}, 0, 1;
        my $c = substr $hr->{'serial'}, 0, 1;
        my $v = $hr->{'value'};
        my $s = (split ' ', $hr->{'signature'})[0];

        my $k = sprintf '%s%s%03d', $p, $c, $v;
        if (!$combs{$k}) {
            push @history, {
                index   => ++$hist_idx,
                pname   => EBT2->printers ($p),
                cname   => EBT2->countries ($c),
                pc      => $p,
                cc      => $c,
                value   => $hr->{'value'},
                num     => $num_note,
                date    => (split ' ', $hr->{'date_entered'})[0],
                city    => $hr->{'city'},
                country => $hr->{'country'},
            };
        }
        $combs{$k}++;
        $sigs{$s}{$k}++;
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

=pod

sub notes_by_combination {
    my ($self, $data) = @_;
    my %ret;

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $comb1 = sprintf '%s%s',   (substr $hr->{'short_code'}, 0, 1), (substr $hr->{'serial'}, 0, 1);
        my $comb2 = sprintf '%s%s%s', (substr $hr->{'short_code'}, 0, 1), (substr $hr->{'serial'}, 0, 1), $hr->{'value'};
        my ($sig) = $hr->{'signature'} =~ /^(\w+)/ or next;

        $ret{'notes_by_combination'}{'any'}{$comb1}{'total'}++;
        $ret{'notes_by_combination'}{'any'}{$comb1}{ $hr->{'value'} }++;
        #$ret{'notes_by_combination_with_value'}{'any'}{$comb2}{'total'}++;   ## 20110406: a ver si comentar esto no rompe nada
        $ret{'notes_by_combination_with_value'}{'any'}{$comb2}{ $hr->{'value'} }++;

        $ret{'notes_by_combination'}{$sig}{$comb1}{'total'}++;
        $ret{'notes_by_combination'}{$sig}{$comb1}{ $hr->{'value'} }++;
        $ret{'notes_by_combination_with_value'}{$sig}{$comb2}{ $hr->{'value'} }++;
    }

    return \%ret;
}
#sub notes_by_combination_with_value { goto &notes_by_combination; }

sub plate_bingo {
    my ($self, $data) = @_;
    my %ret;

    for my $v (keys %{ $EBT2::config{'sigs'} }) {
        for my $cc (keys %{ $EBT2::config{'sigs'}{$v} }) { 
            for my $plate (keys %{ $EBT2::config{'sigs'}{$v}{$cc} }) { 
                $ret{'plate_bingo'}{$v}{$plate} = 0; 
                $ret{'plate_bingo'}{'all'}{$plate} = 0; 
            }    
        }    
    }

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        my $plate = substr $hr->{'short_code'}, 0, 4;
        if (
            !exists $ret{'plate_bingo'}{ $hr->{'value'} }{$plate} or
            'err' eq $ret{'plate_bingo'}{ $hr->{'value'} }{$plate}
        ) {
            warn sprintf "invalid note: plate '%s' doesn't exist for value '%s' and country '%s'\n",
                $plate, $hr->{'value'}, substr $hr->{'serial'}, 0, 1;
            $ret{'plate_bingo'}{ $hr->{'value'} }{$plate} = 'err';
        } else {
            $ret{'plate_bingo'}{ $hr->{'value'} }{$plate}++;
            $ret{'plate_bingo'}{ 'all' }{$plate}++;
        }
    }

    return \%ret;
}

=cut

sub bundle {
    my ($self, $data) = @_;
    my %ret;
    my $at = 0;

    ## plate_bingo: prepare
    for my $v (keys %{ $EBT2::config{'sigs'} }) {
        for my $cc (keys %{ $EBT2::config{'sigs'}{$v} }) {
            for my $plate (keys %{ $EBT2::config{'sigs'}{$v}{$cc} }) {
                $ret{'plate_bingo'}{$v}{$plate} = 0;
                $ret{'plate_bingo'}{'all'}{$plate} = 0;
            }
        }
    }

    ## bad_notes: prepare
    $ret{'bad_notes'} = [];

    my $iter = $data->note_getter;
    while (my $hr = $iter->()) {
        ## count (total_value, signatures)
        $ret{'count'}++;
        $ret{'total_value'} += $hr->{'value'};
        $ret{'signatures'}{ $hr->{'signature'} }++;

        ## days_elapsed
        if (!exists $ret{'days_elapsed'}) {
            my $dt0 = DateTime->new (
                zip @{[qw/year month day hour minute second/]}, @{[ split /[\s:-]/, $hr->{'date_entered'} ]}
            );
            $ret{'days_elapsed'} = DateTime->now->delta_days ($dt0)->delta_days;
        }

        ## notes_by_value
        $ret{'notes_by_value'}{ $hr->{'value'} }++;

        ## notes_by_cc
        my $cc = substr $hr->{'serial'}, 0, 1;
        $ret{'notes_by_cc'}{$cc}{'total'}++;
        $ret{'notes_by_cc'}{$cc}{ $hr->{'value'} }++;

        ## first_by_cc
        $at++;
        #my $cc = substr $hr->{'serial'}, 0, 1;
        if (!exists $ret{'first_by_cc'}{$cc}) {
            $ret{'first_by_cc'}{$cc} = { %$hr, at => $at };
        }

        ## notes_by_country
        $ret{'notes_by_country'}{ $hr->{'country'} }{'total'}++;
        $ret{'notes_by_country'}{ $hr->{'country'} }{ $hr->{'value'} }++;

        ## notes_by_city
        $ret{'notes_by_city'}{ $hr->{'country'} }{ $hr->{'city'} }{'total'}++;
        $ret{'notes_by_city'}{ $hr->{'country'} }{ $hr->{'city'} }{ $hr->{'value'} }++;

        ## notes_by_pc
        my $pc = substr $hr->{'short_code'}, 0, 1;
        $ret{'notes_by_pc'}{$pc}{'total'}++;
        $ret{'notes_by_pc'}{$pc}{ $hr->{'value'} }++;

        ## first_by_pc
        #$at++;
        #my $pc = substr $hr->{'short_code'}, 0, 1;
        if (!exists $ret{'first_by_pc'}{$pc}) {
            $ret{'first_by_pc'}{$pc} = { %$hr, at => $at };
        }

        ## huge_table
        my $plate = substr $hr->{'short_code'}, 0, 4;
        if (!$hr->{'invalid'}) {
            my $serial = EBT2::Data::serial_remove_meaningless_figures2 $hr->{'short_code'}, $hr->{'serial'};
            my $num_stars = $serial =~ tr/*/*/;
            $serial = substr $serial, 0, 4+$num_stars;
            $ret{'huge_table'}{$plate}{ $hr->{'value'} }{$serial}{'count'}++;
        }

        ## alphabets
        my $city = $hr->{'city'};
        ## some Dutch cities have an abbreviated article at the beginning, ignore it
        if ($city =~ /^'s[- ](.*)/) {
            $city = $1;
        }
        ## ...probably more similar cases to be handled here...
        my $initial = substr $city, 0, 1;
        ## removing diacritics is a hard task; let's follow the KISS principle here
        $initial =~ tr/áéíóúÁÉÍÓÚàèìòùÀÈÌÒÙäëïöüÄËÏÖÜ/AEIOUAEIOUAEIOUAEIOUAEIOUAEIOU/;  ## turn to uppercase in the same step
        $ret{'alphabets'}{ $hr->{'country'} }{$initial}++;

        ## fooest_short_codes
        foreach my $fooest_params (
            [ -1, 'lowest_short_codes' ],
            [ 1, 'highest_short_codes' ],
        ) {
            my ($cmp_key, $hash_key) = @$fooest_params;
            my $pc = substr $hr->{'short_code'}, 0, 1;
            my $serial = EBT2::Data::serial_remove_meaningless_figures2 $hr->{'short_code'}, $hr->{'serial'};
            $serial =~ s/^([A-Z]\**\d{3}).*$/$1/;
            my $sort_key = sprintf '%s%s', $hr->{'short_code'}, $serial;

            for my $value ('all', $hr->{'value'}) {
                if (!exists $ret{$hash_key}{$pc}{$value}) {
                    $ret{$hash_key}{$pc}{$value} = { %$hr, sort_key => $sort_key };
                } else {
                    if ($cmp_key == ($sort_key cmp $ret{$hash_key}{$pc}{$value}{'sort_key'})) {
                        $ret{$hash_key}{$pc}{$value} = { %$hr, sort_key => $sort_key };
                    }
                }
            }
        }

        ## coords_bingo
        my $coords = substr $hr->{'short_code'}, 4, 2;
        $ret{'coords_bingo'}{ $hr->{'value'} }{$coords}++;
        $ret{'coords_bingo'}{ 'all' }{$coords}++;

        my ($y, $m, $d, $H, $M, $S) = map { sprintf '%02d', $_ } split /[\s:-]/, $hr->{'date_entered'};
        ## notes_per_year
        #my $y = substr $hr->{'date_entered'}, 0, 4;
        $ret{'notes_per_year'}{$y}{'total'}++;
        $ret{'notes_per_year'}{$y}{ $hr->{'value'} }++;

        ## notes_per_month
        my $ym = substr $hr->{'date_entered'}, 0, 7;
        $ret{'notes_per_month'}{$ym}{'total'}++;
        $ret{'notes_per_month'}{$ym}{ $hr->{'value'} }++;

        ## top10days
        my $ymd = substr $hr->{'date_entered'}, 0, 10;
        $ret{'top10days'}{$ymd}{'total'}++;
        $ret{'top10days'}{$ymd}{ $hr->{'value'} }++;

        ## time_analysis
        #my ($y, $m, $d, $H, $M, $S) = map { sprintf '%02d', $_ } split /[\s:-]/, $hr->{'date_entered'};
        my $dow = 1 + dayofweek $d, $m, $y;
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
        #my ($Y, $m, $d) = (split /[\s:-]/, $hr->{'date_entered'})[0..2];
        #my $dow = 1 + dayofweek $d, $m, $Y;
        $ret{'notes_by_dow'}{$dow}{'total'}++;
        $ret{'notes_by_dow'}{$dow}{ $hr->{'value'} }++;

        ## notes_by_combination
        if (!$hr->{'invalid'}) {
            my $comb1 = sprintf '%s%s',   (substr $hr->{'short_code'}, 0, 1), (substr $hr->{'serial'}, 0, 1);
            if (my ($sig) = $hr->{'signature'} =~ /^(\w+)/) {
                $ret{'notes_by_combination'}{'any'}{$comb1}{'total'}++;
                $ret{'notes_by_combination'}{'any'}{$comb1}{ $hr->{'value'} }++;
                $ret{'notes_by_combination'}{$sig}{$comb1}{'total'}++;
                $ret{'notes_by_combination'}{$sig}{$comb1}{ $hr->{'value'} }++;
            }
        }

        ## plate_bingo
        #my $plate = substr $hr->{'short_code'}, 0, 4;
        if (
            !exists $ret{'plate_bingo'}{ $hr->{'value'} }{$plate} or
            'err' eq $ret{'plate_bingo'}{ $hr->{'value'} }{$plate}
        ) {
            #warn sprintf "invalid note: plate '%s' doesn't exist for value '%s' and country '%s'\n",
            #    $plate, $hr->{'value'}, substr $hr->{'serial'}, 0, 1;
            #$ret{'plate_bingo'}{ $hr->{'value'} }{$plate} = 'err';
        } else {
            $ret{'plate_bingo'}{ $hr->{'value'} }{$plate}++;
            $ret{'plate_bingo'}{ 'all' }{$plate}++;
        }

        ## bad_notes
        if ($hr->{'invalid'}) {
            push @{ $ret{'bad_notes'} }, $hr;
        }
    }

    ## top_10_days: keep the 10 highest (delete the other ones)
    my @sorted_days = sort {
        $ret{'top10days'}{$b}{'total'} <=> $ret{'top10days'}{$a}{'total'} ||
        $b cmp $a
    } keys %{ $ret{'top10days'} };
    delete @{ $ret{'top10days'}  }{ @sorted_days[10..$#sorted_days] };

    return \%ret;
}
sub count { goto &bundle; }
sub total_value { goto &bundle; }
sub signatures  { goto &bundle; }
sub days_elapsed { goto &bundle; }
sub notes_by_value { goto &bundle; }
sub notes_by_cc { goto &bundle; }
sub first_by_cc { goto &bundle; }
sub notes_by_country { goto &bundle; }
sub notes_by_city { goto &bundle; }
sub notes_by_pc { goto &bundle; }
sub first_by_pc { goto &bundle; }
sub huge_table { goto &bundle; }
sub alphabets { goto &bundle; }
sub lowest_short_codes { goto &bundle; }
sub highest_short_codes { goto &bundle; }
sub coords_bingo { goto &bundle; }
sub notes_per_year { goto &bundle; }
sub notes_per_month { goto &bundle; }
sub top10days { goto &bundle; }
sub time_analysis { goto &bundle; }
sub notes_by_dow { goto &bundle; }
sub notes_by_combination { goto &bundle; }
sub plate_bingo { goto &bundle; }
sub bad_notes { goto &bundle; }

sub hit_list {
    my ($self, $data, $whoami) = @_;
    my %ret;

    my $note_no = 0;
    my $notes_elapsed = 0;
    my $hit_no = 0;
    my $notes_between = 0;
    my $prev_hit_dt;

    my $iter = $data->note_getter;
    my @gotten;
    while (my $hr = $iter->()) {
        $hr->{'note_no'} = ++$note_no;
        push @gotten, $hr;
    }
    foreach my $hr (sort {
        (defined $a->{'hit'} && defined $b->{'hit'}) ? $a->{'hit'}{'hit_date'} cmp $b->{'hit'}{'hit_date'} :
        (defined $a->{'hit'} && !defined $b->{'hit'}) ? $a->{'hit'}{'hit_date'} cmp $b->{'date_entered'} :
        (!defined $a->{'hit'} && defined $b->{'hit'}) ? $a->{'date_entered'} cmp $b->{'hit'}{'hit_date'} :
        (!defined $a->{'hit'} && !defined $b->{'hit'}) ? $a->{'date_entered'} cmp $b->{'date_entered'} :
        die 'kk while sorting' 
    } @gotten) {
        $notes_between++;
        $notes_elapsed++;
        if (1 == $hr->{'note_no'}) {
            my $base_date = $hr->{'hit'} ? $hr->{'hit'}{'hit_date'} : $hr->{'date_entered'};
            $prev_hit_dt = DateTime->new (
                zip @{[qw/year month day hour minute second/]}, @{[ split /[\s:-]/, $base_date ]}
            );
        }
        next unless exists $hr->{'hit'};
        next if $hr->{'hit'}{'moderated'};

        ## passive hit? then we shouldn't have increased notes_elapsed and notes_between, decrease them here
        $notes_elapsed--, $notes_between-- if $whoami->{'id'} eq $hr->{'hit'}{'parts'}[0]{'user_id'};

        $hit_no++;
        push @{ $ret{'hit_list'} }, {
            hit_no        => $hit_no,
            dates         => [ map { $_->{'date_entered'} } @{ $hr->{'hit'}{'parts'} } ],
            hit_date      => $hr->{'hit'}{'hit_date'},
            value         => $hr->{'value'},
            serial        => $hr->{'serial'},
            countries     => [ map { $_->{'country'} } @{ $hr->{'hit'}{'parts'} } ],
            cities        => [ map { $_->{'city'} } @{ $hr->{'hit'}{'parts'} } ],
            km            => $hr->{'hit'}{'tot_km'},
            days          => $hr->{'hit'}{'tot_days'},
            hit_partners  => [ map { $_->{'user_name'} } @{ $hr->{'hit'}{'parts'} } ],
            note_no       => $hr->{'note_no'},
            notes         => $notes_elapsed,
            moderated     => $hr->{'hit'}{'moderated'},
            old_hit_ratio => ($hit_no > 1 ? ($notes_elapsed-1)/($hit_no-1) : undef),
            new_hit_ratio => $notes_elapsed/$hit_no,
            notes_between => $notes_between,
            days_between  => DateTime->new (
                zip @{[qw/year month day hour minute second/]}, @{[ split /[\s:-]/, $hr->{'hit'}{'hit_date'} ]}
            )->delta_days ($prev_hit_dt)->delta_days,
        };
        $notes_between = 0;
        $prev_hit_dt = DateTime->new (
            zip @{[qw/year month day hour minute second/]}, @{[ split /[\s:-]/, $hr->{'hit'}{'hit_date'} ]}
        );
    }

    return \%ret;
}

sub hits_by_month {
    my ($self, $data, $whoami, $activity, $hit_list) = @_;
    my %ret;

    my %hbm;
    my %hbim;  ## by insert month

    foreach my $hit (@$hit_list) {
        my $month = substr $hit->{'hit_date'}, 0, 7;
        $hbm{$month}++;

        my $insert_month;
        for (my $idx = 0;; $idx++) {
            if ($whoami->{'name'} eq $hit->{'hit_partners'}[$idx]) {
                $insert_month = $hit->{'dates'}[$idx];
                last;
            }
        }
        $insert_month = substr $insert_month, 0, 7;
        $hbim{$insert_month}++;
    }

    my ($y, $m) = $activity->{'first_note'}{'date'} =~ /^(\d{4})-(\d{2})/;
    my $dt = DateTime->new (year => $y, month => $m);
    my $now = DateTime->now;
    while (1) {
        last if $dt > $now;
        my $str = $dt->strftime ('%Y-%m');
        $ret{'hits_by_month'}{'natural'}{$str} = $hbm{$str}  // 0;
        $ret{'hits_by_month'}{'insert'}{$str}  = $hbim{$str} // 0;
        $dt->add (months => 1);
    }

    return \%ret;
}

sub hit_analysis {
    my ($self, $data, $hit_list) = @_;
    my %ret;

    $ret{'hit_analysis'}{'longest'} = [ (reverse sort { $a->{'km'}   <=> $b->{'km'}   } @$hit_list)[0..9] ];
    $ret{'hit_analysis'}{'oldest'}  = [ (reverse sort { $a->{'days'} <=> $b->{'days'} } @$hit_list)[0..9] ];

    return \%ret;
}

1;

__END__

## NIG METHODS

sub fooest_serial_per_comb3 {
    my ($self, $cmp_key, $hash_key) = @_;

    #return $self if $self->{$hash_key};  ## if already done

    my $iter = $self->note_getter (one_result_aref => 0, one_result_full_data => 0);
    while (my $hr = $iter->()) {
        my $plate = substr $hr->{'short_code'}, 0, 4;
        my $cc    = substr $hr->{'serial'}, 0, 1;
        my $comb3 = sprintf '%s%s%03d', $plate, $cc, $hr->{'value'};

        my $serial = $self->serial_remove_meaningless_figures2 ($hr->{'short_code'}, $hr->{'serial'});
        #$serial =~ s/\*//g;

        if (!exists $self->{$hash_key}{$comb3}) {
            $self->{$hash_key}{$comb3} = { %$hr, sort_key => $serial };
        } else {
            if ($cmp_key == ($serial cmp $self->{$hash_key}{$comb3}{'sort_key'})) {
                $self->{$hash_key}{$comb3} = { %$hr, sort_key => $serial };
            }
        }
    }

    return $self;
}

sub lowest_serial_per_comb3 {
    my ($self) = @_;
    my $cmp_key = -1;
    my $hash_key = 'lowest_serial_per_comb3';

    return $self->fooest_serial_per_comb3 ($cmp_key, $hash_key);
}

sub highest_serial_per_comb3 {
    my ($self) = @_;
    my $cmp_key = 1;
    my $hash_key = 'highest_serial_per_comb3';

    return $self->fooest_serial_per_comb3 ($cmp_key, $hash_key);
}

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

sub note_entering_days {
    my ($self) = @_;

    #return $self if $self->{'note_entering_days'};  ## if already done

    my $iter = $self->note_getter (one_result_aref => 0, one_result_full_data => 0);
    while (my $hr = $iter->()) {
        my $m = 0 + substr $hr->{'date_entered'}, 5, 2;
        my $d = 0 + substr $hr->{'date_entered'}, 8, 2;
        $self->{'note_entering_days'}{$m}{$d}++;
    }

    return $self;
}

sub notes_by_hour_of_day {
    my ($self) = @_;

    #return $self if $self->{'notes_by_hour_of_day'};  ## if already done

    my $iter = $self->note_getter (one_result_aref => 0, one_result_full_data => 0);
    while (my $hr = $iter->()) {
        my $h = substr $hr->{'date_entered'}, 11, 2;
        $self->{'notes_by_hour_of_day'}{$h}{'total'}++;
        $self->{'notes_by_hour_of_day'}{$h}{ $hr->{'value'} }++;
    }

    return $self;
}

sub notes_by_hour_min {
    my ($self) = @_;

    #return $self if $self->{'notes_by_hour_min'};  ## if already done

    my $iter = $self->note_getter (one_result_aref => 0, one_result_full_data => 0);
    while (my $hr = $iter->()) {
        $hr->{'date_entered'} =~ /(\d\d):(\d\d):(\d\d)$/;
        my ($hr, $min, $sec) = ($1, $2, $3);
        $self->{'notes_by_hour_min'}{$hr}{$min}++;
        $self->{'notes_by_min_sec'}{$min}{$sec}++;
    }

    return $self;
}
sub notes_by_min_sec { goto &notes_by_hour_min; }

## todo: notes by hours in a week, 0 .. 167




