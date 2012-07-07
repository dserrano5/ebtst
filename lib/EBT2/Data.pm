package EBT2::Data;

## requires that EBT2 is loaded:
## - _find_out_signature uses %EBT2::config

use warnings;
use strict;
use DateTime;
use File::Spec;
use Text::CSV;
use List::Util qw/max sum/;
use Storable qw/retrieve store/;
use Locale::Country;
Locale::Country::alias_code (uk => 'gb');
Locale::Country::rename_country ('va' => 'Vatican City');

sub new {
    my ($class, %args) = @_;

    my %attrs;
    $attrs{$_} = delete $args{$_} for qw/db/;
    %args and die sprintf 'unrecognized parameters: %s', join ', ', sort keys %args;

    exists $attrs{'db'} or die "need a 'db' parameter";
    #$attrs{'bar'} //= -default_value;

    bless {
        %attrs,
    }, $class;
}

## this is:
## - for sorting
## - for presentation
## - used in the process of signature guessing when plates are shared
sub serial_remove_meaningless_figures2 {
    my ($short, $serial) = @_;

    my $pc = substr $short, 0, 1;
    my $cc = substr $serial, 0, 1;
    if ('M' eq $cc or 'T' eq $cc) {
        $serial = $cc . '*' . substr $serial, 2;
    } elsif ('H' eq $cc or 'N' eq $cc or 'U' eq $cc) {
        $serial = $cc . '**' . substr $serial, 3;
    } elsif ('P' eq $cc and 'F' eq $pc) {
        $serial = $cc . (substr $serial, 1, 2) . '**' . substr $serial, 5;
    } elsif ('Z' eq $cc) {
        $serial = $cc . '***' . substr $serial, 4;
    } else {
        $serial = substr $serial, 0;
    }

    return $serial;
}

sub _guess_signature {
    my ($short, $serial, $sign) = @_;    ## $sign example: "WD:0-1990, JCT:1991-99999"
    
    $sign =~ s/\s//g;
    my $max_len = max map length, $sign =~ /\d+/g;  ## how many digits to evaluate

    foreach my $choice (split /,/, $sign) {
        my ($result, $range) = split /:/, $choice;
        my ($min, $max) = split /-/, $range;

        $serial = serial_remove_meaningless_figures2 $short, $serial;
        $serial =~ s/\D//g;
        my ($num) = $serial =~ /^(.{$max_len})/;
        next if $num < $min or $num > $max;

        return "$result shared";
    }

    return;
}

sub _find_out_signature {
    my ($value, $short, $serial) = @_;

    my $plate = substr $short, 0, 4;
    my $cc = substr $serial, 0, 1;
    my $sig = $EBT2::config{'sigs'}{$value}{$cc}{$plate};
    if (!defined $sig) {
        warn "No signature found (unknown combination?) for note ($value) ($cc) ($plate)\n";
        $sig = '(unknown)';
    } else {
        if ($sig =~ /,/) {
            if (!defined ($sig = _guess_signature $short, $serial, $sig)) {
                warn "Couldn't guess signature for note ($value) ($cc) ($plate) ($short) ($serial)\n";
            }
        } else {
            $sig = sprintf '%s only', $sig;
        }
    }

    return $sig;
}

## only accepts English
sub _cc {
    my ($country) = @_;

    return country2code $country;
}

