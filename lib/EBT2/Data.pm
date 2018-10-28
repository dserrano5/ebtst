package EBT2::Data;

use warnings;
use strict;
use DateTime;
use Date::DayOfWeek;
use File::Spec;
use Text::CSV;
use List::Util qw/first max sum/;
use List::MoreUtils qw/zip/;
use Storable qw/retrieve store freeze/;
use Locale::Country;
use MIME::Base64;
use Digest::SHA qw/sha512/;
use EBT2::Util qw/_xor serial_remove_meaningless_figures2/;
use EBT2::NoteValidator;
use EBT2::Constants ':all';

## whenever there are changes in the data format, this has to be increased in order to detect users with old data formats
my $DATA_VERSION = '20130507-01';

Locale::Country::add_country_alias (uk => 'gb');
Locale::Country::add_country ('rskm' => 'Kosovo');                ## EBT lists Kosovo as a country, which isn't defined in ISO-3166-1 as a country. Use its ISO-3166-2 code
Locale::Country::rename_country ('ba' => 'Bosnia-Herzegovina');   ## Locale::Country gives a different name to this one
Locale::Country::rename_country ('ci' => 'Ivory Coast');          ## Locale::Country gives a different name to this one
Locale::Country::add_country ('rsme' => 'Serbia and Montenegro'); ## EBT lists "Serbia and Montenegro" as a country. Use the joint ISO-3166-1 codes for "Serbia" and "Montenegro"

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

sub whoami {
    my ($self) = @_;

    return $self->{'whoami'};
}

sub set_checked_boxes {
    my ($self, @cbs) = @_;

    $self->{'checked_boxes'} = \@cbs;
    $self->write_db;
    return;
}

sub get_checked_boxes {
    my ($self) = @_;

    return $self->{'checked_boxes'};
}

## never tested with Europa notes, I guess it would work by ignoring both letters
## if a range in the configuration needs to specify the letter, this needs to be changed
sub _guess_signature {
    my ($series, $value, $short, $serial, $sign) = @_;
    
    $sign =~ s/\s//g;
    my $max_len = max map length, $sign =~ /\d+/g;  ## how many digits to evaluate

    foreach my $choice (split /,/, $sign) {
        my ($result, $range) = split /:/, $choice;
        my ($min, $max) = split /-/, $range;

        $serial = serial_remove_meaningless_figures2 $series, $value, $short, $serial;
        $serial =~ s/\D//g;     ## XXX: we might have to take the second letter into account for Europa notes, this line would have to be changed
        my ($num) = $serial =~ /^(.{$max_len})/;
        next if $num < $min or $num > $max;

        return $result;
    }

    return;
}

sub year_to_series {
    my ($year) = @_;
    return $EBT2::config{'year_to_series'}{$year} // '';
}

