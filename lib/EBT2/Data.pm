package EBT2::Data;

use warnings;
use strict;
use DateTime;
use File::Spec;
use Text::CSV;
use List::Util qw/first max sum/;
use List::MoreUtils qw/zip/;
use Storable qw/retrieve store freeze/;
use Locale::Country;
use MIME::Base64;
use EBT2::NoteValidator;
use EBT2::Constants ':all';

## whenever there are changes in the data format, this has to be increased in order to detect users with old data formats
my $DATA_VERSION = '20120804-01';

#use Inline C => <<'EOC';
#void my_split (char *str, int nfields) {
#    int n;
#    int len;
#    char *start;
#    char *substr;
#    char *copy;
#
#    inline_stack_vars;
#    inline_stack_reset;
#
#    copy = calloc (4096, 1);
#    start = str;
#    substr = index (str, ';');
#    for (n = 0; n < nfields-1; n++) {
#        len = substr-start;
#        strncpy (copy, start, len);
#        /* printf ("substr (%s) start (%s) copy (%s)\n", substr, start, copy); */
#        if (!strncmp (copy, ";", 1)) {
#            inline_stack_push (sv_2mortal (newSVpvn ("", 0)));
#        } else {
#            inline_stack_push (sv_2mortal (newSVpvn (copy, len)));
#        }
#        bzero (copy, len);
#        start = substr+1;
#        substr = index (start, ';');
#    }
#    inline_stack_push (sv_2mortal (newSVpvf ("%s", start)));
#    inline_stack_done;
#    free (copy);
#}
#EOC

Locale::Country::alias_code (uk => 'gb');

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
        #warn "No signature found (unknown combination?) for note ($value) ($cc) ($plate)\n";
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

my $do_keep_hits = 0;   ## not sure whether to make this configurable or not...
sub load_notes {
    my ($self, $notes_file, $store_path) = @_;
    my $fd;
    my $note_no;
    my @notes_column_names = qw/
        value year serial desc date_entered city country
        zip short_code id times_entered moderated_hit lat long
    /;

    ## maybe keep known hits (if any)
    my %save_hits;
    if ($do_keep_hits) {
        for my $n (@{ $self->{'notes'} }) {
            next unless exists $n->{'hit'};
            $save_hits{ $n->{'serial'} } = $n->{'hit'};
        }
    } else {
        $self->{'has_hits'} = 0;
    }
    $self->{'has_bad_notes'} = 0;

    $self->_clean_object;

    open $fd, '<:encoding(UTF-8)', $notes_file or die "open: '$notes_file': $!\n";
    my $header = <$fd>;
    $header =~ s/[\x0d\x0a]*$//;
    die "Unrecognized notes file\n" unless 'EBT notes v2' eq $header;

    open my $outfd, '>:encoding(UTF-8)', $store_path or die "open: '$store_path': $!" if $store_path;
    my $notes_csv = Text::CSV->new ({ sep_char => ';', binary => 1 });
    $notes_csv->column_names (@notes_column_names);
    while (my $hr = $notes_csv->getline_hr ($fd)) {
        if ($hr->{'date_entered'} =~ m{^(\d{2})/(\d{2})/(\d{2}) (\d{2}):(\d{2})$}) {
            $hr->{'date_entered'} = sprintf "%s-%s-%s %s:%s:00", (2000+$3), $2, $1, $4, $5;
        }

        if ($store_path) {
            my $serial2 = $hr->{'serial'};
            $serial2 =~ s/...$/xxx/;
            printf $outfd "%s\n", join ';', @$hr{qw/value year/}, $serial2, @$hr{qw/short_code date_entered city country/};
        }

        #$hr->{$_} +=0 for qw/value year id times_entered moderated_hit lat long/;
        $hr->{'note_no'} = ++$note_no;
        $hr->{'signature'} = _find_out_signature @$hr{qw/value short_code serial/};
        $hr->{'country'} = _cc $hr->{'country'};
        $hr->{'errors'} = EBT2::NoteValidator::validate_note $hr;
        $hr->{'hit'} = '';

        $self->{'has_bad_notes'} = 1 if $hr->{'errors'};

        ## HASH
        #push @{ $self->{'notes'} }, $hr;

        ## ARRAY
        #push @{ $self->{'notes'} }, [ @$hr{+COL_NAMES} ];

        ## STRING, CSV
        my $fmt = join ';', ('%s') x NCOLS;
        push @{ $self->{'notes'} }, sprintf $fmt, @$hr{+COL_NAMES};

        ## STRING, FIXED LENGTH STRINGS
        ##         val yr  ser  ts   city co  zip  pc  id   t   mod lat  long sig  err   hit   desc
        #my $fmt = '%3s;%4s;%12s;%19s;%30s;%2s;%12s;%6s;%10s;%1s;%1s;%18s;%18s;%10s;%100s;%100s;%250s';
        #push @{ $self->{'notes'} }, sprintf $fmt, @$hr{+COL_NAMES};
    }
    close $fd;
    close $outfd if $store_path;

    if (%save_hits) {
        for my $n (@{ $self->{'notes'} }) {
            next unless $save_hits{ $n->{'serial'} };
            $n->{'hit'} = $save_hits{ $n->{'serial'} };
        }
    }

    $self->{'has_notes'} = !!@{ $self->{'notes'} };
    $self->{'notes_pos'} = 0;
    $self->{'version'} = $DATA_VERSION;
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

    foreach my $n (@{ $self->{'notes'} }) {
        my @arr = split ';', $n, NCOLS;
        next unless $arr[HIT];
        $arr[HIT] = '';
        $n = join ';', @arr;
    }
    $self->{'has_hits'} = 0;

    my $second_pass = 0;
    my %hits;

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
            $hr->{'country'} = _cc $hr->{'country'};
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

        if (!defined $self->{'whoami'}) {
            my $d1 = $hits{$serial}{'date_entered'};
            foreach my $part (@$p) {
                my $d2 = $part->{'date_entered'};
                if ($d1 eq $d2) {
                    $self->{'whoami'}{'id'}   = $part->{'user_id'};
                    $self->{'whoami'}{'name'} = $part->{'user_name'};
                    last;
                }
            }
        }

        my $idx = (grep { $self->{'whoami'} == $p->[$_]{'user_id'} } 0 .. $#$p)[0];  ## where I appear in the hit
        $idx ||= 1;                                                       ## can't be zero, a hit occurs at the second part
        $hits{$serial}{'hit_date'} = $p->[$idx]{'date_entered'};

        ## this is potentially expensive, let's see if it causes some lag with a high number of hits
        foreach my $n (@{ $self->{'notes'} }) {
            my @arr = split ';', $n, NCOLS;
            next if $arr[SERIAL] ne $serial;
            $arr[HIT] = encode_base64 +(freeze $hits{$serial}), '';
            $n = join ';', @arr;
            last;
        }
    }

    $self->{'has_hits'} = 1 if %hits;
    $self->write_db;
}

