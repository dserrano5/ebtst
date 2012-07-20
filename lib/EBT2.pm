package EBT2;

use warnings;
use strict;
use Storable qw/dclone/;
use Config::General;
use EBT2::Data;
use EBT2::Stats;
use Locale::Country;

sub _work_dir {
    my $work_dir;

    if ('MSWin32' eq $^O) {
        $work_dir = File::Spec->catfile ($FindBin::Bin, '..');
    } else {
        $work_dir = File::Spec->catfile ($ENV{'HOME'}, '.ebt');
    }

    if (!mkdir $work_dir) {
        if (17 != $!) {   ## "File exists"
            die "Couldn't create work directory: '$work_dir': $!\n";
        }
    }

    return $work_dir;
}

my $work_dir = _work_dir;
my $cfg_file = File::Spec->catfile ($work_dir, 'ebt2.cfg');
-r $cfg_file or die "Can't find configuration file '$cfg_file'\n";
our %config = Config::General->new (-ConfigFile => $cfg_file, -IncludeRelative => 1, -UTF8 => 1)->getall;

our @dow2english = qw/Sunday Monday Tuesday Wednesday Thursday Friday Saturday Sunday/;

## build empty hashes with all possible combinations
#our %combs_pc_cc;
our %combs_pc_cc_val;
our %combs_pc_cc_sig;
our %combs_pc_cc_val_sig;
#our %combs_plate_cc_val_sig;
our %all_plates;
foreach my $v (keys %{ $config{'sigs'} }) {
    foreach my $cc (keys %{ $config{'sigs'}{$v} }) {
        for my $plate (keys %{ $config{'sigs'}{$v}{$cc} }) {
            my $pc = substr $plate, 0, 1;

            #$combs_pc_cc{"$pc$cc"} = undef;

            my $k_pcv = sprintf '%s%s%03d', $pc, $cc, $v;
            $combs_pc_cc_val{$k_pcv} = undef;

            my $sig = [ split /, */, $config{'sigs'}{$v}{$cc}{$plate} ];
            foreach my $s (@$sig) {
                $s =~ /^([A-Z]+)/ or die "invalid signature '$s' found in configuration, v ($v) cc ($cc) plate ($plate)";
                $s = $1;

                $combs_pc_cc_sig{'any'}{"$pc$cc"} = undef;
                $combs_pc_cc_sig{$s}{"$pc$cc"} = undef;

                my $k_pcv = sprintf '%s%s%03d', $pc, $cc, $v;
                $combs_pc_cc_val_sig{'any'}{$k_pcv} = undef;
                $combs_pc_cc_val_sig{$s}{$k_pcv} = undef;

                #$k_pcv = sprintf '%s%s%03d', $plate, $cc, $v;
                #$combs_plate_cc_val_sig{'any'}{$k_pcv} = undef;
                #$combs_plate_cc_val_sig{$s}{$k_pcv} = undef;
            }

            push @{ $all_plates{$cc}{$v} }, $plate;
        }
    }
}

sub new {
    my ($class, %args) = @_;

    my %attrs;
    $attrs{$_} = delete $args{$_} for qw/db/;
    %args and die sprintf 'unrecognized parameters: %s', join ', ', sort keys %args;

    #exists $attrs{'foo'} or die "need a 'foo' parameter";
    $attrs{'db'} //= File::Spec->catfile ($work_dir, 'db2');

    bless {
        data  => EBT2::Data->new (db => $attrs{'db'}),
        stats => EBT2::Stats->new,
    }, $class;
}

sub presidents {
    return $config{'presidents'};
}

sub ebt_lang {
    return substr +($ENV{'EBT_LANG'} || $ENV{'LANG'} || $ENV{'LANGUAGE'} || 'en'), 0, 2;
}