sub _find_out_signature {
    my ($series, $value, $short, $serial) = @_;

    my $plate = substr $short, 0, 4;
    my $cc = substr $serial, 0, 1;
    my $sig = $EBT2::config{'sigs'}{$series}{$value}{$cc}{$plate};
    if (!defined $sig) {
        #return 'MD' if 'europa' eq $series;   ## this will last until Europa plates are more or less well known
        #warn "No signature found (unknown combination?) for note ($value) ($cc) ($plate)\n";
        $sig = '_UNK';
    } else {
        if ($sig =~ /,/) {
            if (!defined ($sig = _guess_signature $series, $value, $short, $serial, $sig)) {
                warn "Couldn't guess signature for note ($value) ($cc) ($plate) ($short) ($serial)\n";
                $sig = '_UNK';
            }
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
    my ($self, $progress, $notes_file, $store_path, $do_keep_hits) = @_;
    my $fd;
    my $note_no = 0;
    $do_keep_hits //= 1;
    my @notes_column_names = qw/
        value year serial desc date_entered city country
        zip short_code id times_entered moderated_hit lat long
    /;
    my %recent_cutoffs = (
        _1year   => DateTime->now->subtract (years  => 1)->strftime ('%Y%m%d'),
        _3months => DateTime->now->subtract (months => 3)->strftime ('%Y%m%d'),
        _1week   => DateTime->now->subtract (weeks  => 1)->strftime ('%Y%m%d'),
    );

    my @bad_notes;

    ## maybe keep known hits (if any)
    my %save_hits;
    if ($do_keep_hits) {
        foreach my $n (map { _xor $_ } @{ $self->{'notes'} }) {
            my @arr = split ';', $n, NCOLS;
            next unless $arr[HIT];
            $save_hits{ $arr[SERIAL] } = $arr[HIT];
        }
    }
    $self->{'has_bad_notes'} = 0;
    $self->{'has_existing_countries'} = 0;

    $self->_clean_object;

    if ($do_keep_hits) {
        $self->{'has_hits'} = 0 + !!%save_hits;
    } else {
        $self->{'has_hits'} = 0;
    }

    open $fd, '<:encoding(UTF-8)', $notes_file or die "open: '$notes_file': $!\n";
    my $header = <$fd>;
    $header =~ s/[\x0d\x0a]*$//;
    die "Unrecognized notes file: bad header\n" if $header !~ /^\x{feff}?EBT notes v2;*$/;

    my $last_date;
    open my $outfd, '>:encoding(UTF-8)', $store_path or die "open: '$store_path': $!" if $store_path;
    my $notes_csv = Text::CSV->new ({ sep_char => ';', binary => 1 });
    $notes_csv->column_names (@notes_column_names);
    while (my $hr = $notes_csv->getline_hr ($fd)) {
        if ($progress and 0 == $note_no % $EBT2::progress_every) { $progress->set ($note_no); }
        if ($hr->{'date_entered'} =~ m{^(\d{1,2})[/.](\d{1,2})[/.](\d{2}) (\d{2}):(\d{2})$}) {
            $hr->{'date_entered'} = sprintf "%s-%02s-%02s %s:%s:00", (2000+$3), $2, $1, $4, $5;
        }
        if ($hr->{'date_entered'} =~ m{^(\d{1,2})[/.](\d{1,2})[/.](\d{4}) (\d{2}):(\d{2})$}) {
            $hr->{'date_entered'} = sprintf "%s-%02s-%02s %s:%s:00", $3, $2, $1, $4, $5;
        }
        if ($hr->{'date_entered'} !~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/) {
            die "Unrecognized notes file: bad date '$hr->{'date_entered'}'\n";
        }
        if ($last_date and -1 == ($hr->{'date_entered'} cmp $last_date)) {
            die "Unrecognized notes file: date not in ascending order '$hr->{'date_entered'}'\n";
        }
        $last_date = $hr->{'date_entered'};
        if ($hr->{'lat'} > 90 or $hr->{'lat'} < -90 or $hr->{'long'} > 180 or $hr->{'long'} < -180) {
            $hr->{'lat'} /= 10;
            $hr->{'long'} /= 10;
        }
        my ($y, $m, $d) = (split /[-: ]/, $hr->{'date_entered'})[0,1,2];
        my $dow = dayofweek $d, $m, $y; $dow = 1 + ($dow-1) % 7;   ## turn 0 (sunday) into 7. So we end up with 1..7

        my $ymd = join '', $y, $m, $d;
        if    ($ymd > $recent_cutoffs{'_1week'})   { $hr->{'recent'} = 3; }
        elsif ($ymd > $recent_cutoffs{'_3months'}) { $hr->{'recent'} = 2; }
        elsif ($ymd > $recent_cutoffs{'_1year'})   { $hr->{'recent'} = 1; }
        else                                       { $hr->{'recent'} = 0; }

        $hr->{'note_no'} = ++$note_no;
        $hr->{'series'} = year_to_series $hr->{'year'};
        $hr->{'dow'} = $dow;
        $hr->{'country'} = _cc $hr->{'country'};
        $self->{'existing_countries'}{ $hr->{'country'} } = undef;
        $self->{'has_existing_countries'} = 1;
        $hr->{'signature'} = _find_out_signature @$hr{qw/series value short_code serial/};
        $hr->{'errors'} = EBT2::NoteValidator::validate_note $hr;
        if ($hr->{'errors'}) {
            push @bad_notes, {
                %$hr,
                errors => [ split ';', decode_base64 $hr->{'errors'} ],
            };
        } else {
            if ($store_path) {
                my $serial2 = $hr->{'serial'};
                $serial2 =~ s/...$/xxx/;
                printf $outfd "%s\n", join ';', @$hr{qw/value year/}, $serial2, @$hr{qw/short_code date_entered city country/};
            }
        }
        if ($do_keep_hits and $save_hits{ $hr->{'serial'} }) {
            $hr->{'hit'} = delete $save_hits{ $hr->{'serial'} };
        } else {
            $hr->{'hit'} = '';
        }

        my $fmt = join ';', ('%s') x NCOLS;
        push @{ $self->{'notes'} }, _xor sprintf $fmt, @$hr{+COL_NAMES};
    }
    close $fd;
    close $outfd if $store_path;

    if (@bad_notes) {
        $self->{'has_bad_notes'} = 1;
        $self->{'bad_notes'}{'version'} = $EBT2::Stats::STATS_VERSION;
        $self->{'bad_notes'}{'data'} = _xor freeze \\@bad_notes;   ## always take an additional ref
    }
    #if ($do_keep_hits and %save_hits) {
    #    ## not all hits have been assigned, ie not all are present in the newly uploaded CSV
    #}

    $self->{'has_notes'} = !!@{ $self->{'notes'} };
    $self->{'notes_pos'} = 0;
    $self->{'version'} = $DATA_VERSION;
    $self->write_db;

    return $self;
}

## EBTST::Main::import configured a progress of $note_count*0.1 to this function
## thus, this function sets the progress to 0.1 * the actual notes processed
sub load_hits {
    my ($self, $progress, $hits_file) = @_;
    my $fd;
    my @hits_column_names1 = qw/
        value serial short_code year id hit_date times_entered
        moderated tot_km tot_days lats longs
    /;
    my @hits_column_names2 = qw/
        value serial short_code year id date_entered comment country
        city zip user_id user_name lat long km days
    /;

    my %serials2idx;
    my $idx = 0;
    foreach my $n (map { _xor $_ } @{ $self->{'notes'} }) {
        if ($progress and 0 == $idx % $EBT2::progress_every) { $progress->set ($idx*0.1); }
        my @arr = split ';', $n, NCOLS;
        $serials2idx{ $arr[SERIAL] } = $idx;
        $idx++;
        next unless $arr[HIT];
        $arr[HIT] = '';
        $n = join ';', @arr;
    }
    $progress and $progress->base_add (@{ $self->{'notes'} }*0.1);
    $self->{'has_hits'} = 0;

    foreach my $k ('whoami', grep /^hit/, keys %$self) {
        delete $self->{$k};
    }

    my $second_pass = 0;
    my %hits;

    open $fd, '<:encoding(UTF-8)', $hits_file or die "open: '$hits_file': $!\n";
    my $header = <$fd>;
    $header =~ s/[\x0d\x0a]*$//;
    die "Unrecognized hits file: bad header\n" if $header !~ /^\x{feff}?EBT hits v4;*$/;

    my $last_date;
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
            if ($hr->{'date_entered'} =~ m{^(\d{1,2})[/.](\d{1,2})[/.](\d{2}) (\d{2}):(\d{2})$}) {
                $hr->{'date_entered'} = sprintf "%s-%02s-%02s %s:%s:00", (2000+$3), $2, $1, $4, $5;
            }
            if ($hr->{'date_entered'} =~ m{^(\d{1,2})[/.](\d{1,2})[/.](\d{4}) (\d{2}):(\d{2})$}) {
                $hr->{'date_entered'} = sprintf "%s-%02s-%02s %s:%s:00", $3, $2, $1, $4, $5;
            }
            if ($hr->{'date_entered'} !~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/) {
                die "Unrecognized hits file: bad date '$hr->{'date_entered'}'\n";
            }
            $hr->{'country'} = _cc $hr->{'country'};
            $self->{'existing_countries'}{ $hr->{'country'} } = undef;
            $self->{'has_existing_countries'} = 1;
            if ($hr->{'lat'} > 90 or $hr->{'lat'} < -90 or $hr->{'long'} > 180 or $hr->{'long'} < -180) {
                $hr->{'lat'} /= 10;
                $hr->{'long'} /= 10;
            }

            push @{ $hits{$k}{'parts'} }, $hr;
        } else {
            if ($hr->{'hit_date'} =~ m{^(\d{1,2})[/.](\d{1,2})[/.](\d{2}) (\d{2}):(\d{2})$}) {
                $hr->{'hit_date'} = sprintf "%s-%02s-%02s %s:%s:00", (2000+$3), $2, $1, $4, $5;
            }
            if ($hr->{'hit_date'} =~ m{^(\d{1,2})[/.](\d{1,2})[/.](\d{4}) (\d{2}):(\d{2})$}) {
                $hr->{'hit_date'} = sprintf "%s-%02s-%02s %s:%s:00", $3, $2, $1, $4, $5;
            }
            if ($hr->{'hit_date'} !~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/) {
                die "Unrecognized hits file: bad hit date '$hr->{'hit_date'}'\n";
            }
            if ($last_date and -1 == ($hr->{'hit_date'} cmp $last_date)) {
                die "Unrecognized hits file: hit date not in ascending order '$hr->{'hit_date'}'\n";
            }
            $last_date = $hr->{'date_entered'};
            $hits{$k} = $hr;
        }
    }
    close $fd;

    ## check that all hits have parts. Otherwise, we haven't been given a complete hits file
    foreach my $k (keys %hits) {
        next if exists $hits{$k}{'parts'} and 'ARRAY' eq ref $hits{$k}{'parts'};
        die "Unrecognized hits file: probably incomplete file\n";
    }

    ## assign each entry in %hits to $self->{'notes'}[42]{'hit'}
    foreach my $serial (keys %hits) {
        my $p = $hits{$serial}{'parts'};

        if (!defined $self->{'whoami'}) {
            my $id1 = $hits{$serial}{'id'};
            foreach my $part (@$p) {
                my $id2 = $part->{'id'};
                if ($id1 eq $id2) {
                    $self->{'whoami'}{'id'}   = $part->{'user_id'};
                    $self->{'whoami'}{'name'} = $part->{'user_name'};
                    last;
                }
            }
        }

        my ($y, $m, $d) = (split /[-: ]/, $hits{$serial}{'hit_date'})[0,1,2];
        my $dow = dayofweek $d, $m, $y; $dow = 1 + ($dow-1) % 7;
        $hits{$serial}{'dow'} = $dow;

        my $note_num = $serials2idx{$serial};
        defined $note_num or die "Unrecognized hits file: hit absent from notes CSV\n";   ## TODO: some hits may have been assigned, then we die in the middle of the process
        my @arr = split ';', (_xor $self->{'notes'}[$note_num]), NCOLS;
        $arr[HIT] = encode_base64 +(freeze $hits{$serial}), '';
        $self->{'notes'}[$note_num] = _xor join ';', @arr;
    }

    $self->{'has_hits'} = 1 if %hits;
    $self->write_db;
}