sub _chunk_start_end1 {
    my ($start, $end);

    my ($num, $what, $date) = @_;
    $date =~ /(\d{4})-(\d{2})-(\d{2}) \d{2}:\d{2}:\d{2}$/ or die "invalid date: ($date)";
    my ($y, $m, $d) = ($1, $2, $3);
    if ('d' eq $what) {
            ## start: beginning of same day
            ## end: $num-1 days after $date
            $start = "$y-$m-$d";
            $end = DateTime->new (year => $y, month => $m, day => $d)->add (days => $num-1)->strftime ('%Y-%m-%d');
    } elsif ('w' eq $what) {
            ## start: beginning of monday
            ## end: start + $num weeks - 1 day
            my $date = DateTime->new (year => $y, month => $m, day => $d);
            my $dow = $date->dow; 
            $date->subtract (days => $dow-1);
            $start = $date->strftime ('%Y-%m-%d');

            $date->add (days => 6);
            $date->add (weeks => $num-1);
            $end = $date->strftime ('%Y-%m-%d');
    } elsif ('m' eq $what) {
            ## start: beginning of day 1
            ## end: day 28/29/30/31 at $num-1 months after $date
            my $date = DateTime->new (year => $y, month => $m);
            $start = $date->strftime ('%Y-%m-%d');

            $date->add (months => $num-1);
            my ($y2, $m2) = split /-/, $date->strftime ('%Y-%m');
            $end = DateTime->last_day_of_month (year => $y2, month => $m2)->strftime ('%Y-%m-%d');
    } elsif ('y' eq $what) {
            ## start: beginning of Jan 1st
            ## end: Dec 31st at $num-1 years after $date
            $start = "$y-01-01";

            my $year_end = $y + $num-1;
            $end = "$year_end-12-31";
    }

    return $start, $end;
}

sub _chunk_start_end2 {
    my ($start, $end);

    my ($num, $what, $prev_start, $prev_end) = @_;
    my ($y_start, $m_start, $d_start) = $prev_start =~ /^(\d{4})-(\d{2})-(\d{2})$/;
    my ($y_end,   $m_end,   $d_end)   = $prev_end   =~ /^(\d{4})-(\d{2})-(\d{2})$/;
    ## is it enough to add "$num$what" to both $prev_start and $prev_end? let's try
    if ('d' eq $what) {
            $start = DateTime->new (year => $y_start, month => $m_start, day => $d_start)->add (days => $num)->strftime ('%Y-%m-%d');
            $end   = DateTime->new (year => $y_end,   month => $m_end,   day => $d_end)  ->add (days => $num)->strftime ('%Y-%m-%d');
    } elsif ('w' eq $what) {
            $start = DateTime->new (year => $y_start, month => $m_start, day => $d_start)->add (weeks => $num)->strftime ('%Y-%m-%d');
            $end   = DateTime->new (year => $y_end,   month => $m_end,   day => $d_end)  ->add (weeks => $num)->strftime ('%Y-%m-%d');
    } elsif ('m' eq $what) {
            $start = DateTime->new (year => $y_start, month => $m_start, day => $d_start)->add (months => $num)->strftime ('%Y-%m-%d');

            ## month is different
            $end = DateTime->new (year => $y_end, month => $m_end, day => 1)->add (months => $num);
            my ($y2, $m2) = split /-/, $end->strftime ('%Y-%m');
            $end = DateTime->last_day_of_month (year => $y2, month => $m2)->strftime ('%Y-%m-%d');
    } elsif ('y' eq $what) {
            $start = DateTime->new (year => $y_start, month => $m_start, day => $d_start)->add (years => $num)->strftime ('%Y-%m-%d');
            $end   = DateTime->new (year => $y_end,   month => $m_end,   day => $d_end)  ->add (years => $num)->strftime ('%Y-%m-%d');
    }

    return $start, $end;
}

sub _date_inside_range {
    my ($date, $start, $end) = @_;

    return
        $start le $date &&
        $date le $end;
}

