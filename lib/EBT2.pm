package EBT2;

use warnings;
use strict;
use 5.10.0;
use File::Basename;
use List::MoreUtils qw/uniq/;
use Storable qw/dclone freeze thaw/;
use Time::HiRes qw/gettimeofday tv_interval/; my $t0;
use Config::General;
use EBT2::Util qw/set_xor_key _xor/;

sub _work_dir {
    my $work_dir;

    $work_dir = File::Spec->catfile ($ENV{'HOME'}, '.ebt');
    if (!mkdir $work_dir) {
        if (17 != $!) {   ## "File exists"
            die "Couldn't create work directory: '$work_dir': $!\n";
        }
    }

    return $work_dir;
}

## set up configuration before use'ing other EBT2 modules
my $work_dir;
our %config;
our %config_regions_loaded;
BEGIN {
    $work_dir = _work_dir;
    my $cfg_file = File::Spec->catfile ($work_dir, 'ebt2.cfg');
    -r $cfg_file or die "Can't find configuration file '$cfg_file'\n";
    %config = Config::General->new (-ConfigFile => $cfg_file, -IncludeRelative => 1, -UTF8 => 1)->getall;
}

use EBT2::Data;
use EBT2::Stats;


our $progress_every = 5000;
## build empty hashes with all possible combinations
#our %combs_pc_cc;
our %combs_pc_cc_val;       ## countries, printers, missing_combs_and_history
our %combs_pc_cc_sig;       ## _combs.html.ep
our %combs_pc_cc_val_sig;   ## _combs.html.ep
#our %combs_plate_cc_val_sig;
our %all_plates;
foreach my $series (@{ $config{'series'} }) {
    foreach my $v (keys %{ $config{'sigs'}{$series} }) {
        foreach my $cc (keys %{ $config{'sigs'}{$series}{$v} }) {
            foreach my $plate (keys %{ $config{'sigs'}{$series}{$v}{$cc} }) {
                my $pc = substr $plate, 0, 1;

                #$combs_pc_cc{"$series$pc$cc"} = undef;

                my $k_pcv = sprintf '%s%s%s%03d', $series, $pc, $cc, $v;
                $combs_pc_cc_val{$k_pcv} = undef;

                my $sig = [ split /, */, $config{'sigs'}{$series}{$v}{$cc}{$plate} ];
                foreach my $s (@$sig) {
                    $s =~ /^([A-Z]+)/ or die "invalid signature '$s' found in configuration, series ($series) v ($v) cc ($cc) plate ($plate)";
                    $s = $1;

                    $combs_pc_cc_sig{'any'}{"$series$pc$cc"} = undef;
                    $combs_pc_cc_sig{$s}{"$series$pc$cc"} = undef;

                    my $k_pcv = sprintf '%s%s%s%03d', $series, $pc, $cc, $v;
                    $combs_pc_cc_val_sig{'any'}{$k_pcv} = undef;
                    $combs_pc_cc_val_sig{$s}{$k_pcv} = undef;

                    #$k_pcv = sprintf '%s%s%s%03d', $series, $plate, $cc, $v;
                    #$combs_plate_cc_val_sig{'any'}{$k_pcv} = undef;
                    #$combs_plate_cc_val_sig{$s}{$k_pcv} = undef;
                }

                push @{ $all_plates{$cc}{$v} }, $plate;
            }
        }
    }
}

sub new {
    my ($class, %args) = @_;

    my %attrs;
    $attrs{$_} = delete $args{$_} for qw/db xor_key/;
    %args and die sprintf 'unrecognized parameters: %s', join ', ', sort keys %args;

    exists $attrs{'xor_key'} or die "need a 'xor_key' parameter";
    $attrs{'db'} //= File::Spec->catfile ($work_dir, 'db2');

    set_xor_key $attrs{'xor_key'};

    bless {
        data  => EBT2::Data->new (db => $attrs{'db'}),
        stats => EBT2::Stats->new,
    }, $class;
}

sub ebt_lang {
    return substr +($ENV{'EBT_LANG'} || $ENV{'LANG'} || $ENV{'LANGUAGE'} || 'en'), 0, 2;
}

