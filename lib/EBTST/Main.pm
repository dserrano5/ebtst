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

my %section_titles;
foreach my $section (qw/
    index information value countries locations travel_stats printers huge_table short_codes nice_serials
    top_days plate_bingo bad_notes hit_list hit_analysis hit_summary help
/) {
    my $title = ucfirst $section;
    $title =~ s/_/ /g;
    $section_titles{$section} = $title;
}
%section_titles = (
    %section_titles,
    notes_per_year       => 'Notes/year',
    notes_per_month      => 'Notes/month',
    coords_bingo         => 'Coordinates bingo',
    time_analysis_bingo  => 'Time analysis (bingo)',
    time_analysis_detail => 'Time analysis (detail)',
    combs_bingo          => 'Combinations (bingo)',
    combs_detail         => 'Combinations (detail)',
    hit_times_bingo      => 'Hit times (bingo)',
    hit_times_detail     => 'Hit times (detail)',
    configure            => 'Configuration',
    bbcode               => 'BBCode',
);

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
    $self->stash (title => $section_titles{'index'});
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
    my $notes_dates = $self->ebt->get_notes_dates;
    my $elem_by_pres = $self->ebt->get_elem_notes_by_president;

    my $avg_value   = $total_value / $count;
    my $wd          = $sigs->{'WD'}   // 0;
    my $jct         = $sigs->{'JCT'}  // 0;
    my $md          = $sigs->{'MD'}   // 0;
    my $unk         = $sigs->{'_UNK'} // 0;
    my $today       = DateTime->now->set_time_zone ('Europe/Madrid')->strftime ('%Y-%m-%d %H:%M:%S');
    my $avg_per_day = $count / $full_days;

    my $dest_img = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'pct_by_pres.svg');
    if (!-e $dest_img) {
        my @initials_pres = map { (split /:/)[0] } @{ EBT2->presidents };
        my %dpoints;
        foreach my $elem (map { (split ' ')[0] } split ',', $elem_by_pres) {
            push @{ $dpoints{$_} }, ($dpoints{$_}[-1]//0) for 'Total', @initials_pres;
            $dpoints{'Total'}[-1]++;
            $dpoints{$elem}[-1]++ if '_UNK' ne $elem;
        }

        my $dest_img = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'pct_by_pres.svg');
        EBTST::Main::Gnuplot::bartime_chart
            output => $dest_img,
            xdata => $notes_dates,
            percent => 1,
            dsets => [
                { title =>    'WD', color => '#FF4040', points => $dpoints{'WD'}  },
                { title =>   'JCT', color => '#4040FF', points => $dpoints{'JCT'} },
                { title =>    'MD', color => '#40FF40', points => $dpoints{'MD'}  },
            ];
    }

    $self->stash (
        title        => $section_titles{'information'},
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
    my $data_first = $self->ebt->get_first_by_value;
    my $notes_dates = $self->ebt->get_notes_dates;          ## for the chart
    my $elem_by_val = $self->ebt->get_elem_notes_by_value;  ## for the chart
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

    my $first_by;
    foreach my $value (sort { $data_first->{$a}{'at'} <=> $data_first->{$b}{'at'} } keys %$data_first) {
        push @$first_by, {
            value => $value,
            at       => $data_first->{$value}{'at'},
            on       => (split ' ', $data_first->{$value}{'date_entered'})[0],
            city     => $data_first->{$value}{'city'},
            imgname2 => $data_first->{$value}{'country'},
            bbflag2  => EBT2->flag ($data_first->{$value}{'country'}),
        };
    }

    ## charts
    my $dest_img1 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'acum_by_val.svg');
    my $dest_img2 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'pct_by_val.svg');
    my $dest_img3 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'dev_of_mean.svg');
    if (!-e $dest_img1 or !-e $dest_img2 or !-e $dest_img3) {
        my %dpoints;
        my ($avg_sum, $avg_count);
        foreach my $elem (split ',', $elem_by_val) {
            push @{ $dpoints{$_} }, ($dpoints{$_}[-1]//0) for qw/Total Mean/, @{ EBT2->values };
            $dpoints{'Total'}[-1]++;
            $dpoints{$elem}[-1]++;
            $avg_sum += $elem;
            $dpoints{'Mean'}[-1] = $avg_sum/++$avg_count;
        }
        ## overwrite values with their percentages
        #foreach my $idx (0..$#$notes_dates) {
        #    foreach my $v (@{ EBT2->values }) {
        #        $dpoints{$v}[$idx] = 100 * ($dpoints{$v}[$idx]//0) / $dpoints{'Total'}[$idx];
        #    }
        #}
        -e $dest_img1 or EBTST::Main::Gnuplot::line_chart
            output => $dest_img1,
            xdata => $notes_dates,
            dsets => [
                { title => 'Total', color => 'black',  points => $dpoints{'Total'} },
                { title =>     '5', color => 'grey',   points => $dpoints{'5'}   },
                { title =>    '10', color => 'red',    points => $dpoints{'10'}  },
                { title =>    '20', color => 'blue',   points => $dpoints{'20'}  },
                { title =>    '50', color => 'orange', points => $dpoints{'50'}  },
                { title =>   '100', color => 'green',  points => $dpoints{'100'} },
                { title =>   '200', color => 'yellow', points => $dpoints{'200'} },
                { title =>   '500', color => 'purple', points => $dpoints{'500'} },
            ];

        -e $dest_img2 or EBTST::Main::Gnuplot::bartime_chart
            output => $dest_img2,
            xdata => $notes_dates,
            percent => 1,
            dsets => [
                { title =>     '5', color => 'grey',    points => $dpoints{'5'}   },
                { title =>    '10', color => '#FF4040', points => $dpoints{'10'}  },
                { title =>    '20', color => '#4040FF', points => $dpoints{'20'}  },
                { title =>    '50', color => '#FFC040', points => $dpoints{'50'}  },
                { title =>   '100', color => '#40FF40', points => $dpoints{'100'} },
                { title =>   '200', color => '#FFFF40', points => $dpoints{'200'} },
                { title =>   '500', color => '#FF40FF', points => $dpoints{'500'} },
            ];

        -e $dest_img3 or EBTST::Main::Gnuplot::line_chart
            output => $dest_img3,
            xdata => $notes_dates,
            dsets => [
                { title => 'Average value', color => 'black', points => $dpoints{'Mean'} },
            ];
    }

    $self->stash (
        title => $section_titles{'value'},
        nbval => $notes_by_val,
        fbval => $first_by,
    );
}