sub load_notes        { my ($self, @args) = @_; $self->{'data'}->load_notes (@args); return $self; }
sub load_hits         { my ($self, @args) = @_; $self->{'data'}->load_hits  (@args); return $self; }
sub load_db           { my ($self)        = @_; $self->{'data'}->load_db; return $self; }
sub has_notes         { my ($self)        = @_; $self->{'data'}->has_notes; }
sub has_hits          { my ($self)        = @_; $self->{'data'}->has_hits; }
sub whoami            { my ($self)        = @_; $self->{'data'}->whoami; }
sub set_checked_boxes { my ($self, @cbs)  = @_; $self->{'data'}->set_checked_boxes (@cbs); }
sub get_checked_boxes { my ($self)        = @_; return $self->{'data'}->get_checked_boxes; }
sub values            { return $config{'values'}; }

our $AUTOLOAD;
sub AUTOLOAD {
    my ($self, @args) = @_;
    my ($pkg, $field) = (__PACKAGE__, $AUTOLOAD);

    $field =~ s/${pkg}:://;
    return if $field eq 'DESTROY';
    if ($field =~ s/^get_//) {
        if (!$self->{'data'}{'notes'}) {
            warn "'$field' was queried but there's no data\n";
            return undef;
        }

        return ref $self->{'data'}{$field} ? dclone $self->{'data'}{$field} : $self->{'data'}{$field} if exists $self->{'data'}{$field};

        if ($self->{'stats'}->can ($field)) {    ## if we can JIT compute the value, do it
            my $ret = $self->{'stats'}->$field ($self->{'data'}, @args);
            @{ $self->{'data'} }{keys %$ret} = @$ret{keys %$ret};
            $self->{'data'}->write_db;
            return ref $self->{'data'}{$field} ? dclone $self->{'data'}{$field} : $self->{'data'}{$field} if exists $self->{'data'}{$field};
        }

        die "Method 'get_$field' called but field '$field' is unknown\n";

    } elsif ($field =~ /^(countries|printers)$/) {
        ## close over %config - the quoted eval doesn't do it, resulting in 'Variable "%config" is not available'
        %config if 0;

        eval <<"EOF";
            *$field = sub {
                my (\$self, \$what) = \@_;
                my \$lang = ebt_lang;
                if (\$what) {
                    return \$config{\$field}{\$what};
                } else {
                    return \$config{\$field};
                }
            };
EOF
        $@ and die "eval failed: $@\n";
        goto &$field;

    } elsif ($field =~ /^(printers2name|country_names)$/) {   ## printers2name|note_procedence|country_names
        ## close over %config - the quoted eval doesn't do it, resulting in 'Variable "%config" is not available'
        %config if 0;

        eval <<"EOF";
            *$field = sub {
                my (\$self, \$what) = \@_;
                my \$lang = ebt_lang;
                if (\$what) {
                    if (
                        'en' eq \$lang and
                        !defined \$config{\$field}{\$lang}{\$what}
                    ) {
                        return code2country \$what;
                    }
                    return \$config{\$field}{\$lang}{\$what};
                } else {
                    return \$config{\$field}{\$lang};
                }
            };
EOF
        $@ and die "eval failed: $@\n";
        goto &$field;

#    } elsif ($field =~ /^(sigs_by_president|combs1|combs2|combs3)$/) {
#        ## close over these variables - the quoted eval doesn't do it,
#        ## resulting in errors like 'Variable "%combs1" is not available'
#        map $_, %sigs_by_president, %combs1, %combs2, %combs3;

#        eval <<"EOF";
#            *$field = sub {
#                my (\$self, \$what) = \@_;
#                if (\$what) {
#                    return \$${field}{\$what};
#                } else {
#                    return \\%$field;
#                }
#            };
#EOF
#        $@ and die "eval failed: $@\n";
#        goto &$field;
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

our @values = qw/5 10 20 50 100 200 500/;  ## move to config?
my %combs1;
my %combs2;
my %combs3;
my %sigs_by_president;
our %all_plates;
foreach my $v (keys %{ $config{'sigs'} }) {
    foreach my $cc (keys %{ $config{'sigs'}{$v} }) {
        for my $plate (keys %{ $config{'sigs'}{$v}{$cc} }) {
            my $pc = substr $plate, 0, 1;

            my $k1 = sprintf '%s%s',       $pc, $cc;
            my $k2 = sprintf '%s%s%03d',   $pc, $cc, $v;
            my $k3 = sprintf '%s%s%03d',   $plate, $cc, $v;
            #my $k4 = sprintf '%s%s%03d%s', $plate, $cc, $v, $sig;
            $combs1{$k1}{$v} = undef;
            $combs2{$k2}     = undef;
            $combs3{$k3}     = undef;

            my $key = "$pc$cc$v";
            my $sig = $config{'sigs'}{$v}{$cc}{$plate};
            if ($sig =~ /,/) {
                $sig =~ s/\s//g;
                foreach my $choice (split /,/, $sig) {
                    my ($result, $range) = split /:/, $choice;
                    $sigs_by_president{$result}{$key}++;
                }
            } else {
                $sigs_by_president{$sig}{$key}++;
            }
            $sigs_by_president{'any'}{$key}++;

            ## el 'our $all_plates' ahora lo creamos aquí
            push @{ $all_plates{$cc}{$v} }, $plate;
        }
    }
}

################# SUBS


## CLASS METHODS

## only for showing
sub flag {
    my ($cc) = @_;
    my $flag_txt;

    if (grep { $_ eq $cc } values %{ EBT->countries }, values %{ EBT->printers }) {
        $flag_txt = ":flag-$cc:";
    } else {
        $flag_txt = sprintf '[img]http://www.eurobilltracker.eu/img/flags/%s.gif[/img]', do {
            local $ENV{'EBT_LANG'} = 'en';
            EBT->country_names ($cc);
        };
        $flag_txt = 'oops, no country found...' unless defined $flag_txt;
    }

    return $flag_txt;
}







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







our $AUTOLOAD;
sub AUTOLOAD {
    my ($self, @args) = @_;
    my ($pkg, $field) = (__PACKAGE__, $AUTOLOAD);

    $field =~ s/${pkg}:://;
    return if $field eq 'DESTROY';
    if ($field =~ s/^get_//) {
        if (!$self->{'has_data'}) {
            warn "'$field' was queried but there's no data\n";
            return undef;
        }

        return ref $self->{$field} ? dclone $self->{$field} : $self->{$field} if exists $self->{$field};

        if ($self->can ($field)) {  ## if we can JIT compute the value, do it
            $self->$field;
            $self->write_storable;
            return ref $self->{$field} ? dclone $self->{$field} : $self->{$field} if exists $self->{$field};
        }

        die "Unknown field '$field'\n";

    } elsif ($field =~ /^(countries|printers|presidents)$/) {
        ## close over %config - the quoted eval doesn't do it, resulting in 'Variable "%config" is not available'
        %config if 0;

        eval <<"EOF";
            *$field = sub {
                my (\$self, \$what) = \@_;
                my \$lang = ebt_lang;
                if (\$what) {
                    return \$config{\$field}{\$what};
                } else {
                    return \$config{\$field};
                }
            };
EOF
        $@ and die "eval failed: $@\n";
        goto &$field;

    } elsif ($field =~ /^(printers2name|note_procedence|country_names)$/) {
        ## close over %config - the quoted eval doesn't do it, resulting in 'Variable "%config" is not available'
        %config if 0;

        eval <<"EOF";
            *$field = sub {
                my (\$self, \$what) = \@_;
                my \$lang = ebt_lang;
                if (\$what) {
                    return \$config{\$field}{\$lang}{\$what};
                } else {
                    return \$config{\$field}{\$lang};
                }
            };
EOF
        $@ and die "eval failed: $@\n";
        goto &$field;

    } elsif ($field =~ /^(sigs_by_president|combs1|combs2|combs3)$/) {
        ## close over these variables - the quoted eval doesn't do it,
        ## resulting in errors like 'Variable "%combs1" is not available'
        map $_, %sigs_by_president, %combs1, %combs2, %combs3;

        eval <<"EOF";
            *$field = sub {
                my (\$self, \$what) = \@_;
                if (\$what) {
                    return \$${field}{\$what};
                } else {
                    return \\%$field;
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