sub load_notes {
    my ($self, $notes_file) = @_;
    my $fd;
    my @notes_column_names = qw/
        value year serial desc date_entered city country
        zip short_code id times_entered moderated_hit lat long
    /;

    my %save_hits;
    for my $n (@{ $self->{'notes'} }) {
        next unless exists $n->{'hit'};
        $save_hits{ $n->{'serial'} } = $n->{'hit'};
    }

    $self->_clean_object;

    ## just as in load_hits
    return unless -s $notes_file;

    open $fd, '<:encoding(UTF-8)', $notes_file or die "open: '$notes_file': $!\n";
    my $header = <$fd>;
    $header =~ s/[\x0d\x0a]*$//;
    die "Unrecognized notes file\n" unless 'EBT notes v2' eq $header;

    my $notes_csv = Text::CSV->new ({ sep_char => ';', binary => 1 });
    $notes_csv->column_names (@notes_column_names);
    while (my $hr = $notes_csv->getline_hr ($fd)) {
        $hr->{'signature'} = _find_out_signature @$hr{qw/value short_code serial/};
        $hr->{'country'} = _cc $hr->{'country'};
        if ($hr->{'date_entered'} =~ m{^(\d{2})/(\d{2})/(\d{2}) (\d{2}):(\d{2})$}) {
            $hr->{'date_entered'} = sprintf "%s-%s-%s %s:%s:00", (2000+$3), $2, $1, $4, $5;
        }
        push @{ $self->{'notes'} }, $hr;
    }
    close $fd;

    for my $n (@{ $self->{'notes'} }) {
        next unless $save_hits{ $n->{'serial'} };
        $n->{'hit'} = $save_hits{ $n->{'serial'} };
    }

    $self->{'notes_pos'} = 0;
    $self->write_db;

    return $self;
}