## removes everything except minimum necessary keys, not creating a new hash and maintaining the blessing
sub _clean_object {
    my ($self) = @_;

    my @del_keys = grep {
        'db'            ne $_ and
        'checked_boxes' ne $_
    } keys %$self;
    delete @$self{ @del_keys };

    return $self;
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

sub load_db {
    my ($self) = @_;

    $self->_clean_object;

    my $r = retrieve $self->{'db'};
    $self->{$_} = $r->{$_} for keys %$r;

    if (!exists $self->{'version'} or $self->{'version'} < $DATA_VERSION) {
        warn sprintf "version of data '%s' is less than \$DATA_VERSION '$DATA_VERSION', cleaning object\n", ($self->{'version'} // '<undef>');
        $self->_clean_object;   ## wipe everything, the upload of a new CSV is required to rebuild the database
    }

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

    ## untested, since this code path isn't used in EBTST
    my $n = $self->{'notes'}[ $self->{'notes_pos'}++ ];
    my %h = zip @{[ COL_NAMES ]}, @{[ split ';', $n, NCOLS ]};
    return \%h;
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

    ## shortcut: skip the iterator and the multiple fetchrows
    ## to use the getter as before, just feed a bogus argument, e.g. $self->note_getter (foo => 'bar');
    if (!%args) {
        ## HASH, ARRAY
        #return $self->{'notes'};

        ## STRING, CSV
        return [
            map { [ split ';', $_, NCOLS ] } @{ $self->{'notes'} }
        ];

        ## STRING, CSV, MY_SPLIT
        #return [
        #    map { [ my_split $_, NCOLS ] } @{ $self->{'notes'} }
        #];

        ## STRING, FIXED LENGTH STRINGS
        #my (@arr,@arr2);
        #foreach my $n (@{ $self->{'notes'} }) {
        #    $arr2[0]  = substr $n, 0, 3;
        #    $arr2[1]  = substr $n, 0+3, 4;
        #    $arr2[2]  = substr $n, 0+3+4, 12;
        #    $arr2[3]  = substr $n, 0+3+4+12, 19;
        #    $arr2[4]  = substr $n, 0+3+4+12+19, 30;
        #    $arr2[5]  = substr $n, 0+3+4+12+19+30, 2;
        #    $arr2[6]  = substr $n, 0+3+4+12+19+30+2, 12;
        #    $arr2[7]  = substr $n, 0+3+4+12+19+30+2+12, 6;
        #    $arr2[8]  = substr $n, 0+3+4+12+19+30+2+12+6, 10;
        #    $arr2[9]  = substr $n, 0+3+4+12+19+30+2+12+6+10, 1;
        #    $arr2[10] = substr $n, 0+3+4+12+19+30+2+12+6+10+1, 1;
        #    $arr2[11] = substr $n, 0+3+4+12+19+30+2+12+6+10+1+1, 18;
        #    $arr2[12] = substr $n, 0+3+4+12+19+30+2+12+6+10+1+1+18, 18;
        #    $arr2[13] = substr $n, 0+3+4+12+19+30+2+12+6+10+1+1+18+18, 10;
        #    $arr2[14] = substr $n, 0+3+4+12+19+30+2+12+6+10+1+1+18+18+10, 100;
        #    $arr2[15] = substr $n, 0+3+4+12+19+30+2+12+6+10+1+1+18+18+10+100, 100;
        #    $arr2[16] = substr $n, 0+3+4+12+19+30+2+12+6+10+1+1+18+18+10+100+100, 250;
        #    push @arr, [ @arr2 ];
        #}
        #return \@arr;
    }

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
