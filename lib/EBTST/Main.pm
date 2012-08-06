package EBTST::Main;

use Mojo::Base 'Mojolicious::Controller';
use Encode qw/encode/;
use File::Spec;
use Digest::SHA qw/sha512_hex/;
use DateTime;
use List::Util qw/sum/;
use List::MoreUtils qw/uniq/;
use IO::Uncompress::Gunzip qw/gunzip $GunzipError/;
use IO::Uncompress::Unzip  qw/unzip  $UnzipError/;
use File::Temp qw/tempfile/;
use Locale::Country;
use EBTST::Main::Gnuplot;

our %dows = qw/1 Monday 2 Tuesday 3 Wednesday 4 Thursday 5 Friday 6 Saturday 7 Sunday/;
our %months = qw/1 January 2 February 3 March 4 April 5 May 6 June 7 July 8 August 9 September 10 October 11 November 12 December/;
## no need to list all english country names, we take them from Locale::Country
## with this hash we can override some of Locale::Country's names
my %country_names = (
    ru => 'Russia',            ## instead of 'Russian Federation'
    va => 'Vatican City',      ## instead of 'Holy See (Vatican City State)'
    ve => 'Venezuela',         ## instead of 'Venezuela, Bolivarian Republic of'
);
my %users;

sub _log {
    my ($self, $prio, $msg) = @_;

    my $user = $self->stash ('user');
    $self->app->log->$prio (sprintf '%s: %s', ($user // '<no user>'), $msg);
}

sub _country_names {
    my ($self, $what) = @_;

    if (!defined $what) {
        $self->_log (warn => sprintf "_country_names: undefined param, called from '%s'", (caller 1)[3]);
        return '';
    }

    my $lang = substr +($ENV{'EBT_LANG'} || $ENV{'LANG'} || $ENV{'LANGUAGE'} || 'en'), 0, 2;
    if ('en' eq $lang) {
        return exists $country_names{$what} ? $country_names{$what} : code2country $what;
    }
    return $self->l ("iso3166_$what");
}

sub load_users {
    my ($self) = @_;

    open my $fd, '<:encoding(UTF-8)', $EBTST::config{'users_db'} or die "open: '$EBTST::config{'users_db'}': $!";
    while (<$fd>) {
        chomp;
        my ($u, $p) = split /:/;
        $users{$u} = $p;
    }
    close $fd;

    $self->_log (debug => sprintf "load_users: loaded %d users", scalar keys %users);
}

sub index {
    my ($self) = @_;

    $self->redirect_to ('information') if ref $self->stash ('sess') and $self->stash ('sess')->load;
    $self->flash (requested_url => $self->flash ('requested_url'));
}

sub login {
    my ($self) = @_;

    $self->load_users;
    my $u = $self->param ('user');
    $self->_log (debug => sprintf "login: user is '%s'", $u//'<undef>');

    if (exists $users{$self->param ('user')}) {
        $self->_log (info => "login attempt for existing user '$u'");
        if ($users{$self->param ('user')} eq sha512_hex $self->param ('pass')) {
            $self->stash ('sess')->create;
            $self->stash ('sess')->data (user => $self->param ('user'));
            my $dest = $self->param ('requested_url') || 'information';
            $self->_log (info => "login successful, redirecting to '$dest'");
            $self->redirect_to ($dest);
            return;
        } else {
            $self->_log (info => 'login failed');
        }
    } else {
        $self->_log (info => "login attempt for non-existing user '$u'");
    }

    $self->redirect_to ('index');
}

sub logout {
    my ($self) = @_;

    my $user = $self->stash ('user');
    $self->_log (info => 'logging out');
    $self->stash ('sess')->expire;
    $self->redirect_to ('index');
}

sub information {
    my ($self) = @_;

    my $ac          = $self->ebt->get_activity;
    my $count       = $self->ebt->get_count;
    my $total_value = $self->ebt->get_total_value;
    my $sigs        = $self->ebt->get_signatures;
    my $full_days   = $self->ebt->get_days_elapsed;

    my $avg_value   = $total_value / $count;
    my $wd          = ($sigs->{'WD only'}//0)  + ($sigs->{'WD shared'}//0);
    my $jct         = ($sigs->{'JCT only'}//0) + ($sigs->{'JCT shared'}//0);
    my $md          = ($sigs->{'MD only'}//0)  + ($sigs->{'MD shared'}//0);
    my $unk         = ($sigs->{'(unknown)'}//0);
    my $today       = DateTime->now->set_time_zone ('Europe/Madrid')->strftime ('%Y-%m-%d %H:%M:%S');
    my $avg_per_day = $count / $full_days;

    $self->stash (
        ac           => $ac,
        bbflag       => EBT2->flag ($ac->{'first_note'}{'country'}),
        today        => $today,
        full_days    => $full_days,
        count        => $count,
        total_value  => $total_value,
        avg_value    => (sprintf '%.2f', $avg_value),
        avg_per_day  => (sprintf '%.2f', $avg_per_day),
        sigs_wd      => $wd,
        sigs_jct     => $jct,
        sigs_md      => $md,
        sigs_unk     => $unk,
        sigs_wd_pct  => (sprintf '%.2f', 100 * $wd  / $count),
        sigs_jct_pct => (sprintf '%.2f', 100 * $jct / $count),
        sigs_md_pct  => (sprintf '%.2f', 100 * $md  / $count),
        sigs_unk_pct => (sprintf '%.2f', 100 * $unk / $count),
    );
}

sub value {
    my ($self) = @_;

    my $data = $self->ebt->get_notes_by_value;
    my $notes_dates = $self->ebt->get_notes_dates;
    my $elem_by_val = $self->ebt->get_elem_notes_by_value;
    my $count = $self->ebt->get_count;

    my $notes_by_val;
    for my $value (@{ EBT2->values }) {
        push @$notes_by_val, {
            value  => $value,
            count  => ($data->{$value}//0),
            pct    => (sprintf '%.2f', 100 * ($data->{$value}//0) / $count),
            amount => ($data->{$value}//0) * $value,
        };
    }

    ## chart
    my %dpoints;
    foreach my $elem (split ',', $elem_by_val) {
        push @{ $dpoints{$_} }, $dpoints{$_}[-1] for 'Total', @{ EBT2->values };
        $dpoints{'Total'}[-1]++;
        $dpoints{$elem}[-1]++;
    }
    ## overwrite values with their percentages
    #foreach my $idx (0..$#$notes_dates) {
    #    foreach my $v (@{ EBT2->values }) {
    #        $dpoints{$v}[$idx] = 100 * ($dpoints{$v}[$idx]//0) / $dpoints{'Total'}[$idx];
    #    }
    #}
    EBTST::Main::Gnuplot::line_chart
        output => (sprintf '%s/%s', $self->stash ('images_dir'), 'acum_by_val.png'),
        xdata => $notes_dates,
        dsets => [
            #{ title => 'Total', color => 'black',  points => $dpoints{'Total'} },
            { title =>     '5', color => 'grey',   points => $dpoints{'5'}   },
            { title =>    '10', color => 'red',    points => $dpoints{'10'}  },
            { title =>    '20', color => 'blue',   points => $dpoints{'20'}  },
            { title =>    '50', color => 'orange', points => $dpoints{'50'}  },
            { title =>   '100', color => 'green',  points => $dpoints{'100'} },
            { title =>   '200', color => 'yellow', points => $dpoints{'200'} },
            { title =>   '500', color => 'purple', points => $dpoints{'500'} },
        ];

    $self->stash (notes_by_val => $notes_by_val);
}

sub countries {
    my ($self) = @_;

    my $data = $self->ebt->get_notes_by_cc;
    my $count = $self->ebt->get_count;
    my $data_fbcc = $self->ebt->get_first_by_cc;
    my $count_by_value;

    for my $cc (
        sort {
            ($data->{$b}{'total'}//0) <=> ($data->{$a}{'total'}//0) ||
            $a cmp $b
        } keys %$data
    ) {
        for my $v (grep { /^\d+$/ } keys %{ $data->{$cc} }) {
            $count_by_value->{$v} += $data->{$cc}{$v};
        }
    }

    my $nbcountry;
    for my $cc (
        sort {
            ($data->{$b}{'total'}//0) <=> ($data->{$a}{'total'}//0) ||
            $self->_country_names (EBT2->countries ($a)) cmp $self->_country_names (EBT2->countries ($b))
        } keys %{ EBT2->countries }
    ) {
        my $detail;
        for my $v (@{ EBT2->values }) {
            my $exists = 0;
            foreach my $pc (keys %{ EBT2->printers }) {
                my $k = sprintf '%s%s%03d', $pc, $cc, $v;
                if (exists $EBT2::combs_pc_cc_val{$k}) {
                    $exists = 1;
                    last;
                }
            }
            if ($exists) {
                if ($data->{$cc}{$v}) {
                    push @$detail, {
                        count => $data->{$cc}{$v},
                        pct   => (sprintf '%.2f', 100 * $data->{$cc}{$v} / $count_by_value->{$v}),
                    };
                } else {
                    push @$detail, {
                        count => 0,
                        pct   => (sprintf '%.2f', 0),
                    };
                }
            } else {
                push @$detail, {
                    count => undef,
                    pct   => undef,
                };
            }
        }
        my $iso3166 = do { local $ENV{'EBT_LANG'} = 'en'; EBT2->countries ($cc) };
        push @$nbcountry, {
            cname   => $self->_country_names (EBT2->countries ($cc)),
            imgname => $iso3166,
            bbflag  => EBT2->flag ($iso3166),
            cc      => $cc,
            count   => ($data->{$cc}{'total'}//0),
            pct     => (sprintf '%.2f', 100 * ($data->{$cc}{'total'}//0) / $count),
            detail  => $detail,
        };
    }

    my $fbcc;
    foreach my $cc (sort { $data_fbcc->{$a}{'at'} <=> $data_fbcc->{$b}{'at'} } keys %$data_fbcc) {
        my $iso3166 = do { local $ENV{'EBT_LANG'} = 'en'; EBT2->countries ($cc) };
        push @$fbcc, {
            at       => $data_fbcc->{$cc}{'at'},
            cname    => $self->_country_names (EBT2->countries ($cc)),
            imgname  => $iso3166,
            bbflag   => EBT2->flag ($iso3166),
            value    => $data_fbcc->{$cc}{'value'},
            on       => (split ' ', $data_fbcc->{$cc}{'date_entered'})[0],
            city     => $data_fbcc->{$cc}{'city'},
            imgname2 => $data_fbcc->{$cc}{'country'},
            bbflag2  => EBT2->flag ($data_fbcc->{$cc}{'country'}),
        };
    }

    $self->stash (
        nbcountry    => $nbcountry,
        #cbv          => $count_by_value,
        tot_bv       => [ map { $count_by_value->{$_}//0 } @{ EBT2->values } ],
        fbcc         => $fbcc,
    );
}

sub locations {
    my ($self) = @_;

    my $nbco    = $self->ebt->get_notes_by_country;
    my $nbci    = $self->ebt->get_notes_by_city;
    my $count   = $self->ebt->get_count;
    my $ab_data = $self->ebt->get_alphabets;

    my $countries;
    foreach my $iso3166 (
        sort {
            $nbco->{$b}{'total'} <=> $nbco->{$a}{'total'} or
            $a cmp $b
        } keys %$nbco
    ) {
        my $detail;
        for my $v (@{ EBT2->values }) {
            push @$detail, {
                value => $v,
                count => $nbco->{$iso3166}{$v},
            };
        }
        push @$countries, {
            cname   => $self->_country_names ($iso3166),
            imgname => $iso3166,
            bbflag  => EBT2->flag ($iso3166),
            count   => $nbco->{$iso3166}{'total'},
            pct     => (sprintf '%.2f', 100 * $nbco->{$iso3166}{'total'} / $count),
            detail  => $detail,
        };
    }

    my $distinct_cities = sum @{[
        map {
            scalar keys %{ $nbci->{$_} }
        } keys %$nbci
    ]};

    my $c_data;
    foreach my $country (sort keys %$nbci) {
        my $loc_data;
        foreach my $loc (
            sort {
                $nbci->{$country}{$b}{'total'} <=> $nbci->{$country}{$a}{'total'} or
                $a cmp $b
            } keys %{ $nbci->{$country} }
        ) {
            my $detail;
            for my $v (@{ EBT2->values }) {
                push @$detail, {
                    value => $v,
                    count => $nbci->{$country}{$loc}{$v},
                };
            }
            push @$loc_data, {
                loc_name => $loc,
                count    => $nbci->{$country}{$loc}{'total'},
                pct      => (sprintf '%.2f', 100 * $nbci->{$country}{$loc}{'total'} / $count),
                detail   => $detail,
            };
        }
        push @$c_data, {
            cname    => $self->_country_names ($country),
            imgname  => $country,
            bbflag   => EBT2->flag ($country),
            loc_data => $loc_data,
        };
    }

    my $ab;
    foreach my $c (sort keys %$ab_data) {
        my $letters;
            
        for my $letter ('A'..'Z') {
            $letters->{$letter} = $ab_data->{$c}{$letter};
        }

        push @$ab, {
            imgname => $c,
            cname   => $self->_country_names ($c),
            tot     => (scalar keys %{ $ab_data->{$c} }),
            letters => $letters,
        };
    }

    $self->stash (
        num_co    => scalar keys %$nbco,
        countries => $countries,
        num_locs  => $distinct_cities,
        c_data    => $c_data,
        ab        => $ab,
    );
}

sub printers {
    my ($self) = @_;

    my $data  = $self->ebt->get_notes_by_pc;
    my $count = $self->ebt->get_count;
    my $count_by_value;
    my $data_fbpc = $self->ebt->get_first_by_pc;

    for my $pc (
        sort {
            ($data->{$b}{'total'}//0) <=> ($data->{$a}{'total'}//0) ||
            $a cmp $b
        } keys %$data
    ) {
        for my $v (grep { /^\d+$/ } keys %{ $data->{$pc} }) {
            $count_by_value->{$v} += $data->{$pc}{$v};
        }
    }

    my $nbp;
    foreach my $pc (sort {
        $data->{$b}{'total'} <=> $data->{$a}{'total'} or
        $a cmp $b
    } keys %$data) {
        my $detail;
        for my $v (@{ EBT2->values }) {
            my $exists = 0;
            foreach my $cc (keys %{ EBT2->countries }) {
                my $k = sprintf '%s%s%03d', $pc, $cc, $v;
                if (exists $EBT2::combs_pc_cc_val{$k}) {
                    $exists = 1;
                    last;
                }
            }
            if ($exists) {
                if ($data->{$pc}{$v}) {
                    push @$detail, {
                        count => $data->{$pc}{$v},
                        pct   => (sprintf '%.2f', 100 * $data->{$pc}{$v} / $count_by_value->{$v}),
                    };
                } else {
                    push @$detail, {
                        count => 0,
                        pct   => (sprintf '%.2f', 0),
                    };
                }
            } else {
                push @$detail, {
                    count => undef,
                    pct   => undef,
                };
            }
        }
        push @$nbp, {
            cname   => $self->_country_names (EBT2->printers ($pc)),
            imgname => EBT2->printers ($pc),
            bbflag  => EBT2->flag (EBT2->printers ($pc)),
            pc      => $pc,
            count   => $data->{$pc}{'total'},
            pct     => (sprintf '%.2f', 100 * $data->{$pc}{'total'} / $count),
            detail  => $detail,
        };
    }

    my $fbpc;
    foreach my $pc (sort { $data_fbpc->{$a}{'at'} <=> $data_fbpc->{$b}{'at'} } keys %$data_fbpc) {
        my $iso3166 = do { local $ENV{'EBT_LANG'} = 'en'; EBT2->printers ($pc) };
        push @$fbpc, {
            at       => $data_fbpc->{$pc}{'at'},
            pc       => $pc,
            imgname  => $iso3166,
            bbflag   => EBT2->flag ($iso3166),
            value    => $data_fbpc->{$pc}{'value'},
            on       => (split ' ', $data_fbpc->{$pc}{'date_entered'})[0],
            city     => $data_fbpc->{$pc}{'city'},
            imgname2 => $data_fbpc->{$pc}{'country'},
            bbflag2  => EBT2->flag ($data_fbpc->{$pc}{'country'}),
        };
    }

    $self->stash (
        nbp    => $nbp,
        #cbv    => $count_by_value,
        tot_bv => [ map { $count_by_value->{$_}//0 } @{ EBT2->values } ],
        fbpc   => $fbpc,
    );
}

sub huge_table {
    my ($self) = @_;

    my $ht_data = $self->ebt->get_huge_table;

    my $ht;
    foreach my $plate (keys %$ht_data) {
        $ht->{$plate}{'values'} = $ht_data->{$plate};
        foreach my $value (keys %{ $ht->{$plate}{'values'} }) {
            foreach my $serial (keys %{ $ht->{$plate}{'values'}{$value} }) {
                $ht->{$plate}{'values'}{$value}{$serial}{'flag'} = EBT2->countries (substr $serial, 0, 1);
            }
        }
        $ht->{$plate}{'plate_flag'} = EBT2->printers (substr $plate, 0, 1);
    }

    $self->stash (
        ht => $ht,
    );
}

sub short_codes {
    my ($self) = @_;

    my $cook = sub {
        my ($str) = @_;
        return $str =~ /^(.{6})(.*)/;
    };

    my $lo = $self->ebt->get_lowest_short_codes;
    my $hi = $self->ebt->get_highest_short_codes;
    my @pcs = uniq keys %$lo, keys %$hi;

    my $sc;
    foreach my $pc (sort @pcs) {
        foreach my $v ('all', @{ EBT2->values }) {
            my $records = {
                lo => $lo->{$pc}{$v},
                hi => $hi->{$pc}{$v},
            };
            my $tmp;
            foreach my $what (qw/lo hi/) {
                next unless defined $records->{$what}{'short_code'};
                my $pc = substr $records->{$what}{'short_code'}, 0, 1;
                my $cc = substr $records->{$what}{'serial'},     0, 1;
                my ($pc_str, $cc_str) = $cook->($records->{$what}{'sort_key'});
                $tmp->{$what} = {
                    pc_img  => EBT2->printers ($pc),
                    pc_flag => EBT2->flag (EBT2->printers ($pc)),
                    cc_img  => EBT2->countries ($cc),
                    cc_flag => EBT2->flag (EBT2->countries ($cc)),
                    pc_str  => $pc_str,
                    cc_str  => $cc_str,
                    value   => $records->{$what}{'value'},
                    date    => (split ' ', $records->{$what}{'date_entered'})[0],
                };
            }
            push @{ $sc->{$v} }, $tmp;

            #if (!defined $lo->{$pc}{$v}{'sort_key'}) {
            #    next;
            #}
        }
    }

    $self->stash (
        sc  => $sc,
    );
}

sub nice_serials {
    my ($self) = @_;

    my $nice_data = $self->ebt->get_nice_serials;
    my $numbers_in_a_row = $self->ebt->get_numbers_in_a_row;
    my $count = $self->ebt->get_count;

    my $nice_notes;
    foreach my $n (@$nice_data) {
        push @$nice_notes, {
            score   => $n->{'score'},
            serial  => $n->{'visible_serial'},
            value   => $n->{'value'},
            date    => (split ' ', $n->{'date_entered'})[0],
            city    => $n->{'city'},
            imgname => $n->{'country'},
            bbflag  => EBT2->flag ($n->{'country'}),
        };
    }

    my $niar;
    foreach my $length (keys %$numbers_in_a_row) {
        my $num = $numbers_in_a_row->{$length};
        my $pct = $num * 100 / $count;
        $niar->{$length} = { count => $num, pct => sprintf '%.2f', $pct };
    }

    $self->stash (
        nicest           => $nice_notes,
        numbers_in_a_row => $niar,
        primes           => 'bar',
        squares          => 'baz',
        palindromes      => 'qux',
    );
}

sub coords_bingo {
    my ($self) = @_;

    my $cbingo_data = $self->ebt->get_coords_bingo;

    my $cbingo = $cbingo_data;
    #foreach my $v ('all', @{ EBT2->values }) {
    #    next unless defined $cbingo_data->{$v};
    #}

    $self->stash (
        cbingo => $cbingo,
    );
}

sub notes_per_year {
    my ($self) = @_;

    my $nby_data = $self->ebt->get_notes_per_year;
    my $count = $self->ebt->get_count;

    my $nby;
    foreach my $y (sort keys %$nby_data) {
        my $detail;
        foreach my $v (@{ EBT2->values }) {
            push @$detail, {
                value => $v,
                count => $nby_data->{$y}{$v},
            };
        }
        my $tot = $nby_data->{$y}{'total'};
        push @$nby, {
            year   => $y,
            count  => $tot,
            pct    => (sprintf '%.2f', 100 * $tot / $count),
            detail => $detail,
        };
    }

    $self->stash (
        nby => $nby,
    );
}

sub notes_per_month {
    my ($self) = @_;

    my $nbm_data = $self->ebt->get_notes_per_month;
    my $count = $self->ebt->get_count;

    my $nbm;
    foreach my $m (sort keys %$nbm_data) {
        my $detail;
        foreach my $v (@{ EBT2->values }) {
            push @$detail, {
                value => $v,
                count => $nbm_data->{$m}{$v},
            };
        }
        my $tot = $nbm_data->{$m}{'total'};
        push @$nbm, {
            month  => $m,
            count  => $tot,
            pct    => (sprintf '%.2f', 100 * $tot / $count),
            detail => $detail,
        };
    }

    $self->stash (
        nbm => $nbm,
    );
}

sub top_days {
    my ($self) = @_;

    my $t10d_data = $self->ebt->get_top10days;
    my $nbdow_data = $self->ebt->get_notes_by_dow;
    my $count = $self->ebt->get_count;

    my $nbdow;
    my %dpoints;
    foreach my $dow (sort keys %$nbdow_data) {
        my $detail;
        foreach my $v (@{ EBT2->values }) {
            push @$detail, {
                value => $v,
                count => $nbdow_data->{$dow}{$v},
            };
            push @{ $dpoints{$v} }, ($nbdow_data->{$dow}{$v}//0);
        }
        my $tot = $nbdow_data->{$dow}{'total'};
        push @$nbdow, {
            dow    => $dows{$dow},
            count  => $tot,
            pct    => (sprintf '%.2f', 100 * $tot / $count),
            detail => $detail,
        };
    }
    EBTST::Main::Gnuplot::bar_chart
        output     => (sprintf '%s/%s', $self->stash ('images_dir'), 'week_days.png'),
        labels     => [ qw/Monday Tuesday Wednesday Thursday Friday Saturday Sunday/ ],
        bar_border => 1,
        dsets => [
            { title =>     '5', color => 'grey',   points => $dpoints{'5'}   },
            { title =>    '10', color => 'red',    points => $dpoints{'10'}  },
            { title =>    '20', color => 'blue',   points => $dpoints{'20'}  },
            { title =>    '50', color => 'orange', points => $dpoints{'50'}  },
            { title =>   '100', color => 'green',  points => $dpoints{'100'} },
            { title =>   '200', color => 'yellow', points => $dpoints{'200'} },
            { title =>   '500', color => 'purple', points => $dpoints{'500'} },
        ];

    my $t10d;
    foreach my $d (
        sort {
            $t10d_data->{$b}{'total'} <=> $t10d_data->{$a}{'total'} or
            $a cmp $b
        } keys %$t10d_data
    ) {
        my $detail;
        foreach my $v (@{ EBT2->values }) {
            push @$detail, {
                value => $v,
                count => $t10d_data->{$d}{$v},
            };
        }
        my $tot = $t10d_data->{$d}{'total'};
        push @$t10d, {
            date   => $d,
            count  => $tot,
            pct    => (sprintf '%.2f', 100 * $tot / $count),
            detail => $detail,
        };
    }

    $self->stash (
        nbdow => $nbdow,
        t10d  => $t10d,
    );
}

sub time_analysis {
    my ($self) = @_;

    my $count   = $self->ebt->get_count;
    my $ta_data = $self->ebt->get_time_analysis;

    $self->stash (
        count => $count,
        ta    => $ta_data,
    );
}

sub combs_bingo {
    my ($self) = @_;

    my $nbcombo    = $self->ebt->get_notes_by_combination;
    #my $sbp        = $self->ebt->sigs_by_president;
    my $comb_data  = $self->ebt->get_missing_combs_and_history;
    my $count      = $self->ebt->get_count;
    my $presidents = [
        map { [ split /:/ ] } 'any:Any signature', @{ $self->ebt->presidents }
    ];

    my $missing;
    foreach my $k (sort keys %{ $comb_data->{'missing_pcv'} }) {
        my ($p, $c, $v) = $k =~ /^(.)(.)(\d{3})$/;
        $v += 0;

        if (!exists $missing->{"$p$c"}) {
            $missing->{"$p$c"} = {
                pname   => do { local $ENV{'EBT_LANG'} = 'en'; EBT2->printers ($p) },
                cname   => do { local $ENV{'EBT_LANG'} = 'en'; EBT2->countries ($c) },
                pletter => $p,
                cletter => $c,
                values  => [ $v ],
            };
        } else {
            push @{ $missing->{"$p$c"}{'values'} }, $v;
        }
    }

    $self->stash (
        nbcombo    => $nbcombo,
        presidents => $presidents,
        missing    => $missing,
        history    => $comb_data->{'history'},
        count      => $count,
    );
}
sub combs_detail { goto &combs_bingo; }

sub plate_bingo {
    my ($self) = @_;

    my $plate_data = $self->ebt->get_plate_bingo;
    my $cooked;
    foreach my $value (
        sort {
            if ('all' eq $a) { return -1; }
            if ('all' eq $b) { return 1; }
            return $a <=> $b;
        } keys %$plate_data
    ) {
        my %plates;
        my @printers;
        my $highest = 0;
        foreach my $plate (sort keys %{ $plate_data->{$value} }) {
            $plates{$plate} = $plate_data->{$value}{$plate};
            push @printers, substr $plate, 0, 1;
            my $ordinal = substr $plate, 1;
            $highest = $ordinal if $ordinal > $highest;
        }
        @printers = sort +uniq @printers;

        push @$cooked, {
            value    => $value,
            plates   => \%plates,
            printers => \@printers,
            highest  => $highest,
        };
    }

    $self->stash (plate_bingo => $cooked);
}

sub bad_notes {
    my ($self) = @_;

    my $bad_notes = $self->ebt->get_bad_notes;
    my @cooked;

    my $idx = 0;
    foreach my $bn (@$bad_notes) {
        my $pc = substr $bn->{'short_code'}, 0, 1;
        my $cc = substr $bn->{'serial'},     0, 1;
        $bn->{'serial'} =~ s/^([A-Z])....(....)...$/$1xxxx$2xxx/;
        $bn->{'short_code'} = substr $bn->{'short_code'}, 0, 4;
        push @cooked, {
            %$bn,
            idx    => ++$idx,
            pc_img => EBT2->printers ($pc),
            cc_img => EBT2->countries ($cc),
        };
    }

    $self->stash (
        bad_notes => \@cooked,
    );
}

sub hit_list {
    my ($self) = @_;

    my $whoami = $self->ebt->whoami;
    my $hit_data = $self->ebt->get_hit_list ($whoami);
    my $cooked;
    foreach my $hit (@$hit_data) {
        next if $hit->{'moderated'};
        $hit->{'serial'} =~ s/^([A-Z])....(....)...$/$1xxxx$2xxx/;
        push @$cooked, $hit;
    }

    $self->stash (
        hit_list => $cooked,
        whoami   => $whoami,
    );
}

sub hit_times {
    my ($self) = @_;

    my $whoami   = $self->ebt->whoami;
    my $hit_list = $self->ebt->get_hit_list ($whoami);
    my $ht       = $self->ebt->get_hit_times ($hit_list);

    $self->stash (
        count     => (scalar @$hit_list),
        hit_times => $ht,
    );
}

sub hit_analysis {
    my ($self) = @_;

    my $whoami   = $self->ebt->whoami;
    my $hit_list = $self->ebt->get_hit_list ($whoami);
    my $ha       = $self->ebt->get_hit_analysis ($hit_list);

    my $longest;
    my $oldest;
    foreach my $hit (@{ $ha->{'longest'} }) {
        $hit->{'serial'} =~ s/^([A-Z])....(....)...$/$1xxxx$2xxx/;
        push @$longest, $hit;
    }
    foreach my $hit (@{ $ha->{'oldest'} }) {
        $hit->{'serial'} =~ s/^([A-Z])....(....)...$/$1xxxx$2xxx/;
        push @$oldest, $hit;
    }

    $self->stash (
        longest => $longest,
        oldest  => $oldest,
        whoami  => $whoami,
    );
}

sub hit_summary {
    my ($self) = @_;

    my $whoami       = $self->ebt->whoami;
    my $activity     = $self->ebt->get_activity;
    my $count        = $self->ebt->get_count;
    my $hit_list     = $self->ebt->get_hit_list ($whoami);
    my $hs           = $self->ebt->get_hit_summary ($whoami, $activity, $count, $hit_list);

    foreach my $combo (keys %{ $hs->{'hits_by_combo'} }) {
        $hs->{'hits_by_combo'}{$combo}{'pcflag'} = EBT2->flag (EBT2->printers  ($hs->{'hits_by_combo'}{$combo}{'pc'})),
        $hs->{'hits_by_combo'}{$combo}{'ccflag'} = EBT2->flag (EBT2->countries ($hs->{'hits_by_combo'}{$combo}{'cc'})),
    }

    $self->stash (
        hs => $hs,
    );
}

## both gunzip and unzip appear to accept already uncompressed data, which makes things easier: just blindly uncompress everything
sub _decompress {
    my ($self, $file) = @_;
    my ($fd, $tmpfile);

    ($fd, $tmpfile) = tempfile 'ebtst-uncompress.XXXXXX', DIR => $ENV{'TMP'}//$ENV{'TEMP'}//'/tmp';
    if (!gunzip $file, $fd, AutoClose => 1) {
        $self->_log (warn => "_decompress: gunzip: $GunzipError");
        unlink $tmpfile or $self->_log (warn => "_decompress: unlink: '$tmpfile': $!");
    } else {
        rename $tmpfile, $file or $self->_log (warn => "_decompress: rename: '$tmpfile' to '$file': $!");
    }

    ($fd, $tmpfile) = tempfile 'ebtst-uncompress.XXXXXX', DIR => $ENV{'TMP'}//$ENV{'TEMP'}//'/tmp';
    if (!unzip $file, $fd, AutoClose => 1) {
        $self->_log (warn => "_decompress: unzip: $UnzipError");
        unlink $tmpfile or $self->_log (warn => "_decompress: unlink: '$tmpfile': $!");
    } else {
        rename $tmpfile, $file or $self->_log (warn => "_decompress: rename: '$tmpfile' to '$file': $!");
    }

    return;
}

sub upload {
    my ($self) = @_;

    my $notes_csv = $self->req->upload ('notes_csv_file');
    my $hits_csv  = $self->req->upload ('hits_csv_file');
    if ($notes_csv and $notes_csv->size) {
        my $local_notes_file = File::Spec->catfile ($ENV{'TMP'}//$ENV{'TEMP'}//'/tmp', 'notes_uploaded.csv');
        my $outfile = File::Spec->catfile ($EBTST::config{'csvs_dir'}, int rand 1e7);
        $notes_csv->move_to ($local_notes_file);
        $self->_decompress ($local_notes_file);
        $self->_log (info => "will store a censored copy at '$outfile'");
        $self->ebt->load_notes ($local_notes_file, $outfile);
        unlink $local_notes_file or $self->_log (warn => "upload: unlink: '$local_notes_file': $!\n");
    }
    if ($hits_csv and $hits_csv->size) {
        my $local_hits_file = File::Spec->catfile ($ENV{'TMP'}//$ENV{'TEMP'}//'/tmp', 'hits_uploaded.csv');
        $hits_csv->move_to ($local_hits_file);
        $self->_decompress ($local_hits_file);
        $self->ebt->load_hits ($local_hits_file);
        unlink $local_hits_file  or $self->_log (warn => "upload: unlink: '$local_hits_file': $!\n");
    }

    $self->redirect_to ('information');
}

sub _prepare_html_dir {
    my ($self, $statics_dir, $dest_dir) = @_;

    if (!defined unlink glob "$dest_dir/*") {
        if (2 != $!) {
            die "unlink: $!";
        }
    }

    if (!rmdir $dest_dir) {
        if (2 != $!) {
            die "rmdir: '$dest_dir': $!";
        }
    }

    if (!mkdir $dest_dir) {
        if (17 != $!) {   ## "File exists"
            die "Couldn't create directory: '$dest_dir': $!\n";
        }
    }

    my $src_img_dir  = File::Spec->catfile ($statics_dir,  'images');
    my $src_css      = File::Spec->catfile ($statics_dir,  'ebt.css');
    my $dest_img_dir = File::Spec->catfile ($dest_dir, 'images');
    my $dest_css     = File::Spec->catfile ($dest_dir, 'ebt.css');
    symlink $src_img_dir, $dest_img_dir or $self->_log (warn => "_prepare_html_dir: symlink: '$src_img_dir' to '$dest_img_dir': $!");
    symlink $src_css, $dest_css         or $self->_log (warn => "_prepare_html_dir: symlink: '$src_css' to '$dest_css': $!");

    return;
}

sub _save_html {
    my ($self, $html_dir, $html_text, @req_params) = @_;

    my $index_symlink_done = 0;
    foreach my $param (@req_params) {
        my $partial_html = encode 'UTF-8', $self->render_partial (template => "main/$param", format => 'html');
        my $html_copy = $html_text;
        $html_copy =~ s/<!-- content -->/$partial_html/;

        my $file = File::Spec->catfile ($html_dir, "$param.html");
        if (open my $fd, '>', $file) {
            print $fd $html_copy or $self->_log (warn => "_save_html: print: '$file': $!");
            close $fd            or $self->_log (warn => "_save_html: close: '$file': $!");

            if (!$index_symlink_done) {
                my $index_html = File::Spec->catfile ($html_dir, 'index.html');
                symlink "$param.html", $index_html or $self->_log (warn => "_save_html: symlink: '$param.html' to '$index_html': $!");
                $index_symlink_done = 1;
            }
        } else {
            $self->_log (warn => "_save_html: open: '$file': $!");
        }
    }

    return;
}

## remove entries in class #sections which don't appear in @req_params
sub _trim_html_sections {
    my ($self, $html, @req_params) = @_;

    my $dom = Mojo::DOM->new ($html);
    my $sections = $dom->at ('#sections');
    foreach my $tr ($sections->find ('tr')->each) {
        my $id = $tr->td->a->{'id'};
        unless (grep { $_ eq $id } @req_params) {
            $tr->replace ('');
        }
    }
    return $dom->to_xml;
}

sub gen_output {
    my ($self) = @_;
    my @params = qw/
        information value countries locations printers huge_table short_codes nice_serials
        coords_bingo notes_per_year notes_per_month top_days time_analysis combs_bingo combs_detail
        plate_bingo bad_notes hit_list hit_times hit_analysis hit_summary
    /;

    my @req_params = grep { $self->param ($_) } @params;
    @req_params = 'information' unless @req_params;
    $self->ebt->set_checked_boxes (@req_params);

    my $html_dir = File::Spec->catfile ($self->stash ('html_dir'), $self->stash ('user'));
    $self->_log (debug => "gen_output: req_params '@req_params', html_dir '$html_dir'");
    $self->_prepare_html_dir ($self->stash ('statics_dir'), $html_dir);
    my $html_output = encode 'UTF-8', $self->render_partial (template => 'layouts/offline', format => 'html');
    $html_output = $self->_trim_html_sections ($html_output, @req_params);

    $self->$_ for @req_params;

    $self->_save_html ($html_dir, $html_output, @req_params);

    my @rendered_bbcode;
    foreach my $param (@req_params) {
        ## bbcode: store in memory for later output
        ## missing templates yield an undef result
        my $r = encode 'UTF-8', $self->render_partial (template => "main/$param", format => 'txt');
        push @rendered_bbcode, $r;

    }

    ## now output stored bbcode
    my $body = join "\n\n", grep defined, @rendered_bbcode;
    $self->res->headers->content_type ('text/plain; charset=utf-8');
    $self->res->body ($body);
    $self->rendered (200);
}

1;

__END__

## 20120102: ugh, comento esto porque me sale:
## 'Undefined subroutine &MooseX::Types::filter_tags called at /usr/share/perl5/MooseX/Types.pm line 345'
## y como consecuencia no puedo usar EBT::OFC2
#sub evolution {
#    my ($self) = @_;
#
#    my $stats;
#    if ($self->param ('interval_what')) {
#        my $interval = 'all' eq  $self->param ('interval_what') ?
#            'all' :
#            $self->param ('interval_num') . $self->param ('interval_what');
#
#        my $filter;
#        if (my $v = $self->param ('filter_val')) {
#            $filter->{ lc $self->param ('filter_what') } = $v;
#        }
#
#        my $group_by = lc $self->param ('group_by')||undef;
#        my @show_only = split ',', $self->param ('show_only');
#        my $output = $self->param ('output');
#
#        $self->ebt->note_evolution ($interval, $filter, $group_by, \@show_only, $output);
#        my $data = $self->ebt->get_note_evolution;
#        foreach my $chunk (@$data) {
#            my $sd = $chunk->{'start_date'}; $sd =~ s/-//g;
#            $stats->{$sd} = $chunk->{'val'};
#        }
#    }
#
#    $self->flash (in => 'evolution');
#    if ($stats) {
#        my ($knames, $all_data) = EBT::OFC2::gen_json_data 'f0f0f0', 'some title', $stats;
#        my $js_blob = EBT::OFC2::create_js_blob $all_data, 790, 500, 'ofc2';
#
#        $self->stash (
#            form_name => (join '', map { chr 97 + int rand 26 } 1..10),
#            js_blob   => $js_blob,
#            knames    => $knames,
#        );
#    } else {
#        $self->stash (
#            form_name => (join '', map { chr 97 + int rand 26 } 1..10),
#            js_blob   => '',
#            knames    => [],
#        );
#    }
#}

1;