sub _num_detail_1st {
    my ($self, %args) = @_;

    my ($data, $data_first, $method1, $method2, $notes_by_key) = @args{qw/data data_first method1 method2 notes_by_key/};

    my $count = $self->ebt->get_count;
    my $count_by_value;

    for my $code1 (sort {
        ($data->{$b}{'total'}//0) <=> ($data->{$a}{'total'}//0) ||
        $a cmp $b
    } keys %$data) {
        for my $v (grep { /^\d+$/ } keys %{ $data->{$code1} }) {
            $count_by_value->{$v} += $data->{$code1}{$v};
        }
    }

    my $notes_by;
    foreach my $code1 (sort {
        ($data->{$b}{'total'}//0) <=> ($data->{$a}{'total'}//0) ||
        $a cmp $b
    } keys %{ EBT2->$method1 }) {
        my $detail;
        for my $v (@{ EBT2->values }) {
            my $exists = 0;
            foreach my $code2 (keys %{ EBT2->$method2 }) {
                my $k;
                if ('countries' eq $method1) {
                    $k = sprintf '%s%s%03d', $code2, $code1, $v;
                } else {
                    $k = sprintf '%s%s%03d', $code1, $code2, $v;
                }
                if (exists $EBT2::combs_pc_cc_val{$k}) {
                    $exists = 1;
                    last;
                }
            }
            if ($exists) {
                if ($data->{$code1}{$v}) {
                    push @$detail, {
                        count => $data->{$code1}{$v},
                        pct   => (sprintf '%.2f', 100 * $data->{$code1}{$v} / $count_by_value->{$v}),
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
        push @$notes_by, {
            cname   => $self->_country_names (EBT2->$method1 ($code1)),
            imgname => EBT2->$method1 ($code1),
            bbflag  => EBT2->flag (EBT2->$method1 ($code1)),
            $notes_by_key => $code1,
            count   => ($data->{$code1}{'total'}//0),
            pct     => (sprintf '%.2f', 100 * ($data->{$code1}{'total'}//0) / $count),
            detail  => $detail,
        };
    }

    my $first_by;
    foreach my $code1 (sort { $data_first->{$a}{'at'} <=> $data_first->{$b}{'at'} } keys %$data_first) {
        push @$first_by, {
            (
                'countries' eq $method1 ?
                (cname => $self->_country_names (EBT2->$method1 ($code1))) :
                (pc => $code1)
            ),
            at       => $data_first->{$code1}{'at'},
            imgname  => EBT2->$method1 ($code1),
            bbflag   => EBT2->flag (EBT2->$method1 ($code1)),
            value    => $data_first->{$code1}{'value'},
            on       => (split ' ', $data_first->{$code1}{'date_entered'})[0],
            city     => $data_first->{$code1}{'city'},
            imgname2 => $data_first->{$code1}{'country'},
            bbflag2  => EBT2->flag ($data_first->{$code1}{'country'}),
        };
    }

    return $notes_by, $count_by_value, $first_by;
}

sub countries {
    my ($self) = @_;

    my $data      = $self->ebt->get_notes_by_cc;
    my $data_first = $self->ebt->get_first_by_cc;
    my ($method1, $method2) = qw/countries printers/;
    my $notes_by_key = 'cc';

    my ($notes_by, $count_by_value, $first_by) = $self->_num_detail_1st (
        data         => $data,
        data_first   => $data_first,
        method1      => 'countries',
        method2      => 'printers',
        notes_by_key => 'cc',
    );

    $self->stash (
        title     => $section_titles{'countries'},
        nbcountry => $notes_by,
        tot_c_bv  => [ map { $count_by_value->{$_}//0 } @{ EBT2->values } ],
        fbcc      => $first_by,
    );
}

sub printers {
    my ($self) = @_;

    my $data      = $self->ebt->get_notes_by_pc;
    my $data_first = $self->ebt->get_first_by_pc;
    my ($method1, $method2) = qw/printers countries/;
    my $notes_by_key = 'pc';

    my ($notes_by, $count_by_value, $first_by) = $self->_num_detail_1st (
        data         => $data,
        data_first   => $data_first,
        method1      => 'printers',
        method2      => 'countries',
        notes_by_key => 'pc',
    );

    $self->stash (
        title     => $section_titles{'printers'},
        nbprinter => $notes_by,
        tot_p_bv  => [ map { $count_by_value->{$_}//0 } @{ EBT2->values } ],
        fbpc      => $first_by,
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
        title     => $section_titles{'locations'},
        num_co    => scalar keys %$nbco,
        countries => $countries,
        num_locs  => $distinct_cities,
        c_data    => $c_data,
        ab        => $ab,
    );
}

sub travel_stats {
    my ($self) = @_;

    my $travel_stats = $self->ebt->get_travel_stats;
    my $notes_dates = $self->ebt->get_notes_dates;          ## for the chart
    my $elem_by_city = $self->ebt->get_elem_notes_by_city;  ## for the chart

    my %unique_years;
    my ($num_locs, $yearly_visits, $one_time_visits);
    foreach my $location (keys %$travel_stats) {
        my @years = keys %{ $travel_stats->{$location}{'visits'} };
        $unique_years{$_} = undef for @years;

        $num_locs++;
        $yearly_visits += @years;
        $one_time_visits++ if 1 == @years;
    }

    ## chart
    my $dest_img = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'travel_stats.svg');
    if (!-e $dest_img) {
        my @_8best = grep defined, (reverse sort { $travel_stats->{$a}{'total'} <=> $travel_stats->{$b}{'total'}} keys %$travel_stats)[0..7];
        my %dpoints;
        foreach my $elem (split ',', $elem_by_city) {
            push @{ $dpoints{$_} }, ($dpoints{$_}[-1]//0) for @_8best;
            next unless grep { $_ eq $elem } @_8best;
            $dpoints{$elem}[-1]++;
        }

        my @colors = ('red', 'blue', '#FFCF00', 'green', 'magenta', '#808000', '#000080', '#008080');
        my @dsets = map {
            defined $_8best[$_] ?
                { title => (encode 'UTF-8', $_8best[$_]), color => $colors[$_], points => $dpoints{ $_8best[$_] } } :
                ()
        } 0..7;

        EBTST::Main::Gnuplot::line_chart
            output => $dest_img,
            xdata => $notes_dates,
            logscale => 'y',
            dsets => \@dsets;
    }

    $self->stash (
        title           => $section_titles{'travel_stats'},
        years           => [ sort keys %unique_years ],
        travel_stats    => $travel_stats,
        num_locs        => $num_locs,
        yearly_visits   => $yearly_visits,
        one_time_visits => $one_time_visits,
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
        title => $section_titles{'huge_table'},
        ht    => $ht,
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
                    recent  => $records->{$what}{'recent'},
                };
            }
            push @{ $sc->{$v} }, $tmp;

            #if (!defined $lo->{$pc}{$v}{'sort_key'}) {
            #    next;
            #}
        }
    }

    $self->stash (
        title => $section_titles{'short_codes'},
        sc    => $sc,
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
            recent  => $n->{'recent'},
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
        title            => $section_titles{'nice_serials'},
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
        title  => $section_titles{'coords_bingo'},
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
        title => $section_titles{'notes_per_year'},
        nby   => $nby,
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
        title => $section_titles{'notes_per_month'},
        nbm   => $nbm,
    );
}

sub top_days {
    my ($self) = @_;

    my $t10d_data = $self->ebt->get_top10days;
    my $t10m_data = $self->ebt->get_top10months;
    my $nbdow_data = $self->ebt->get_notes_by_dow;
    my $count = $self->ebt->get_count;

    my $nbdow;
    my %dpoints;
    foreach my $dow (1..7) {
        my $detail;
        foreach my $v (@{ EBT2->values }) {
            push @$detail, {
                value => $v,
                count => $nbdow_data->{$dow}{$v},
            };
            push @{ $dpoints{$v} }, ($nbdow_data->{$dow}{$v}//0);
        }
        my $tot = $nbdow_data->{$dow}{'total'} // 0;
        push @$nbdow, {
            dow    => $dows{$dow},
            count  => $tot,
            pct    => (sprintf '%.2f', 100 * $tot / $count),
            detail => $detail,
        };
    }

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

    my $t10m;
    foreach my $m (
        sort {
            $t10m_data->{$b}{'total'} <=> $t10m_data->{$a}{'total'} or
            $a cmp $b
        } keys %$t10m_data
    ) {
        my $detail;
        foreach my $v (@{ EBT2->values }) {
            push @$detail, {
                value => $v,
                count => $t10m_data->{$m}{$v},
            };
        }
        my $tot = $t10m_data->{$m}{'total'};
        push @$t10m, {
            date   => $m,
            count  => $tot,
            pct    => (sprintf '%.2f', 100 * $tot / $count),
            detail => $detail,
        };
    }

    my $dest_img = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'week_days.svg');
    -e $dest_img or EBTST::Main::Gnuplot::bar_chart
        output     => $dest_img,
        labels     => [ map { encode 'UTF-8', $self->l ($_) } qw/Monday Tuesday Wednesday Thursday Friday Saturday Sunday/ ],
        bar_border => 1,
        dsets => [
            { title =>     '5', color => 'grey',    points => $dpoints{'5'}   },
            { title =>    '10', color => '#FF4040', points => $dpoints{'10'}  },
            { title =>    '20', color => '#4040FF', points => $dpoints{'20'}  },
            { title =>    '50', color => '#FFC040', points => $dpoints{'50'}  },
            { title =>   '100', color => '#40FF40', points => $dpoints{'100'} },
            { title =>   '200', color => '#FFFF40', points => $dpoints{'200'} },
            { title =>   '500', color => '#FF40FF', points => $dpoints{'500'} },
        ];

    $self->stash (
        title => $section_titles{'top_days'},
        nbdow => $nbdow,
        t10d  => $t10d,
        t10m  => $t10m,
    );
}

sub time_analysis_bingo {
    my ($self, $detail) = @_;

    my $count   = $self->ebt->get_count;
    my $ta_data = $self->ebt->get_time_analysis;

    $self->stash (
        title    => ($detail ? $section_titles{'time_analysis_detail'} : $section_titles{'time_analysis_bingo'}),
        ta_count => $count,
        ta       => $ta_data,
    );
}
sub time_analysis_detail { push @_, 1; goto &time_analysis_bingo; }

sub combs_bingo {
    my ($self, $detail) = @_;

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
        title      => ($detail ? $section_titles{'combs_detail'} : $section_titles{'combs_bingo'}),
        nbcombo    => $nbcombo,
        presidents => $presidents,
        missing    => $missing,
        history    => $comb_data->{'history'},
        count      => $count,
    );
}
sub combs_detail { push @_, 1; goto &combs_bingo; }

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

    $self->stash (
        title       => $section_titles{'plate_bingo'},
        plate_bingo => $cooked,
    );
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
        title     => $section_titles{'bad_notes'},
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
        title    => $section_titles{'hit_list'},
        hit_list => $cooked,
        whoami   => $whoami,
    );
}

sub hit_times_bingo {
    my ($self, $detail) = @_;

    my $whoami   = $self->ebt->whoami;
    my $hit_list = $self->ebt->get_hit_list ($whoami);
    my $ht       = $self->ebt->get_hit_times ($hit_list);

    $self->stash (
        title           => ($detail ? $section_titles{'hit_times_detail'} : $section_titles{'hit_times_bingo'}),
        hit_times_count => (scalar grep { !$_->{'moderated'} } @$hit_list),
        hit_times       => $ht,
    );
}
sub hit_times_detail { push @_, 1; goto &hit_times_bingo; }

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
        title   => $section_titles{'hit_analysis'},
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
    my $notes_dates  = $self->ebt->get_notes_dates;         ## for the chart
    my $hits_dates   = $self->ebt->get_hits_dates;          ## for the chart
    my $elem_travel_days = $self->ebt->get_elem_travel_days;
    my $elem_travel_km   = $self->ebt->get_elem_travel_km;

    foreach my $combo (keys %{ $hs->{'hits_by_combo'} }) {
        $hs->{'hits_by_combo'}{$combo}{'pcflag'} = EBT2->flag (EBT2->printers  ($hs->{'hits_by_combo'}{$combo}{'pc'})),
        $hs->{'hits_by_combo'}{$combo}{'ccflag'} = EBT2->flag (EBT2->countries ($hs->{'hits_by_combo'}{$combo}{'cc'})),
    }

    ## chart
    my $dest_img1 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'hits_ratio.svg');
    my $dest_img2 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'hits_travel_days.svg');
    my $dest_img3 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'hits_travel_km.svg');
    if (!-e $dest_img1 or !-e $dest_img2 or !-e $dest_img3) {
        my %dpoints;

        my $hits_dates_idx = 0;
        my ($count_notes, $count_hits);
        foreach my $elem (@$notes_dates) {
            $count_notes++;
            if (defined $hits_dates->[$hits_dates_idx]) {
                my $cmp = $elem cmp $hits_dates->[$hits_dates_idx];
                if (-1 != $cmp) {
                    $count_hits++;
                    $hits_dates_idx++;
                }
            }
            push @{ $dpoints{'hit_ratio'} }, $count_hits ? $count_notes/$count_hits : undef;
        }

        my ($days_sum, $days_count);
        foreach my $elem (split ',', $elem_travel_days) {
            $days_sum += $elem;
            push @{ $dpoints{'travel_days'} }, $days_sum/++$days_count;
        }

        my ($km_sum, $km_count);
        foreach my $elem (split ',', $elem_travel_km) {
            $km_sum += $elem;
            push @{ $dpoints{'travel_km'} }, $km_sum/++$km_count;
        }

        -e $dest_img1 or EBTST::Main::Gnuplot::line_chart
            output => $dest_img1,
            xdata => $notes_dates,
            dsets => [
                { title => 'Hit ratio', color => 'black', points => $dpoints{'hit_ratio'} },
            ];

        -e $dest_img2 or EBTST::Main::Gnuplot::line_chart
            output => $dest_img2,
            xdata => $hits_dates,
            dsets => [
                { title => 'Travel days', color => 'black', points => $dpoints{'travel_days'} },
            ];

        -e $dest_img3 or EBTST::Main::Gnuplot::line_chart
            output => $dest_img3,
            xdata => $hits_dates,
            dsets => [
                { title => 'Travel km', color => 'black', points => $dpoints{'travel_km'} },
            ];
    }

    $self->stash (
        title => $section_titles{'hit_summary'},
        hs    => $hs,
    );
}

sub configure {
    my ($self) = @_;

    $self->stash (
        title => $section_titles{'configure'},
    );
}

sub help {
    my ($self) = @_;

    $self->stash (
        title => $section_titles{'help'},
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
        foreach my $img (glob File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), '*')) {
            unlink $img or $self->_log (warn => "upload: unlink: '$img': $!\n");
        }
    }
    if ($hits_csv and $hits_csv->size) {
        my $local_hits_file = File::Spec->catfile ($ENV{'TMP'}//$ENV{'TEMP'}//'/tmp', 'hits_uploaded.csv');
        $hits_csv->move_to ($local_hits_file);
        $self->_decompress ($local_hits_file);
        $self->ebt->load_hits ($local_hits_file);
        unlink $local_hits_file  or $self->_log (warn => "upload: unlink: '$local_hits_file': $!\n");
        foreach my $img (glob File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'hits_*')) {
            unlink $img or $self->_log (warn => "upload: unlink: '$img': $!\n");
        }
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
        my $title = encode 'UTF-8', $self->l ($section_titles{$param});
        my $html_copy = $html_text;
        $html_copy =~ s/<!-- content -->/$partial_html/;
        $html_copy =~ s/<!-- title -->/$title/;

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
        next unless $tr->td->can ('a');  ## ignore cell containing the username
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
        information value countries printers locations travel_stats huge_table short_codes nice_serials
        coords_bingo notes_per_year notes_per_month top_days time_analysis_bingo time_analysis_detail
        combs_bingo combs_detail plate_bingo bad_notes hit_list hit_times_bingo hit_times_detail
        hit_analysis hit_summary
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
        ## missing templates yield an undef result
        my $r = $self->render_partial (template => "main/$param", format => 'txt');
        push @rendered_bbcode, $r;

    }

    $self->stash (
        format => 'html',
        title  => $section_titles{'bbcode'},
        user   => undef,
        bbcode => (join "\n\n", grep defined, @rendered_bbcode),
        url    => $self->stash ('public_stats'),
    );
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