my $bbcode_flags_base_href = '';
sub set_bbcode_flags_base_href {
    my ($self, $href) = @_;

    $href //= '';
    $href =~ s{/+$}{};
    $bbcode_flags_base_href = $href;
}

sub flag {
    my ($self, $iso3166) = @_;
    my $flag_txt;

    if (!defined $iso3166) {
        warn sprintf "flag: undefined iso3166, called from '%s'", (caller 1)[3];
        return undef;
    }
    if (grep { $_ eq $iso3166 } qw/at be cy de es fi fr gr ie it mt nl pt si sk uk/) {
        $flag_txt = ":flag-$iso3166:";
    } else {
        $flag_txt = sprintf '[img]%s/images/%s.gif[/img]', $bbcode_flags_base_href, $iso3166;
    }

    return $flag_txt;
}

sub load_notes        { my ($self, @args) = @_; $self->{'data'}->load_notes ($self->{'progress'}, @args); return $self; }
sub load_hits         { my ($self, @args) = @_; $self->{'data'}->load_hits  ($self->{'progress'}, @args); return $self; }
sub load_db           { my ($self)        = @_; $self->{'data'}->load_db; return $self; }
sub note_count        { my ($self)        = @_; $self->{'data'}->note_count; }
sub has_notes         { my ($self)        = @_; $self->{'data'}->has_notes; }
sub has_hits          { my ($self)        = @_; $self->{'data'}->has_hits; }
sub has_bad_notes     { my ($self)        = @_; $self->{'data'}->has_bad_notes; }
sub has_existing_countries { my ($self)   = @_; $self->{'data'}->has_existing_countries; }
sub whoami            { my ($self)        = @_; $self->{'data'}->whoami; }
sub set_checked_boxes { my ($self, @cbs)  = @_; $self->{'data'}->set_checked_boxes (@cbs); }
sub get_checked_boxes { my ($self)        = @_; return $self->{'data'}->get_checked_boxes; }
sub set_progress_obj  { my ($self, $obj)  = @_; $self->{'progress'} = $obj; }
sub del_progress_obj  { my ($self, $obj)  = @_; delete $self->{'progress'}; }
sub set_logger        { my ($self, $log)  = @_; $self->{'log'} = $log; }
sub values            { return $config{'values'};     }
sub series            { return $config{'series'}; }
sub presidents        { return $config{'presidents'}; }

sub _log {
    my ($self, $prio, $msg) = @_;
    return unless $self->{'log'};
    $self->{'log'}->$prio ($msg);
}