sub load_hits {
    my ($self, $hits_file) = @_;
    my $fd;
    my @hits_column_names1 = qw/
        value serial short_code year id date_entered times_entered
        moderated tot_km tot_days lats longs
    /;
    my @hits_column_names2 = qw/
        value serial short_code year id date_entered comment country
        city zip user_id user_name lat long km days
    /;

    delete $_->{'hit'} for @{ $self->{'notes'} };

    my $second_pass = 0;
    my %hits;

    ## mojolicious feeds us an empty file, this is probably solved in a better way before reaching this point...
    return unless -s $hits_file;

    open $fd, '<:encoding(UTF-8)', $hits_file or die "open: '$hits_file': $!\n";
    my $header = <$fd>;
    $header =~ s/[\x0d\x0a]*$//;
    die "Unrecognized hits file\n" unless 'EBT hits v4' eq $header;

    my $hits_csv = Text::CSV->new ({ sep_char => ';', binary => 1 });
    $hits_csv->column_names (@hits_column_names1);
    while (my $hr = $hits_csv->getline_hr ($fd)) {
        if (!length $hr->{'value'}) {
            $second_pass = 1;
            $hits_csv->column_names (@hits_column_names2);
            next;
        }

        my $k = $hr->{'serial'};
        if ($second_pass) {
            delete @$hr{qw/value serial short_code year/};
            push @{ $hits{$k}{'parts'} }, $hr;
        } else {
            $hits{$k} = $hr;
        }
    }
    close $fd;

    ## assign each entry in %hits to $self->{'notes'}[42]{'hit'}
    ## set hit_date (date in which this note became a hit for me)
    foreach my $serial (keys %hits) {
        my $p = $hits{$serial}{'parts'};
        ## TODO: user id!!!
        my $idx = (grep { 153477 == $p->[$_]{'user_id'} } 0 .. $#$p)[0];  ## where I appear in the hit
        $idx ||= 1;                                                       ## can't be zero, a hit occurs at the second part
        $hits{$serial}{'hit_date'} = $p->[$idx]{'date_entered'};

        ## this grep is expensive, let's see if it causes some lag with a high number of hits
        my ($note) = grep { $_->{'serial'} eq $serial } @{ $self->{'notes'} };
        $note->{'hit'} = $hits{$serial};
    }

    $self->write_db;
}

## removes everything except minimum necessary keys, not creating a new hash and maintaining the blessing
sub _clean_object {
    my ($self) = @_;

    my @del_keys = grep { 'db' ne $_ } keys %$self;
    delete @$self{ @del_keys };

    return $self;
}

sub has_notes {
    my ($self) = @_;

    return exists $self->{'notes'} && !!@{ $self->{'notes'} };
}

sub load_db {
    my ($self) = @_;

    $self->_clean_object;
    my $r = retrieve $self->{'db'};
    $self->{$_} = $r->{$_} for keys %$r;

    return $self;
}

sub write_db {
    my ($self) = @_;

    store $self, $self->{'db'} or warn "store failed\n";
    return $self;
}

my $eof = 0;  ## set to 1 in get_chunk, reset to 0 here
sub rewind {
    my ($self) = @_;

    $self->{'notes_pos'} = 0;
    $eof = 0;
    return $self;
}

sub next_note {
    my ($self) = @_;
    return $self->{'notes'}[ $self->{'notes_pos'}++ ];
}

my ($last_read, $chunk_start, $chunk_end);
sub get_chunk {
    my ($self, $interval) = @_;
    my @chunk;

    return if $eof;

    if ('all' eq lc $interval) {
        while (my $hr = $self->next_note) {
            push @chunk, $hr;
        }
        $eof = 1;
        return {
            start_date => (split ' ', $chunk[ 0]{'date_entered'})[0],
            end_date   => (split ' ', $chunk[-1]{'date_entered'})[0],
            notes      => [ @chunk ],
        };
    }

    my ($num, $what) = $interval =~ /^(\d+)([ndwmy])$/;

    if ('n' eq $what) {
        while (1) {
            my $hr = $self->next_note;
            if (!$hr) {
                $eof = 1;
                if (@chunk) {
                    return {
                        start_date => (split ' ', $chunk[ 0]{'date_entered'})[0],
                        end_date   => (split ' ', $chunk[-1]{'date_entered'})[0],
                        notes      => [ @chunk ],
                    };
                } else {
                    ## don't return an empty chunk, but undef instead. It'll be
                    ## catched in the premature return in &note_getter's iterator
                    return;
                }
            }
            push @chunk, $hr;
            if (@chunk == $num) {
                return {
                    start_date => (split ' ', $chunk[ 0]{'date_entered'})[0],
                    end_date   => (split ' ', $chunk[-1]{'date_entered'})[0],
                    notes      => [ @chunk ],
                };
            }
        }
    }

    ## time-based chunks
    if (!$last_read) {
        ## first chunk

        ## - read first note
        my $hr = $self->next_note;
        if (!defined $hr) {
            $eof = 1;
            if (@chunk) {
                ## is this ever reached?
                return { start_date => "ever reached?", end_date => "ever reached?", notes => [ @chunk ] };
            } else {
                ## undef
                return;
            }
        }

        ## - determine chunk start and end (note is always in this range, so push it)
        ($chunk_start, $chunk_end) = _chunk_start_end1 $num, $what, $hr->{'date_entered'};
        push @chunk, $hr;

        ## - read more notes until an invalid is found
        ## - this invalid one ends up in $last_read, for the next call to this function
        ## - return chunk
        while (1) {
            $hr = $self->next_note;
            if (!defined $hr) {
                $eof = 1;
                if (@chunk) {
                    return { start_date => $chunk_start, end_date => $chunk_end, notes => [ @chunk ] };
                } else {
                    ## undef
                    return;
                }
            }

            my $note_date = $hr->{'date_entered'};
            $note_date = (split ' ', $note_date)[0];
            if (_date_inside_range $note_date, $chunk_start, $chunk_end) {
                push @chunk, $hr;
            } else {
                $last_read = $hr;
                return { start_date => $chunk_start, end_date => $chunk_end, notes => [ @chunk ] };
            }
        }
    } else {
        ## rest of chunks
        ## - determine next chunk start and end
        ($chunk_start, $chunk_end) = _chunk_start_end2 $num, $what, $chunk_start, $chunk_end;

        ## - if note in $last_read is in this range:
        ##   - push
        ##   - while read valid notes, push; when invalid, store in $last read and return chunk (just like in the other 'if' branch)
        my $note_date = $last_read->{'date_entered'};
        $note_date = (split ' ', $note_date)[0];
        if (_date_inside_range $note_date, $chunk_start, $chunk_end) {
            push @chunk, $last_read;
            undef $last_read;

            ## this is repeated code
            while (1) {
                my $hr = $self->next_note;
                if (!defined $hr) {
                    $eof = 1;
                    if (@chunk) {
                        return { start_date => $chunk_start, end_date => $chunk_end, notes => [ @chunk ] };
                    } else {
                        ## undef
                        return;
                    }
                }

                $note_date = $hr->{'date_entered'};
                $note_date = (split ' ', $note_date)[0];
                if (_date_inside_range $note_date, $chunk_start, $chunk_end) {
                    push @chunk, $hr;
                } else {
                    $last_read = $hr;
                    return { start_date => $chunk_start, end_date => $chunk_end, notes => [ @chunk ] };
                }
            }

        ## - else
        ##   - return the empty chunk
        } else {
            return { start_date => $chunk_start, end_date => $chunk_end, notes => [ @chunk ] };
        }
    }

    ## unreached, I think
print "unreached\n";
    return;
}

=pod

    %args == (
       filter => {
           value => '20',
           city => 'Madrid',
           country => 'Greece',
       },
       interval => '1n',
       one_result_aref      => '0',
       one_result_full_data => '0',
    );

one_result_aref specifies whether to return an aref of notes if only one note is to be returned

one_result_full_data specifies whether to return dates along with notes or not

=cut
sub note_getter {
    my ($self, %args) = @_;

    die "filter must be a hashref\n" if $args{'filter'} and 'HASH' ne ref $args{'filter'};

    $args{'interval'}             = '1n' unless defined $args{'interval'};
    $args{'one_result_aref'}      = '0'  unless defined $args{'one_result_aref'};
    $args{'one_result_full_data'} = '0'  unless defined $args{'one_result_full_data'};

    if ($args{'interval'} !~ /^\d+[ndwmy]$/ and 'all' ne lc $args{'interval'}) {
        die "invalid interval '$args{'interval'}'\n";
    }

    ## group by interval
    $self->rewind;
    my @complex;
    while (my $chunk = $self->get_chunk ($args{'interval'})) {
        push @complex, $chunk;
    }

    ## filter
    if ($args{'filter'}) {
        foreach my $chunk (@complex) {
            my $new_notes = [];
            NOTE: foreach my $hr (@{ $chunk->{'notes'} }) {
                foreach my $cond (keys %{ $args{'filter'} }) {
                    ## TODO: --timestamp(lt,gt) --date(lt,gt) --time(lt,gt) --latitude(lt,gt) --longitude(lt,gt)
                    if ('value' eq $cond) {
                        next NOTE if $hr->{$cond} != $args{'filter'}{$cond};
                    } else {
                        next NOTE if $hr->{$cond} !~ $args{'filter'}{$cond};
                    }
                }
                push @$new_notes, $hr;
            }
            $chunk->{'notes'} = $new_notes;
        }
    }

    ## return iterator
    return sub {
        my $ret = shift @complex;

        return if !defined $ret;
        #if !@$ret, there are no filtered notes in that interval, which is ok (say "no Maltese notes in January 2010")

        ## si hay un billete y no queremos ni aref ni full_data, devolver únicamente el billete (un hashref) sin más
        if (!$args{'one_result_aref'} and !$args{'one_result_full_data'} and 1 == @{ $ret->{'notes'} }) {
            return $ret->{'notes'}[0];
        }

        ## si hay un billete y no queremos aref (pero sí full_data, se entiende), quitar la aref
        if (!$args{'one_result_aref'} and 1 == @{ $ret->{'notes'} }) {
            $ret->{'notes'} = $ret->{'notes'}[0];
        }

        ## si no queremos full data, devolver sólo los billetes (aref) sin rangos de fechas
        if (!$args{'one_result_full_data'}) {
            $ret = $ret->{'notes'};
        }

        return $ret;
    };
}

1;
