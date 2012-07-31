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

my %users;
open my $fd, '<:encoding(UTF-8)', $EBTST::config{'users_db'} or die "open: '$EBTST::config{'users_db'}': $!";
while (<$fd>) {
    chomp;
    my ($u, $p) = split /:/;
    $users{$u} = $p;
}
close $fd;

sub index {
    my ($self) = @_;

    $self->redirect_to ('information') if ref $self->stash ('sess') and $self->stash ('sess')->load;
    $self->flash (requested_url => $self->flash ('requested_url'));
}

sub login {
    my ($self) = @_;

    if (
        exists $users{$self->param ('user')} and
        $users{$self->param ('user')} eq sha512_hex $self->param ('pass')
    ) {
        $self->stash ('sess')->create;
        $self->stash ('sess')->data (user => $self->param ('user'));
        my $dest = $self->param ('requested_url') || 'information';
        $self->redirect_to ($dest);
    } else {
        $self->redirect_to ('index');
    }
}

sub logout {
    my ($self) = @_;

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

    my $nbc;
    for my $cc (
        sort {
            ($data->{$b}{'total'}//0) <=> ($data->{$a}{'total'}//0) ||
            EBT2->country_names (EBT2->countries ($a)) cmp EBT2->country_names (EBT2->countries ($b))
        } keys %{ EBT2->countries }
    ) {
        my $detail;
        for my $v (@{ EBT2->values }) {
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
        }
        my $iso3166 = do { local $ENV{'EBT_LANG'} = 'en'; EBT2->countries ($cc) };
        push @$nbc, {
            cname   => EBT2->country_names (EBT2->countries ($cc)),
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
            cname    => EBT2->country_names (EBT2->countries ($cc)),
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
        nbc    => $nbc,
        #cbv    => $count_by_value,
        tot_bv => [ map { $count_by_value->{$_}//0 } @{ EBT2->values } ],
        fbcc   => $fbcc,
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
            cname   => EBT2->country_names ($iso3166),
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
            cname    => EBT2->country_names ($country),
            imgname  => $country,
            bbflag   => EBT2->flag ($country),
            loc_data => $loc_data,
        };
    }

    my $ab;
    foreach my $c (sort keys %$ab_data) {
        my $letters;
            
        for my $letter ('A'..'Z') {
            $letters->{$letter} = $ab_data->{$c}{$letter} // '';
        }

        push @$ab, {
            imgname => $c,
            cname   => EBT2->country_names ($c),
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
        }
        push @$nbp, {
            cname   => EBT2->country_names (EBT2->printers ($pc)),
            pname   => EBT2->printers2name ($pc),
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
            cname    => EBT2->country_names (EBT2->countries ($pc)),
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
                $tmp->{$what} = {
                    pc_img  => EBT2->printers ($pc),
                    pc_flag => EBT2->flag (EBT2->printers ($pc)),
                    cc_img  => EBT2->countries ($cc),
                    cc_flag => EBT2->flag (EBT2->countries ($cc)),
                    str     => (sprintf '%s/%s', $cook->($records->{$what}{'sort_key'})),
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
    foreach my $dow (sort keys %$nbdow_data) {
        my $detail;
        foreach my $v (@{ EBT2->values }) {
            push @$detail, {
                value => $v,
                count => $nbdow_data->{$dow}{$v},
            };
        }
        my $tot = $nbdow_data->{$dow}{'total'};
        push @$nbdow, {
            dow    => EBT2->dow_names($dow),
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

    $self->stash (
        nbdow => $nbdow,
        t10d  => $t10d,
    );
}

sub time_analysis {
    my ($self) = @_;

    my $ta_data = $self->ebt->get_time_analysis;

    $self->stash (
        ta => $ta_data,
    );
}

sub combs {
    my ($self) = @_;

    my $nbc        = $self->ebt->get_notes_by_combination;
    #my $sbp        = $self->ebt->sigs_by_president;
    my $comb_data  = $self->ebt->get_missing_combs_and_history;
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
        nbc        => $nbc,
        presidents => $presidents,
        missing    => $missing,
        history    => $comb_data->{'history'},
    );
}

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

    $self->stash (cooked => $cooked);
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
        cooked => $cooked,
        whoami => $whoami,
    );
}

sub hits_by_month {
    my ($self) = @_;

    my $activity = $self->ebt->get_activity;
    my $hit_list = $self->ebt->get_hit_list;

    my $hbm = $self->ebt->get_hits_by_month ($self->ebt->whoami, $activity, $hit_list);
    my $rows;
    foreach my $month (sort keys %{ $hbm->{'natural'} }) {
        push @$rows, {
            month   => $month,
            natural => $hbm->{'natural'}{$month},
            insert  => $hbm->{'insert'}{$month},
        };
    }

    $self->stash (n_hits => scalar @$hit_list, rows => $rows);
}

sub hit_analysis {
    my ($self) = @_;

    my $whoami   = $self->ebt->whoami;
    my $hit_list = $self->ebt->get_hit_list;

    my $ha = $self->ebt->get_hit_analysis ($hit_list);
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

## both gunzip and unzip appear to accept already uncompressed data, which makes things easier: just blindly uncompress everything
sub _decompress {
    my ($file) = @_;
    my ($fd, $tmpfile);

    ($fd, $tmpfile) = tempfile 'ebtst-uncompress.XXXXXX', DIR => $ENV{'TMP'}//$ENV{'TEMP'}//'/tmp';
    if (!gunzip $file, $fd, AutoClose => 1) {
        warn "gunzip: $GunzipError";
        unlink $tmpfile or warn "unlink: '$tmpfile': $!";
    } else {
        rename $tmpfile, $file or warn "rename: '$tmpfile' to '$file': $!";
    }

    ($fd, $tmpfile) = tempfile 'ebtst-uncompress.XXXXXX', DIR => $ENV{'TMP'}//$ENV{'TEMP'}//'/tmp';
    if (!unzip $file, $fd, AutoClose => 1) {
        warn "unzip: $UnzipError";
        unlink $tmpfile or warn "unlink: '$tmpfile': $!";
    } else {
        rename $tmpfile, $file or warn "rename: '$tmpfile' to '$file': $!";
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
        _decompress $local_notes_file;
        $self->ebt->load_notes ($local_notes_file, $outfile);
        unlink $local_notes_file or warn "unlink: '$local_notes_file': $!\n";
    }
    if ($hits_csv and $hits_csv->size) {
        my $local_hits_file = File::Spec->catfile ($ENV{'TMP'}//$ENV{'TEMP'}//'/tmp', 'hits_uploaded.csv');
        $hits_csv->move_to ($local_hits_file);
        _decompress $local_hits_file;
        $self->ebt->load_hits ($local_hits_file);
        unlink $local_hits_file  or warn "unlink: '$local_hits_file': $!\n";
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
    symlink $src_img_dir, $dest_img_dir or warn "symlink: '$src_img_dir' to '$dest_img_dir': $!";
    symlink $src_css, $dest_css         or warn "symlink: '$src_css' to '$dest_css': $!";

    return;
}

sub _save_html {
    my ($self, $param, $html_dir, $html, @req_params) = @_;

    my $file = File::Spec->catfile ($html_dir, "$param.html");
    if (open my $fd, '>', $file) {
        my $partial_html = encode 'UTF-8', $self->render_partial (template => "main/$param", format => 'html');

        $html =~ s/<!-- content -->/$partial_html/;

        print $fd $html or warn "print: '$file': $!";
        close $fd       or warn "close: '$file': $!";

        if ('information' eq $param) {
            my $index_html = File::Spec->catfile ($html_dir, 'index.html');
            symlink 'information.html', $index_html or warn "symlink: 'information.html' to '$index_html': $!";
        }
    } else {
        warn "open: '$file': $!";
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
        coords_bingo notes_per_year notes_per_month top_days time_analysis combs
        plate_bingo bad_notes hit_list hits_by_month hit_analysis
    /;

    my @req_params = grep { $self->param ($_) } @params;
    $self->ebt->set_checked_boxes (@req_params);

    my $html_dir = File::Spec->catfile ($self->stash ('html_dir'), $self->stash ('user'));
    $self->_prepare_html_dir ($self->stash ('statics_dir'), $html_dir);
    my $html_output = encode 'UTF-8', $self->render_partial (template => 'layouts/offline', format => 'html');
    $html_output = $self->_trim_html_sections ($html_output, @req_params);

    my @rendered_bbcode;
    foreach my $param (@req_params) {
        $self->$param;

        ## bbcode: store in memory for later output
        ## missing templates yield an undef result
        my $r = encode 'UTF-8', $self->render_partial (template => "main/$param", format => 'txt');
        push @rendered_bbcode, $r;

        ## html: save to file
        $self->_save_html ($param, $html_dir, $html_output, @req_params);
    }

    ## now output stored bbcode
    my $body = join "\n\n", grep defined, @rendered_bbcode;
    $self->res->headers->content_type ('text/plain; charset=utf-8');
    $self->res->body ($body);
    $self->rendered (200);
}

1;

__END__

sub help {
    my ($self) = @_;

    $self->flash (in => 'help');
}

sub quit {
    my ($self) = @_;

    #$self->render (text => 'bye!');
    #$self->res->headers->content_length (4); $self->write('bye!');
    exit;
}

sub huge_table {
    my ($self) = @_;

    $self->flash (in => 'huge_table');
}

sub time_analysis {
    my ($self) = @_;

    $self->flash (in => 'time_analysis');
}

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

sub bbcode {
    my ($self) = @_;

    $self->flash (in => 'bbcode');
}

sub charts {
    my ($self) = @_;

    $self->flash (in => 'charts');
}

1;