## removes everything except minimum necessary keys, not creating a new hash and maintaining the blessing
sub _clean_object {
    my ($self) = @_;

    my @del_keys = grep {
        'db'            ne $_ and
        'checked_boxes' ne $_ and
        'whoami'        ne $_
    } keys %$self;
    delete @$self{ @del_keys };

    return $self;
}

sub note_count {
    my ($self) = @_;
    return scalar @{ $self->{'notes'} };
}

sub has_notes {
    my ($self) = @_;

    return $self->{'has_notes'};
}

sub has_bad_notes {
    my ($self) = @_;

    return $self->{'has_bad_notes'};
}

sub has_hits {
    my ($self) = @_;

    return $self->{'has_hits'};
}

sub has_existing_countries {
    my ($self) = @_;

    return $self->{'has_existing_countries'};
}

sub load_db {
    my ($self) = @_;

    $self->_clean_object;

    my $r = retrieve $self->{'db'};      ## FIXME: race condition: another process may be in write_db's store at this moment
    $self->{$_} = $r->{$_} for keys %$r;

    if (
        !exists $self->{'version'} or
        -1 == ($self->{'version'} cmp $DATA_VERSION)
    ) {
        warn sprintf "%s: version of data '%s' is less than \$DATA_VERSION '%s', cleaning object\n",
            scalar localtime, ($self->{'version'} // '<undef>'), $DATA_VERSION;
        $self->_clean_object;   ## wipe everything, the upload of a new CSV is required to rebuild the database
    }

    return $self;
}

sub write_db {
    my ($self) = @_;

    store $self, $self->{'db'} or warn "store failed\n";
    return $self;
}

sub rewind {
    my ($self) = @_;

    $self->{'notes_pos'} = 0;
    $self->{'eof'} = 0;   ## set to 1 in get_chunk, reset to 0 here
    return $self;
}

sub next_note {
    my ($self) = @_;

    my $note = $self->{'notes'}[ $self->{'notes_pos'}++ ];
    return unless defined $note;

    ## duplicated code:
    my $weird_chars = $note =~ tr/0-9a-zA-Z,#-\.//c;
    my $is_enc = 0.3 < $weird_chars / length $note;

    if ($is_enc) {
        return _xor $note;
    } else {
        return $note;
    }
}

my ($last_read, $chunk_start, $chunk_end);
sub get_chunk {
    my ($self, $interval) = @_;
    my @chunk;

    return if $self->{'eof'};

    if ('all' eq lc $interval) {
        $self->{'eof'} = 1;
        return {
            start_date => (split ' ', (split /;/, (_xor $self->{'notes'}[ 0]), NCOLS)[DATE_ENTERED])[0],
            end_date   => (split ' ', (split /;/, (_xor $self->{'notes'}[-1]), NCOLS)[DATE_ENTERED])[0],
            notes      => [ map { _xor $_ } @{ $self->{'notes'} } ],
        };
    }

    my ($num, $what) = $interval =~ /^(\d+)([ndwmy])$/;

    if ('n' eq $what) {
        while (1) {

            ## we could slice $self->{'notes'} instead of going through $self->next_note

            my $n = $self->next_note;
            if (!$n) {
                $self->{'eof'} = 1;
                if (@chunk) {
                    return {
                        start_date => (split ' ', (split /;/, $chunk[ 0], NCOLS)[DATE_ENTERED])[0],
                        end_date   => (split ' ', (split /;/, $chunk[-1], NCOLS)[DATE_ENTERED])[0],
                        notes      => [ @chunk ],
                    };
                } else {
                    ## don't return an empty chunk, but undef instead. It'll be
                    ## catched in the premature return in &note_getter's iterator
                    return;
                }
            }
            push @chunk, $n;
            if (@chunk == $num) {
                return {
                    start_date => (split ' ', (split /;/, $chunk[ 0], NCOLS)[DATE_ENTERED])[0],
                    end_date   => (split ' ', (split /;/, $chunk[-1], NCOLS)[DATE_ENTERED])[0],
                    notes      => [ @chunk ],
                };
            }
        }
    }

    ## time-based chunks
    if (!$last_read) {
        ## first chunk

        ## - read first note
        my $n = $self->next_note;
        if (!defined $n) {
            $self->{'eof'} = 1;
            if (@chunk) {
                ## is this ever reached?
                return { start_date => "ever reached?", end_date => "ever reached?", notes => [ @chunk ] };
            } else {
                ## undef
                return;
            }
        }

        ## - determine chunk start and end (note is always in this range, so push it)
        ($chunk_start, $chunk_end) = _chunk_start_end1 $num, $what, (split /;/, $n, NCOLS)[DATE_ENTERED];
        push @chunk, $n;

        ## - read more notes until an invalid is found
        ## - this invalid one ends up in $last_read, for the next call to this function
        ## - return chunk
        while (1) {
            $n = $self->next_note;
            if (!defined $n) {
                $self->{'eof'} = 1;
                if (@chunk) {
                    return { start_date => $chunk_start, end_date => $chunk_end, notes => [ @chunk ] };
                } else {
                    ## undef
                    return;
                }
            }

            my $note_date = (split /;/, $n, NCOLS)[DATE_ENTERED];
            $note_date = (split ' ', $note_date)[0];
            if (_date_inside_range $note_date, $chunk_start, $chunk_end) {
                push @chunk, $n;
            } else {
                $last_read = $n;
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
        my $note_date = (split /;/, $last_read, NCOLS)[DATE_ENTERED];
        $note_date = (split ' ', $note_date)[0];
        if (_date_inside_range $note_date, $chunk_start, $chunk_end) {
            push @chunk, $last_read;
            undef $last_read;

            ## this is repeated code
            while (1) {
                my $n = $self->next_note;
                if (!defined $n) {
                    $self->{'eof'} = 1;
                    if (@chunk) {
                        return { start_date => $chunk_start, end_date => $chunk_end, notes => [ @chunk ] };
                    } else {
                        ## undef
                        return;
                    }
                }

                $note_date = (split /;/, $n, NCOLS)[DATE_ENTERED];
                $note_date = (split ' ', $note_date)[0];
                if (_date_inside_range $note_date, $chunk_start, $chunk_end) {
                    push @chunk, $n;
                } else {
                    $last_read = $n;
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
       full_data => '0',
    );

full_data specifies whether to return dates along with notes or not

=cut
sub note_getter {
    my ($self, %args) = @_;

    die "filter must be a hashref\n" if $args{'filter'} and 'HASH' ne ref $args{'filter'};

    $args{'interval'}  //= '1n';
    $args{'full_data'} //= '0';

    if ($args{'interval'} !~ /^\d+[ndwmy]$/ and 'all' ne lc $args{'interval'}) {
        die "invalid interval '$args{'interval'}'\n";
    }

    my $chunk = $self->get_chunk ($args{'interval'});

    if (!$chunk) {
        $self->rewind;
        return;
    }

    ## doing this with a map{} seems to use more memory
    my @new_chunk;
    foreach my $note (@{ $chunk->{'notes'} }) {
        push @new_chunk, [ split ';', $note, NCOLS ];
    }
    $chunk->{'notes'} = \@new_chunk;

    ## filter
    if ($args{'filter'}) {
        my $new_notes = [];
        NOTE: foreach my $hr (@{ $chunk->{'notes'} }) {
            foreach my $cond (keys %{ $args{'filter'} }) {
                ## TODO: --timestamp(lt,gt) --date(lt,gt) --time(lt,gt) --latitude(lt,gt) --longitude(lt,gt)
                if ('value' eq $cond) {
                    next NOTE if $hr->[const_helper $cond] != $args{'filter'}{$cond};
                } else {
                    next NOTE if $hr->[const_helper $cond] !~ $args{'filter'}{$cond};
                }
            }
            push @$new_notes, $hr;
        }
        $chunk->{'notes'} = $new_notes;
    }

    return $args{'full_data'} ? $chunk : $chunk->{'notes'};
}

1;