sub load_region_file {
    my ($self, $country, $f) = @_;

    my $bn = basename $f;
    if (exists $config_regions_loaded{$bn}) {
        $self->_log (debug => "load_region_file: region_file ($bn) already loaded, skipping");
        return;
    }
    $self->_log (debug => "load_region_file: loading region_file ($bn)");
    $config_regions_loaded{$bn} = undef;

    my $fd;
    if (!open $fd, '<:encoding(UTF-8)', $f) {
        $self->_log (warn => "open: '$f': $!");
        return;
    }

    my $cfg = $config{'regions'}{$country} ||= {};

    my ($group_name, $subgroup_name);
    my ($group_idx, $subgroup_idx) = (-1, -1);
    my %locs_in_group;
    if (exists $cfg->{'groups'}   ) { $group_idx    = $#{ $cfg->{'groups'}    }; }  ## point to last entry, index will be increased before array is updated
    if (exists $cfg->{'subgroups'}) { $subgroup_idx = $#{ $cfg->{'subgroups'} }; }

    my $entries_seen = 0;
    my $entry_check = sub {
        my ($type, $line) = @_;
        if (-1 == $group_idx) { $self->_log (warn => "no group defined yet, ignoring line (type ($type) line ($line))\n"); return; }
        $entries_seen = 1;
        return 1;
    };
    while (defined (my $line = <$fd>)) {
        chomp $line;
        $line =~ s{(?<!:)//.*}{};
        next if $line =~ /^\s*$/;

        ## actual parsing work
        given ($line) {
            when (/^PrintZeros/i) {}
            when (/^NMessage/) {}
            when (/^\s*Group\s*=\s*(.*)/) {
                $group_name = $1;
                $group_name =~ s/\s*$//;
                $group_idx++;
                $cfg->{'groups'}[$group_idx] = { name => $group_name };

                undef $subgroup_name;
                $subgroup_idx++;
                $cfg->{'subgroups'}[$subgroup_idx] = $subgroup_name;

                if ($group_idx) {
                    my $nlocs = scalar keys %locs_in_group;
                    ## $nlocs is zero when this is the first group in a given file
                    ## without this check, we set to zero the last group in the previous file for the same language
                    if ($nlocs) {
                        $cfg->{'groups'}[$group_idx-1]{'num_locs'} = $nlocs;
                    }
                    undef %locs_in_group;
                }

                $entries_seen = 0;
            }
            when (/^\s*SubGroup\s*=\s*(.*)/) {
                if (!$group_name) { $self->_log (warn => "subgroup without group, ignoring whole file '$f'\n"); return; }
                if (!$subgroup_name and !$entries_seen) {              ## first subgroup and no entries directly under the group
                    $subgroup_name = $1;
                    $subgroup_name =~ s/\s*$//;
                    $subgroup_idx++;
                    $cfg->{'subgroups'}[$subgroup_idx] = { name => $subgroup_name };

                } elsif ($subgroup_name) {                             ## prev subgroup has name, this is the next subgroup
                    $subgroup_name = $1;
                    $subgroup_name =~ s/\s*$//;
                    $subgroup_idx++;
                    $cfg->{'subgroups'}[$subgroup_idx] = { name => $subgroup_name };

                } elsif (!$subgroup_name) {                            ## first subgroup but there are already some entries directly under the group, this is an error
                    $self->_log (warn => "entries outside any subgroup, ignoring whole file '$f'");
                    return;

                } else {
                    $self->_log (error => "shouldn't happen");
                    return;
                }
            }
            when (/^\s*SubFlag\s*=\s*(.*)/) {
                if (!$subgroup_name) { $self->_log (warn => "subflag without subgroup, ignoring whole file '$f'\n"); return; }
                my $flag_url = $1;
                $flag_url =~ s/\s*$//;
                $cfg->{'subgroups'}[-1]{'flag_url'} = $flag_url;
            }
            when (/^\s*(\d+)\s*,\s*(\d+)\s*=\s*(.*)/) {
                next unless $entry_check->(ranges => $_);
                my ($start, $end, $name) = ($1, $2, $3);
                $name =~ s/\s*$//;
                $locs_in_group{$name} = undef;
                for (my $i = $start; $i <= $end; $i++) {
                    ## split and rejoin with the new entry
                    $cfg->{'ranges'}[$i] = join '#',
                        (split /#/, $cfg->{'ranges'}[$i]//''),
                        sprintf '%d,%d,%s', $group_idx, $subgroup_idx, $name;
                }
            }
            when (/^\s*([\w\d]+)\s*;\s*([^=]+)=\s*(.*)/) {
                next unless $entry_check->(specific => $_);
                my ($zip, $csv_name, $name) = ($1, $2, $3);
                $csv_name =~ s/\s*$//;
                $name     =~ s/\s*$//;
                $locs_in_group{$name} = undef;
                $cfg->{'specific'}{$zip}{$csv_name} = join '#',
                    (split /#/, $cfg->{'specific'}{$zip}{$csv_name}//''),
                    sprintf '%d,%d,%s', $group_idx, $subgroup_idx, $name;
            }
            when (/^\s*;\s*([^=]+)=\s*(.*)/) {
                next unless $entry_check->(name_map => $_);
                my ($csv_name, $name) = ($1, $2);
                $csv_name =~ s/\s*$//;
                $name     =~ s/\s*$//;
                $locs_in_group{$name} = undef;
                $cfg->{'name_map'}{$csv_name} = join '#',
                    (split /#/, $cfg->{'name_map'}{$csv_name}//''),
                    sprintf '%d,%d,%s', $group_idx, $subgroup_idx, $name;
            }
            when (/^\s*([^=]+)=\s*(.*)/) {
                next unless $entry_check->(zip_map => $_);
                my ($zip, $name) = ($1, $2);
                $zip  =~ s/\s*$//;
                $name =~ s/\s*$//;
                $locs_in_group{$name} = undef;
                $cfg->{'zip_map'}{$zip} = join '#',
                    (split /#/, $cfg->{'zip_map'}{$zip}//''),
                    sprintf '%d,%d,%s', $group_idx, $subgroup_idx, $name;
            }
            default { $self->_log (warn => "ignoring unrecognized line '$line'\n"); }
        }
    }

    ## this is only done when a new group is found, need to repeat it for the last group
    $cfg->{'groups'}[-1]{'num_locs'} = scalar keys %locs_in_group;

    close $fd;

$cfg = <<'EOF';
$config{'regions'} = {
    es => {
        groups => [
            { name => 'foo', num_locs => 42 },
            { name => 'bar', num_locs => 21 },
            { name => 'foo', num_locs => 69 },  ## dup name ok
        ],
        subgroups => [
            { name => 'sg1' },
            { name => 'sg2', flag => 'http://bar' },
            { name => 'sg2', flag => 'http://bar' },  ## dup name ok
        ],
        ranges => [
            'group_idx,subgroup_idx,name|...',
            '30,10,name|34,20,name2',
        ],
        specific => {
            zip => {
                csv_name => 'group_idx,subgroup_idx,name|...',
            },
        },
        name_map => {
            csv_name => 'group_idx,subgroup_idx,name|...',
        },
        zip_map => {
            zip => 'group_idx,subgroup_idx,name|...',
        },
    },
};
EOF
    return;
}

sub load_region_config {
    my ($self) = @_;
    my @configured_countries = uniq map { /^([a-z]+)/ } map { basename $_ } glob File::Spec->catfile ($work_dir, 'regions', '*');

    my @countries = keys %{ $self->{'data'}{'existing_countries'} };
    if (!@countries) { @countries = @configured_countries; }  ## don't know what countries to load? then load them all
    #@countries = @configured_countries;                      ## unconditionally load all (for development)

    foreach my $country (@countries) {
        my $region_files = File::Spec->catfile ($work_dir, 'regions', "$country*");
        foreach my $region_file (glob $region_files) {
            $self->load_region_file ($country, $region_file);
        }
    }
}

sub done_data {
    my ($self) = @_;

    my %done = map { $_ => undef } keys %{ $self->{'data'} };
    delete @done{qw/db whoami version eof has_hits has_notes has_bad_notes has_existing_countries checked_boxes notes_pos/};
    my @done = keys %done;
    return @done;
}

my @encrypted_fields = qw/
    first_by_cc first_by_pc first_by_value
    highest_short_codes lowest_short_codes
    hit_analysis hit_list hit_summary
    missing_combs_and_history notes_by_combination
    notes_by_cc notes_by_city notes_by_country notes_by_dow notes_by_pc notes_by_value
    bad_notes
    huge_table
    nice_serials
    plate_bingo
    travel_stats
/;

our $AUTOLOAD;
sub AUTOLOAD {
    my ($self, @args) = @_;
    my ($pkg, $field) = (__PACKAGE__, $AUTOLOAD);

    $field =~ s/${pkg}:://;
    return if $field eq 'DESTROY';
    if ($field =~ s/^get_//) {
        if (!$self->{'data'}{'notes'}) {
            $self->_log (warn => "'$field' was queried but there's no data");
            return undef;
        }

        ## temporary code for existing databases
        delete $self->{'data'}{'stats_version'};
        if (exists $self->{'data'}{$field}) {
            if ('HASH' ne ref $self->{'data'}{$field}) {
                #$self->_log (debug => "existing field ($field) is not a hashref: delete");
                delete $self->{'data'}{$field};
            } else {
                if (!exists $self->{'data'}{$field}{'version'}) {
                    #$self->_log (debug => "existing field ($field) is a versionless hashref: delete");
                    delete $self->{'data'}{$field};
                }
            }
        }

        if (exists $self->{'data'}{$field}) {
            if ($self->{'data'}{$field}{'version'}) {
                if (-1 != ($self->{'data'}{$field}{'version'} cmp $EBT2::Stats::STATS_VERSION)) {
                    #$self->_log (debug => "version of field ($field) ok, returning cached");

                    ## always try to decrypt. Try both ->decrypt and ->decrypt_hex
                    if (!ref $self->{'data'}{$field}{'data'}) {
                        if (25 < length $self->{'data'}{$field}{'data'}) {
                            my $weird_chars = $self->{'data'}{$field}{'data'} =~ tr/0-9a-zA-Z,#-\.//c;
                            my $is_enc = 0.3 < $weird_chars / length $self->{'data'}{$field}{'data'};
                            if ($is_enc) {
                                $t0 = [gettimeofday];
                                my $dec = _xor $self->{'data'}{$field}{'data'};
                                my $elapsed = tv_interval $t0;
                                #if ($elapsed >= 0.001) { $self->_log (debug => sprintf "decryption of field (%s) length (%s) took (%s) secs", $field, (length $self->{'data'}{$field}{'data'}), $elapsed); }
                                return ${ thaw $dec };
                            }
                        }
                        #$self->_log (debug => sprintf "scalar value for field '$field' not decrypted");
                    }

                    return ref $self->{'data'}{$field}{'data'} ? dclone $self->{'data'}{$field}{'data'} : $self->{'data'}{$field}{'data'};
                }
                #$self->_log (info => sprintf q{version '%s' of field '%s' is less than $STATS_VERSION '%s', recalculating},
                #    $self->{'data'}{$field}{'version'}, $field, $EBT2::Stats::STATS_VERSION);
            } else {
                ## shouldn't happen, since the temporary code above deletes these entries
                $self->_log (debug => "unversioned field ($field) exists, assume it is outdated");
            }
        } else {
            if (!$self->{'stats'}->can ($field)) {
                $self->_log (warn => "Method 'get_$field' called but field '$field' is unknown");
                return undef;
            }
            #$self->_log (debug => "field ($field) doesn't exist, let's go for it");
        }

        $self->load_region_config if grep { $field eq $_ } qw/regions hit_regions/;
        my $new_data = $self->{'stats'}->$field ($self->{'progress'}, $self->{'data'}, @args);

        if (!keys %$new_data) {
            $self->_log (warn => "Method 'get_$field' returned nothing");
            return undef;
        }
        my $ret;
        foreach my $f (keys %$new_data) {
            ## temporary code for existing databases
            if (exists $self->{'data'}{$f}) {
                if ('HASH' ne ref $self->{'data'}{$f}) {
                    delete $self->{'data'}{$f};
                } else {
                    if (!exists $self->{'data'}{$f}{'version'}) {
                        delete $self->{'data'}{$f};
                    }
                }
            }

            if ($f eq $field) { $ret = ref $new_data->{$f} ? dclone $new_data->{$f} : $new_data->{$f}; }

            ## encrypt only selected fields, but always take an additional ref so we don't try to freeze scalar values
            if (grep { $f eq $_ } @encrypted_fields and 25 < length (my $frozen = freeze \$new_data->{$f})) {
                $t0 = [gettimeofday];
                $self->{'data'}{$f}{'data'} = _xor $frozen;
                my $elapsed = tv_interval $t0;
                if ($elapsed >= 0.001) {
                    $self->_log (debug => sprintf "encryption of field (%s) length (%s) took (%s) secs", $f, (length $frozen), $elapsed);
                }
            } else {
                $self->{'data'}{$f}{'data'} = $new_data->{$f};
            }

            $self->{'data'}{$f}{'version'} = $EBT2::Stats::STATS_VERSION;
        }
        $self->{'data'}->write_db;

        return $ret;

    } elsif ($field eq 'countries') {
        ## close over %config - the quoted eval doesn't do it, resulting in 'Variable "%config" is not available'
        %config if 0;

        eval <<"EOF";
            *$field = sub {
                my (\$self, \$what) = \@_;
                if (\$what) {
                    return \$config{\$field}{\$what};
                } else {
                    return \$config{\$field};
                }
            };
EOF
        $@ and die "eval failed: $@\n";
        goto &$field;

    } elsif ($field eq 'printers') {
        ## close over %config - the quoted eval doesn't do it, resulting in 'Variable "%config" is not available'
        %config if 0;

        eval <<"EOF";
            *$field = sub {
                my (\$self, \$what, \$series) = \@_;
                \$series ||= '2002';
                if (\$what) {
                    return \$config{\$field}{\$series}{\$what};
                } else {
                    return \$config{\$field};
                }
            };
EOF
        $@ and die "eval failed: $@\n";
        goto &$field;

    } else {
        die "Can't call non existing method '$field'\n";
    }
}

1;




__END__

aqui el /tmp/ebt.pm:

package EBT;

use warnings;
use strict;
use File::Spec;

## $Id$
our $VERSION = (qw$Revision$)[-1];


################# CONSTANTS AND GLOBALS

my $primes_file   = File::Spec->catfile ($work_dir, 'prime-numbers');


## DATA METHODS

sub note_grep {
    my ($self, %filter) = @_;

    my $iter = $self->note_getter (interval => 'all', filter => \%filter, one_result_full_data => 0);
    return $iter->();
}





## this should go in the application, not in the module
sub note_evolution {
    my ($self, $interval, $filter, $group_by, $show_only, $output) = @_;

    ## no premature return, this always calculates data
    $self->{'note_evolution'} = [];

    my ($percent, $percent_shown);
    if ('count' ne $output) {
        if ('percent' eq $output) {
            $percent = 1;
        }
        if ('percent_shown' eq $output) {
            $percent_shown = 1;
        }
    }

    my $iter = $self->note_getter (interval => $interval, filter => $filter);
    while (my $chunk = $iter->()) {
        if (!defined $group_by) {
            push @{ $self->{'note_evolution'} }, {
                start_date => $chunk->{'start_date'},
                end_date   => $chunk->{'end_date'},
                val        => {
                    all => scalar @{ $chunk->{'notes'} },
                },
            };
            next;
        }

        my %group;
        foreach my $hr (@{ $chunk->{'notes'} }) {
            my $key;
            if ('cc' eq $group_by) {
                $key = substr $hr->{'serial'}, 0, 1;
            } elsif ('pc' eq $group_by) {
                $key = substr $hr->{'short_code'}, 0, 1;
            } elsif ('plate' eq $group_by) {
                $key = substr $hr->{'short_code'}, 0, 4;
            } elsif ('comb1' eq $group_by) {
                $key = sprintf '%s%s', (substr $hr->{'short_code'}, 0, 1), (substr $hr->{'serial'}, 0, 1);
            } elsif ('comb2' eq $group_by) {
                $key = sprintf '%s%s%s', (substr $hr->{'short_code'}, 0, 1), (substr $hr->{'serial'}, 0, 1), ($hr->{'value'});
            } elsif ('value' eq $group_by) {
                $key = $hr->{'value'};
            } elsif ('city' eq $group_by) {
                $key = $hr->{'city'};
            } elsif ('country' eq $group_by) {
                $key = $hr->{'country'};
            } elsif ('zip' eq $group_by) {
                $key = $hr->{'zip'};
            } elsif ('signature' eq $group_by) {
                $key = $hr->{'signature'};
            } else {   ## TODO: time/hour/min/sec? lat/long?
                die "Unknown 'group-by' value\n";
            }
            $group{$key}++;
        }

        if ($percent_shown) {
            ## delete from %group what we're not going to show
            foreach my $g (keys %group) {
                next if grep { $g =~ /^$_/ } @$show_only;
                delete $group{$g};
            }
        }
        my $total = (sum values %group)//0;

        my $show_pieces = {};
        foreach my $k (keys %group) {
            my $match;
            if ('value' eq $group_by) {
                $match = grep { $k == $_ } @$show_only;
            } else {
                $match = grep { $k =~ /^$_/ } @$show_only;
            }
            ## push (ie show) if @$show_only isn't defined OR if it's defined and there's match
            if (!@$show_only or $match) {
                my $v = $group{$k}//0;
                $percent||$percent_shown and $v = sprintf '%.2f', $v*100/$total;
                #push @show_pieces, 1==@$show_only ? ($v) : (join ':', $k, $v);
                $show_pieces->{$k} = $v;
            }
        }

        push @{ $self->{'note_evolution'} }, {
            start_date => $chunk->{'start_date'},
            end_date   => $chunk->{'end_date'},
            val        => $show_pieces,
        };
    }

    return $self;
}

1;
