package EBTST::Main;

use Mojo::Base 'Mojolicious::Controller';
use Encode qw/encode/;
use File::Spec;
use Digest::SHA qw/sha512_hex/;
use DateTime;
use List::Util qw/sum/;
use List::MoreUtils qw/uniq/;
use Storable qw/retrieve store/;
use IO::Uncompress::Gunzip qw/gunzip $GunzipError/;
use IO::Uncompress::Unzip  qw/unzip  $UnzipError/;
use File::Temp qw/tempfile/;
use File::Copy;
use Fcntl qw/:flock/;
use Locale::Country;
use Mojo::Cookie::Response;
use Mojo::UserAgent::CookieJar;
use Mojo::UserAgent;
use EBTST::Main::Gnuplot;
use EBTST::Main::Progress;

use Time::HiRes qw/tv_interval gettimeofday/;
sub report {
    my ($str, $t0, $n) = @_;
    my $t = tv_interval $t0;
    $n ||= 0;  ## no warnings uninit
    return sprintf +($n ? '%s: %.3fs (%s, %.0fK/s)' : '%s: %.3fs'), $str, $t, $n, $n/$t/1000;
}

my $tmpdir = $ENV{'TMP'} // $ENV{'TEMP'} // '/tmp';
our %dows = qw/1 Monday 2 Tuesday 3 Wednesday 4 Thursday 5 Friday 6 Saturday 7 Sunday/;
our %months = qw/1 January 2 February 3 March 4 April 5 May 6 June 7 July 8 August 9 September 10 October 11 November 12 December/;
## no need to list all english country names, we take them from Locale::Country
## with this hash we can override some of Locale::Country's names
## also used for countries present in EBT but not in the standard
my %country_names = (
    ru   => 'Russia',            ## instead of 'Russian Federation'
    va   => 'Vatican City',      ## instead of 'Holy See (Vatican City State)'
    ve   => 'Venezuela',         ## instead of 'Venezuela, Bolivarian Republic of'
);
my %users;

my %section_titles;
foreach my $section (qw/
    register information value countries locations regions travel_stats printers huge_table short_codes nice_serials
    top_days plate_bingo bad_notes hit_list hit_locations hit_regions hit_analysis hit_summary calendar help
/) {
    my $title = ucfirst $section;
    $title =~ s/_/ /g;
    $section_titles{$section} = $title;
}
%section_titles = (
    %section_titles,
    index                => 'Login',
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
    $self->app->log->$prio ($msg);
}

sub _country_names {
    my ($self, $what) = @_;

    if (!defined $what) {
        $self->_log (warn => sprintf "_country_names: undefined param, called from '%s'", (caller 1)[3]);
        return '';
    }

    my $ret;
    my $lang = substr +($ENV{'EBT_LANG'} || $ENV{'LANG'} || $ENV{'LANGUAGE'} || 'en'), 0, 2;

    $ret = $self->l ("iso3166_$what");
    if ('en' eq $lang or $ret =~ /^iso3166_/) {
        $ret = exists $country_names{$what} ? $country_names{$what} : code2country $what;
    }

    return $ret;
}

#sub _in_progress {
#    my ($self) = @_;
#    return $self->stash ('sess')->data ('_xhr_working');
#}

#sub _check_in_progress {
#    my ($self) = @_;
#    my $task;
#
#    $self->_log (debug => "in _check_in_progress");
#    return unless $task = $self->_in_progress;
#
#    if ($self->req->is_xhr) {
#        $self->_log (debug => "is xhr, task '$task' is running, ignoring request");
#        return $task;
#    }
#
#    $self->_log (debug => "is not xhr, task '$task' is running, waiting for completion");
#    while (1) {
#        sleep 5;
#        my $task2 = $self->_in_progress;
#        last if !$task2 or $task2 ne $task;
#        $self->_log (debug => "'$task' still running, waiting for completion");
#    }
#
#    $self->_log (debug => "'$task' completed, going on");
#    return;
#}

my %mults = (
    information   => 1.1,    ## graphs generation is relatively quick, hence that 0.1
    value         => 2.6,
    countries     => 2,
    printers      => 2,
    travel_stats  => 1.2,
    combs_bingo   => 2,
    combs_detail  => 2,
    hit_locations => 2,
    hit_summary   => 2.6,
);
$mults{'calc_sections'} = sum values %mults;

sub _init_progress {
    my ($self, %args) = @_;
    my $from = (split /::/, (caller 1)[3])[-1];

    my $tot = $args{'tot'} // ($self->ebt->get_count * ($mults{$from}//1));
    $self->_log (debug => sprintf "initializing progress for '$from', base (%s) tot ($tot)", $args{'base'}//'<undef>');

    #$self->stash ('sess')->data (_xhr_working => $from);
    #$self->stash ('sess')->flush;
    $self->ebt->set_progress_obj (
        $self->{'progress'} = EBTST::Main::Progress->new (sess => $self->stash ('sess'), tot => $tot, base => $args{'base'})
    );
    return;
}

sub _end_progress {
    my ($self, $text) = @_;

    $text //= 'ok';
    $self->ebt->del_progress_obj;
    #$self->stash ('sess')->clear ('_xhr_working');
    #$self->stash ('sess')->flush;
    $self->_log (debug => "_end_progress: rendering text ($text)");
    $self->render (text => $text, layout => undef, format => 'txt');
    return;
}

sub load_users {
    my ($self) = @_;

    my $users_file = $self->app->config ('users_db');
    open my $fd, '<:encoding(UTF-8)', $users_file or die "open: '$users_file': $!";
    flock $fd, LOCK_SH;
    while (<$fd>) {
        chomp;
        next if /^#/ or /^$/;
        my ($u, $p) = split /:/;
        $users{$u} = $p;
    }
    flock $fd, LOCK_UN;
    close $fd;

    $self->_log (debug => sprintf "load_users: loaded %d users", scalar keys %users);
}


sub index {
    my ($self) = @_;

    $self->flash (requested_url => $self->flash ('requested_url'));
    $self->stash (msg => $self->flash ('msg')//'');
    $self->stash (title => $section_titles{'index'});

    if ($self->req->is_xhr) {
        $self->render (layout => undef, text => 'ok');
    } else {
        $self->redirect_to ('information') if ref $self->stash ('sess') and $self->stash ('sess')->sid;
    }

    return;
}

sub login {
    my ($self) = @_;

    if (ref $self->stash ('sess') and $self->stash ('sess')->sid) {
        $self->redirect_to ('information');
        return;
    }

    $self->load_users;
    my $u = $self->param ('user');
    $self->_log (debug => sprintf "login: user is '%s'", $u//'<undef>');

    if (exists $users{$u}) {
        $self->_log (info => "login attempt for existing user '$u'");
        if ($users{$u} eq sha512_hex $self->param ('pass')) {
            $self->stash ('sess')->create;
            $self->stash ('sess')->data (user => $u);
            my $dest = $self->param ('requested_url') || 'information';
            $self->_log (info => "login successful, redirecting to '$dest'");
            $self->redirect_to ($dest);
            return;
        } else {
            $self->flash (msg => 'Wrong username/passphrase');
            $self->_log (info => 'login failed');
        }
    } else {
        $self->flash (msg => 'Wrong username/passphrase');
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

sub register {
    my ($self) = @_;

    if (ref $self->stash ('sess') and $self->stash ('sess')->sid) {
        $self->redirect_to ('information');
        return;
    }
    $self->stash (title => $section_titles{'register'});
    return if 'GET' eq $self->req->method;

    my $u  = $self->param ('user');
    my $p1 = $self->param ('pass1');
    my $p2 = $self->param ('pass2');
    if ($p1 ne $p2) {
        $self->_log (info => 'passwords do not match');
        $self->stash (msg => 'Passwords do not match');
        return;
    }

    $u =~ s/^\s+//; $u =~ s/\s+$//;

    if (!length $u or !length $p1) {
        $self->stash (msg => 'Empty user or password');
        return;
    }

    if (6 > length $p1) {
        $self->stash (msg => 'Password is too short');
        return;
    }

    my $invalid = 0;
    if ($u  =~ m{[<>&'"`/]}) { $self->_log (info => 'invalid username'); $invalid |= 1; }
    if ($p1 =~ m{[<>&'"`/]}) { $self->_log (info => 'invalid password'); $invalid |= 2; }
    if ($invalid) {
        if (1 == $invalid) {
            $self->stash (msg => 'Username contains invalid characters');
        } elsif (2 == $invalid) {
            $self->stash (msg => 'Password contains invalid characters');
        } else {
            $self->stash (msg => 'Username and password contain invalid characters');
        }
        return;
    }

    $self->load_users;
    if (exists $users{$u}) {
        $self->_log (info => "register attempt for existing user '$u'");
        $self->stash (msg => 'User already exists');
        return;
    }

    my $users_file = $self->app->config ('users_db');
    if (open my $fd, '>>:encoding(UTF-8)', $users_file) {
        flock $fd, LOCK_EX;
        printf $fd "%s:%s\n", $u, sha512_hex $p1;
        flock $fd, LOCK_UN;
        close $fd;
    } else {
        $self->_log (warn => "open: '$users_file': $!");
        $self->flash (msg => 'Error upon registration');
        return;
    }

    $self->stash ('sess')->create;
    $self->stash ('sess')->data (user => $u);
    $self->flash (msg => 'Registration successful');
    $self->_log (info => "new user '$u', redirecting to configure");
    $self->redirect_to ('configure');
    return;
}

sub progress {
    my ($self) = @_;

    #$self->_log (debug => sprintf "%s: progress called", scalar localtime);
    my ($p, $t) = split m{/}, $self->stash ('sess')->data ('progress') // '0/1';
    $self->_log (debug => "progress: p ($p) t ($t)");
    $self->res->headers->connection ('close');
    $self->render (layout => undef, json => { cur => $p, total => $t });
}

sub information {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count           = $self->ebt->get_count;                      $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $ac              = $self->ebt->get_activity;                   $xhr and $self->{'progress'}->base_add ($count);
    my $total_value     = $self->ebt->get_total_value;                ## (don't set progress, this has been already calculated and cached)
    my $sigs            = $self->ebt->get_signatures;                 ## already cached
    my $series          = $self->ebt->get_series;                     ## already cached
    my $full_days       = $self->ebt->get_days_elapsed;               ## already cached
    my $notes_dates     = $self->ebt->get_notes_dates;                ## already cached
    my $elem_by_pres    = $self->ebt->get_elem_notes_by_president;    ## already cached
    my $monthly_by_pres = $self->ebt->get_monthly_notes_by_president; ## already cached
    #$self->_log (debug => report 'information get', $t0, $count);

    $t0 = [gettimeofday];
    my $avg_value     = $total_value / $count;
    my $wd            = $sigs->{'WD'}   // 0;
    my $jct           = $sigs->{'JCT'}  // 0;
    my $md            = $sigs->{'MD'}   // 0;
    my $unk           = $sigs->{'_UNK'} // 0;
    my $series_2002   = $series->{'2002'} // 0;
    my $series_europa = $series->{'europa'} // 0;
    my $today         = DateTime->now->set_time_zone ('Europe/Madrid')->strftime ('%Y-%m-%d %H:%M:%S');
    my $avg_per_day   = $full_days ? $count / $full_days : undef;
    #$self->_log (debug => report 'information cook', $t0, $count);

    $t0 = [gettimeofday];
    my $dest_img1 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'pct_by_pres.svg');
    my $dest_img2 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'pct_by_pres_monthly.svg');
    if (!-e $dest_img1 or !-e $dest_img2) {
        my @initials_pres = map { (split /:/)[0] } @{ EBT2->presidents };

        my %dpoints;
        foreach my $elem (map { (split ' ')[0] } split ',', $elem_by_pres) {
            push @{ $dpoints{$_} }, ($dpoints{$_}[-1]//0) for 'Total', @initials_pres;
            $dpoints{'Total'}[-1]++;
            $dpoints{$elem}[-1]++ if '_UNK' ne $elem;
        }

        -e $dest_img1 or EBTST::Main::Gnuplot::bartime_chart
            output => (encode 'UTF-8', $dest_img1),
            xdata => $notes_dates,
            title => (encode 'UTF-8', $self->l ('Historic percent notes by president')),
            percent => 1,
            dsets => [
                { title => 'WD',  color => '#FF4040', points => $dpoints{'WD'}  },
                { title => 'JCT', color => '#4040FF', points => $dpoints{'JCT'} },
                { title => 'MD',  color => '#40FF40', points => $dpoints{'MD'}  },
            ];

        my @labels_monthly;
        my %dpoints_monthly;
        my ($y, $m) = split /-/, (sort keys %$monthly_by_pres)[0];
        my $cursor = DateTime->new (year => $y, month => $m);
        my $now = DateTime->now;
        while (1) {
            my $ym = $cursor->strftime ('%Y-%m');
            push @labels_monthly, $ym;
            my $monthly_tot = 0;
            foreach my $pres (@initials_pres) {
                $monthly_tot += $monthly_by_pres->{$ym}{$pres} // 0;
            }
            foreach my $pres (@initials_pres) {
                push @{ $dpoints_monthly{$pres} }, $monthly_tot ? ($monthly_by_pres->{$ym}{$pres} // 0)*100/$monthly_tot : 0;
            }
            $cursor->add (months => 1);
            last if $cursor > $now;
        }
        ## empty some labels if there are too many of them to be properly displayed
        my @idxs_to_empty;
        if (@labels_monthly > 100) {
            @idxs_to_empty = grep { $_ % 3 } 0..$#labels_monthly;
        } elsif (@labels_monthly > 50) {
            @idxs_to_empty = grep { $_ % 2 } 0..$#labels_monthly;
        }
        @labels_monthly[@idxs_to_empty] = ('') x @idxs_to_empty;

        -e $dest_img2 or EBTST::Main::Gnuplot::bar_chart
            output     => (encode 'UTF-8', $dest_img2),
            labels     => \@labels_monthly,
            labels_rotate => 90,
            title => (encode 'UTF-8', $self->l ('Monthy percent notes by president')),
            bar_border => (@labels_monthly > 100 ? 0 : 1),
            dsets => [
                { title => 'WD',  color => '#FF4040', points => $dpoints_monthly{'WD'}  },
                { title => 'JCT', color => '#4040FF', points => $dpoints_monthly{'JCT'} },
                { title => 'MD',  color => '#40FF40', points => $dpoints_monthly{'MD'}  },
            ];
    }
    #$self->_log (debug => report 'information chart', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count*0.1);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $self->stash (
        title             => $section_titles{'information'},
        ac                => $ac,
        bbflag            => EBT2->flag ($ac->{'first_note'}{'country'}),
        today             => $today,
        full_days         => $full_days,
        count             => $count,
        total_value       => $total_value,
        avg_value         => (sprintf '%.2f', $avg_value),
        avg_per_day       => (sprintf '%.2f', $avg_per_day//0),
        sigs_wd           => $wd,
        sigs_jct          => $jct,
        sigs_md           => $md,
        sigs_unk          => $unk,
        sigs_wd_pct       => (sprintf '%.2f', 100 * $wd  / $count),
        sigs_jct_pct      => (sprintf '%.2f', 100 * $jct / $count),
        sigs_md_pct       => (sprintf '%.2f', 100 * $md  / $count),
        sigs_unk_pct      => (sprintf '%.2f', 100 * $unk / $count),
        series_2002       => $series_2002,
        series_europa     => $series_europa,
        series_2002_pct   => (sprintf '%.2f', 100 * $series_2002 / $count),
        series_europa_pct => (sprintf '%.2f', 100 * $series_europa / $count),
    );
}

sub value {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    #if ($self->_check_in_progress) {
    #    $self->_log (debug => 'value: oops me piro');
    #    $self->render (layout => undef, text => 'ko');
    #    return;
    #}
    #$self->_log (debug => 'value: _check_in_progress nos deja seguir');

    my $t0 = [gettimeofday];
    my $count       = $self->ebt->get_count;                $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $data        = $self->ebt->get_notes_by_value;       $xhr and $self->{'progress'}->base_add ($count);
    my $data_first  = $self->ebt->get_first_by_value;       $xhr and $self->{'progress'}->base_add ($count);
    my $notes_dates = $self->ebt->get_notes_dates;
    my $elem_by_val = $self->ebt->get_elem_notes_by_value;
    #$self->_log (debug => report 'value get', $t0, $count);

    $t0 = [gettimeofday];
    my $notes_by_val;
    foreach my $value (@{ EBT2->values }) {
        push @$notes_by_val, {
            value  => $value,
            count  => ($data->{$value}//0),
            pct    => (sprintf '%.2f', 100 * ($data->{$value}//0) / $count),
            amount => ($data->{$value}//0) * $value,
        };
    }

    my $first_by_val;
    foreach my $value (sort { $data_first->{$a}{'at'} <=> $data_first->{$b}{'at'} } keys %$data_first) {
        push @$first_by_val, {
            value    => $value,
            id       => $data_first->{$value}{'id'},
            at       => $data_first->{$value}{'at'},
            on       => (split ' ', $data_first->{$value}{'date_entered'})[0],
            city     => $data_first->{$value}{'city'},
            imgname2 => $data_first->{$value}{'country'},
            bbflag2  => EBT2->flag ($data_first->{$value}{'country'}),
        };
    }
    #$self->_log (debug => report 'value cook', $t0, $count);

    ## charts
    $t0 = [gettimeofday];
    my $dest_img1 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'acum_by_val.svg');
    my $dest_img2 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'pct_by_val.svg');
    my $dest_img3 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'dev_of_mean.svg');
    if (!-e $dest_img1 or !-e $dest_img2 or !-e $dest_img3) {
        my %dpoints;
        my ($avg_sum, $avg_count);
        foreach my $elem (split ',', $elem_by_val) {   ## FIXME: this loop is memory-hungry
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
            output => (encode 'UTF-8', $dest_img1),
            xdata => $notes_dates,
            title => (encode 'UTF-8', $self->l ('Accumulated notes by value')),
            dsets => [
                { title => (encode 'UTF-8', $self->l ('Total')), color => 'black',  points => $dpoints{'Total'} },
                { title =>                                  '5', color => 'grey',   points => $dpoints{'5'}   },
                { title =>                                 '10', color => 'red',    points => $dpoints{'10'}  },
                { title =>                                 '20', color => 'blue',   points => $dpoints{'20'}  },
                { title =>                                 '50', color => 'orange', points => $dpoints{'50'}  },
                { title =>                                '100', color => 'green',  points => $dpoints{'100'} },
                { title =>                                '200', color => 'yellow', points => $dpoints{'200'} },
                { title =>                                '500', color => 'purple', points => $dpoints{'500'} },
            ];
        $xhr and $self->{'progress'}->base_add ($count*0.2);

        -e $dest_img2 or EBTST::Main::Gnuplot::bartime_chart
            output => (encode 'UTF-8', $dest_img2),
            xdata => $notes_dates,
            title => (encode 'UTF-8', $self->l ('Historic percent notes by value')),
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
        $xhr and $self->{'progress'}->base_add ($count*0.2);

        -e $dest_img3 or EBTST::Main::Gnuplot::line_chart
            output => (encode 'UTF-8',  $dest_img3),
            xdata => $notes_dates,
            title => (encode 'UTF-8', $self->l ('Historic mean value')),
            dsets => [
                { title => (encode 'UTF-8', $self->l ('Average value')), color => 'black', points => $dpoints{'Mean'} },
            ];
    }
    #$self->_log (debug => report 'value chart', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count*0.2);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $self->stash (
        title => $section_titles{'value'},
        nbval => $notes_by_val,
        fbval => $first_by_val,
    );
}

sub countries {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count      = $self->ebt->get_count;        $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $data       = $self->ebt->get_notes_by_cc;  $xhr and $self->{'progress'}->base_add ($count);
    my $data_first = $self->ebt->get_first_by_cc;
    #$self->_log (debug => report 'countries get', $t0, $count);

    ## we could do this just after $self->ebt->get_first_by_cc
    ## but then we'd lose the $self->_log (debug => report) call
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my $count_by_value;
    foreach my $cc (sort {
        ($data->{$b}{'total'}//0) <=> ($data->{$a}{'total'}//0) ||
        $a cmp $b
    } keys %$data) {
        foreach my $v (grep { /^\d+$/ } keys %{ $data->{$cc} }) {
            $count_by_value->{$v} += $data->{$cc}{$v};
        }
    }

    my $notes_by_cc;
    foreach my $cc (sort {
        ($data->{$b}{'total'}//0) <=> ($data->{$a}{'total'}//0) ||
        $a cmp $b
    } keys %{ EBT2->countries }) {
        my $detail;
        foreach my $v (@{ EBT2->values }) {
            my $exists = 0;
            foreach my $series (keys %{ EBT2->printers }) {
                foreach my $pc (keys %{ EBT2->printers->{$series} }) {
                    my $k = sprintf '%s%s%s%03d', $series, $pc, $cc, $v;
                    if (exists $EBT2::combs_pc_cc_val{$k}) {
                        $exists = 1;
                        last;
                    }
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
        push @$notes_by_cc, {
            cname   => $self->_country_names (EBT2->countries ($cc)),
            imgname => EBT2->countries ($cc),
            bbflag  => EBT2->flag (EBT2->countries ($cc)),
            cc      => $cc,
            count   => ($data->{$cc}{'total'}//0),
            pct     => (sprintf '%.2f', 100 * ($data->{$cc}{'total'}//0) / $count),
            detail  => $detail,
        };
    }

    my $first_by_cc;
    foreach my $cc (sort { $data_first->{$a}{'at'} <=> $data_first->{$b}{'at'} } keys %$data_first) {
        push @$first_by_cc, {
            (cname => $self->_country_names (EBT2->countries ($cc))),
            at       => $data_first->{$cc}{'at'},
            id       => $data_first->{$cc}{'id'},
            imgname  => EBT2->countries ($cc),
            bbflag   => EBT2->flag (EBT2->countries ($cc)),
            value    => $data_first->{$cc}{'value'},
            on       => (split ' ', $data_first->{$cc}{'date_entered'})[0],
            city     => $data_first->{$cc}{'city'},
            imgname2 => $data_first->{$cc}{'country'},
            bbflag2  => EBT2->flag ($data_first->{$cc}{'country'}),
        };
    }
    #$self->_log (debug => report 'countries cook', $t0, $count);

    $self->stash (
        title     => $section_titles{'countries'},
        nbcountry => $notes_by_cc,
        tot_c_bv  => [ map { $count_by_value->{$_}//0 } @{ EBT2->values } ],
        fbcc      => $first_by_cc,
    );
}

sub printers {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count      = $self->ebt->get_count;        $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $data       = $self->ebt->get_notes_by_pc;  $xhr and $self->{'progress'}->base_add ($count);
    my $data_first = $self->ebt->get_first_by_pc;
    #$self->_log (debug => report 'printers get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my $count_by_value;
    foreach my $series (keys %$data) {
        foreach my $pc (sort {
            ($data->{$series}{$b}{'total'}//0) <=> ($data->{$series}{$a}{'total'}//0) ||
            $a cmp $b
        } keys %{ $data->{$series} }) {
            foreach my $v (grep { /^\d+$/ } keys %{ $data->{$series}{$pc} }) {
                $count_by_value->{$v} += $data->{$series}{$pc}{$v};
            }
        }
    }

    my $notes_by_pc;
    foreach my $series (keys %{ EBT2->printers }) {
        foreach my $pc (keys %{ EBT2->printers->{$series} }) {
            my $detail;
            foreach my $v (@{ EBT2->values }) {
                my $exists = 0;
                foreach my $cc (keys %{ EBT2->countries }) {
                    my $k = sprintf '%s%s%s%03d', $series, $pc, $cc, $v;
                    if (exists $EBT2::combs_pc_cc_val{$k}) {
                        $exists = 1;
                        last;
                    }
                }
                if ($exists) {
                    if ($data->{$series}{$pc}{$v}) {
                        push @$detail, {
                            count => $data->{$series}{$pc}{$v},
                            pct   => (sprintf '%.2f', 100 * $data->{$series}{$pc}{$v} / $count_by_value->{$v}),
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
            my ($printer_iso3166, $printer_name) = split /,/, EBT2->printers ($pc, $series);
            push @$notes_by_pc, {
                cname   => (sprintf '(%s) %s', ucfirst $series, $printer_name),
                imgname => $printer_iso3166,
                bbflag  => EBT2->flag ($printer_iso3166),
                pc      => $pc,
                count   => ($data->{$series}{$pc}{'total'}//0),
                pct     => (sprintf '%.2f', 100 * ($data->{$series}{$pc}{'total'}//0) / $count),
                detail  => $detail,
            };
        }
    }
    $notes_by_pc = [ sort {
        ($b->{'count'}//0) <=> ($a->{'count'}//0) ||
        $a->{'pc'}         cmp $b->{'pc'}         ||
        $a->{'imgname'}    cmp $b->{'imgname'}
    } @$notes_by_pc ];

    my $first_by_pc;
    foreach my $series (keys %$data_first) {
        my $dfs = $data_first->{$series};
        foreach my $pc (keys %$dfs) {
            my ($printer_iso3166, $printer_name) = split /,/, EBT2->printers ($pc, $series);
            push @$first_by_pc, {
                pc       => $pc,
                at       => $dfs->{$pc}{'at'},
                id       => $dfs->{$pc}{'id'},
                imgname  => $printer_iso3166,
                bbflag   => EBT2->flag ($printer_iso3166),
                value    => $dfs->{$pc}{'value'},
                on       => (split ' ', $dfs->{$pc}{'date_entered'})[0],
                city     => $dfs->{$pc}{'city'},
                imgname2 => $dfs->{$pc}{'country'},
                bbflag2  => EBT2->flag ($dfs->{$pc}{'country'}),
            };
        }
    }
    $first_by_pc = [ sort { $a->{'at'} <=> $b->{'at'} } @$first_by_pc ];
    #$self->_log (debug => report 'printers cook', $t0, $count);

    $self->stash (
        title     => $section_titles{'printers'},
        nbprinter => $notes_by_pc,
        tot_p_bv  => [ map { $count_by_value->{$_}//0 } @{ EBT2->values } ],
        fbpc      => $first_by_pc,
    );
}

sub locations {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count   = $self->ebt->get_count;             $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $nbco    = $self->ebt->get_notes_by_country;  ## already cached
    my $nbci    = $self->ebt->get_notes_by_city;     ## already cached
    my $ab_data = $self->ebt->get_alphabets;         ## already cached
    #$self->_log (debug => report 'locations get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my $countries;
    foreach my $iso3166 (
        sort {
            $nbco->{$b}{'total'} <=> $nbco->{$a}{'total'} or
            $a cmp $b
        } keys %$nbco
    ) {
        my $detail;
        foreach my $v (@{ EBT2->values }) {
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
        my @sorted_locs; { use locale; @sorted_locs = sort {
            $nbci->{$country}{$b}{'total'} <=> $nbci->{$country}{$a}{'total'} or
            $a cmp $b
        } keys %{ $nbci->{$country} }; }

        foreach my $loc (@sorted_locs) {
            my $detail;
            foreach my $v (@{ EBT2->values }) {
                push @$detail, {
                    value => $v,
                    count => $nbci->{$country}{$loc}{$v},
                };
            }
            push @$loc_data, {
                loc_name => $loc,
                id       => $nbci->{$country}{$loc}{'first_id'},
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
            
        foreach my $letter ('A'..'Z') {
            $letters->{$letter} = $ab_data->{$c}{$letter};
        }

        push @$ab, {
            imgname => $c,
            cname   => $self->_country_names ($c),
            tot     => (scalar keys %{ $ab_data->{$c} }),
            letters => $letters,
        };
    }
    #$self->_log (debug => report 'locations cook', $t0, $count);

    my $url = $self->url_for;
    $url = '' if $url =~ /gen_output_/;
    $self->stash (
        title     => $section_titles{'locations'},
        num_co    => scalar keys %$nbco,
        countries => $countries,
        num_locs  => $distinct_cities,
        c_data    => $c_data,
        ab        => $ab,
        url       => $url,
    );
}

sub regions {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count       = $self->ebt->get_count;              $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $region_data = $self->ebt->get_regions;            $xhr and $self->{'progress'}->base_add ($count);
    my $nbco        = $self->ebt->get_notes_by_country;   $xhr and $self->{'progress'}->base_add ($count);
    #$self->_log (debug => report 'regions get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    foreach my $country (sort keys %$region_data) {
        $region_data->{$country}{'__cname'} = $self->_country_names ($country);
    }

    my $url = $self->url_for;
    $url = '' if $url =~ /gen_output_/;
    $self->stash (
        title       => $section_titles{'regions'},
        count       => $count,
        nbco        => $nbco,
        region_data => $region_data,
        url         => $url,
    );
}

sub travel_stats {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count        = $self->ebt->get_count;               $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $travel_stats = $self->ebt->get_travel_stats;        $xhr and $self->{'progress'}->base_add ($count);
    my $notes_dates  = $self->ebt->get_notes_dates;         ## already cached (as part of 'information')
    my $elem_by_city = $self->ebt->get_elem_notes_by_city;  ## already cached
    #$self->_log (debug => report 'travel_stats get', $t0, $count);

    $t0 = [gettimeofday];
    my %unique_years;
    my ($num_locs, $yearly_visits, $one_time_visits);
    foreach my $location (keys %$travel_stats) {
        my @years = keys %{ $travel_stats->{$location}{'visits'} };
        $unique_years{$_} = undef for @years;

        $num_locs++;
        $yearly_visits += @years;
        $one_time_visits++ if 1 == @years;
    }
    #$self->_log (debug => report 'travel_stats cook', $t0, $count);

    ## chart
    $t0 = [gettimeofday];
    my $dest_img = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'travel_stats.svg');
    if (!-e $dest_img) {
        my @_8best =
            map { (split /#/)[1] }
            grep defined,
            (reverse sort { $travel_stats->{$a}{'total'} <=> $travel_stats->{$b}{'total'}} keys %$travel_stats)[0..7];
        my %dpoints;
        foreach my $elem (split '#', $elem_by_city) {
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
            output => (encode 'UTF-8', $dest_img),
            xdata => $notes_dates,
            title => (encode 'UTF-8', $self->l ('Cities with most notes')),
            logscale => 'y',
            dsets => \@dsets;
    }
    #$self->_log (debug => report 'travel_stats chart', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count*0.2);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

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
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count   = $self->ebt->get_count;       $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $ht_data = $self->ebt->get_huge_table;
    #$self->_log (debug => report 'huge_table get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my $ht;
    foreach my $sp (keys %$ht_data) {
        my ($series, $plate) = $sp =~ /^(.*)(.{4})$/;
        $ht->{$sp}{'values'} = $ht_data->{$sp};
        foreach my $value (keys %{ $ht->{$sp}{'values'} }) {
            foreach my $serial (keys %{ $ht->{$sp}{'values'}{$value} }) {
                $ht->{$sp}{'values'}{$value}{$serial}{'flag'} = EBT2->series_countries ((substr $serial, 0, 1), $series);
            }
        }
        $ht->{$sp}{'plate_flag'} = (split /,/, EBT2->printers ((substr $plate, 0, 1), $series))[0];
    }
    #$self->_log (debug => report 'huge_table cook', $t0, $count);

    my $url = $self->url_for;
    $url = '' if $url =~ /gen_output_/;
    $self->stash (
        title => $section_titles{'huge_table'},
        ht    => $ht,
        url   => $url,
    );
}

sub short_codes {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $split = sub {
        my ($str) = @_;
        return $str =~ /^(.{6})(.*)/;
    };

    my $t0 = [gettimeofday];
    my $count   = $self->ebt->get_count;                $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $lo      = $self->ebt->get_lowest_short_codes;
    my $hi      = $self->ebt->get_highest_short_codes;  ## already cached
    #$self->_log (debug => report 'short_codes get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    my @pcs = uniq keys %$lo, keys %$hi;
    $t0 = [gettimeofday];
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
                my ($pc_str, $cc_str) = $split->($records->{$what}{'sort_key'});
                my $pc_iso3166 = (split /,/, EBT2->printers ($pc, $records->{$what}{'series'}))[0];
                $tmp->{$what} = {
                    pc_img  => $pc_iso3166,
                    pc_flag => EBT2->flag ($pc_iso3166),
                    cc_img  => EBT2->series_countries ($cc, $records->{$what}{'series'}),
                    cc_flag => EBT2->flag (EBT2->series_countries ($cc, $records->{$what}{'series'})),
                    pc_str  => $pc_str,
                    cc_str  => $cc_str,
                    id      => $records->{$what}{'id'},
                    value   => $records->{$what}{'value'},
                    date    => (split ' ', $records->{$what}{'date_entered'})[0],
                    recent  => $records->{$what}{'recent'},
                };
            }
            push @{ $sc->{$v} }, $tmp;
        }
    }
    #$self->_log (debug => report 'short_codes cook', $t0, $count);

    $self->stash (
        title => $section_titles{'short_codes'},
        sc    => $sc,
    );
}

sub nice_serials {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count = $self->ebt->get_count;                        $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $nice_data = $self->ebt->get_nice_serials;
    my $numbers_in_a_row = $self->ebt->get_numbers_in_a_row;  ## already cached
    my $different_digits = $self->ebt->get_different_digits;  ## already cached
    #$self->_log (debug => report 'nice_serials get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
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
        $niar->{$length} = { count => $num, pct => $pct };
    }

    my $dd;
    foreach my $digit (keys %$different_digits) {
        my $num = $different_digits->{$digit};
        my $pct = $num * 100 / $count;
        $dd->{$digit} = { count => $num, pct => $pct };
    }
    #$self->_log (debug => report 'nice_serials cook', $t0, $count);

    $self->stash (
        title            => $section_titles{'nice_serials'},
        nicest           => $nice_notes,
        numbers_in_a_row => $niar,
        different_digits => $dd,
        primes           => 'bar',
        squares          => 'baz',
        palindromes      => 'qux',
    );
}

sub coords_bingo {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count       = $self->ebt->get_count;         $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $cbingo_data = $self->ebt->get_coords_bingo;
    #$self->_log (debug => report 'coords_bingo get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my $cbingo = $cbingo_data;
    #foreach my $v ('all', @{ EBT2->values }) {
    #    next unless defined $cbingo_data->{$v};
    #}
    #$self->_log (debug => report 'coords_bingo cook', $t0, $count);

    $self->stash (
        title  => $section_titles{'coords_bingo'},
        cbingo => $cbingo,
    );
}

sub notes_per_year {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count    = $self->ebt->get_count;           $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $nby_data = $self->ebt->get_notes_per_year;
    #$self->_log (debug => report 'notes_per_year get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my $nby;
    my ($y) = (sort keys %$nby_data)[0];
    my $cursor = DateTime->new (year => $y);
    my $now = DateTime->now;
    while (1) {
        my $y = $cursor->strftime ('%Y');
        my $detail;
        foreach my $v (@{ EBT2->values }) {
            push @$detail, {
                value => $v,
                count => $nby_data->{$y}{$v}//0,
            };
        }
        my $tot = $nby_data->{$y}{'total'}//0;
        push @$nby, {
            year   => $y,
            count  => $tot,
            pct    => (sprintf '%.2f', 100 * $tot / $count),
            detail => $detail,
        };
        $cursor->add (years => 1);
        last if $cursor > $now;
    }
    #$self->_log (debug => report 'notes_per_year cook', $t0, $count);

    $self->stash (
        title => $section_titles{'notes_per_year'},
        nby   => $nby,
    );
}

sub notes_per_month {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count    = $self->ebt->get_count;            $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $nbm_data = $self->ebt->get_notes_per_month;
    #$self->_log (debug => report 'notes_per_month get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my $nbm;
    my ($y, $m) = split /-/, (sort keys %$nbm_data)[0];
    my $cursor = DateTime->new (year => $y, month => $m);
    my $now = DateTime->now;
    while (1) {
        my $m = $cursor->strftime ('%Y-%m');
        my $detail;
        foreach my $v (@{ EBT2->values }) {
            push @$detail, {
                value => $v,
                count => $nbm_data->{$m}{$v}//0,
            };
        }
        my $tot = $nbm_data->{$m}{'total'}//0;
        push @$nbm, {
            month  => $m,
            count  => $tot,
            pct    => (sprintf '%.2f', 100 * $tot / $count),
            detail => $detail,
        };
        $cursor->add (months => 1);
        last if $cursor > $now;
    }
    #$self->_log (debug => report 'notes_per_month cook', $t0, $count);

    $self->stash (
        title => $section_titles{'notes_per_month'},
        nbm   => $nbm,
    );
}

sub top_days {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count      = $self->ebt->get_count;         $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $t10d_data  = $self->ebt->get_top10days;
    my $t10m_data  = $self->ebt->get_top10months;   ## already cached
    my $nbdow_data = $self->ebt->get_notes_by_dow;  ## already cached
    #$self->_log (debug => report 'top_days get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
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
    #$self->_log (debug => report 'top_days cook', $t0, $count);

    ## chart
    $t0 = [gettimeofday];
    my $dest_img = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'week_days.svg');
    -e $dest_img or EBTST::Main::Gnuplot::bar_chart
        output     => (encode 'UTF-8', $dest_img),
        labels     => [ map { encode 'UTF-8', $self->l ($_) } qw/Monday Tuesday Wednesday Thursday Friday Saturday Sunday/ ],
        title => (encode 'UTF-8', $self->l ('Accumulated notes by day of the week')),
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
    #$self->_log (debug => report 'top_days chart', $t0, $count);

    $self->stash (
        title => $section_titles{'top_days'},
        nbdow => $nbdow,
        t10d  => $t10d,
        t10m  => $t10m,
    );
}

sub time_analysis_bingo {
    my ($self, $detail) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count   = $self->ebt->get_count;          $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $ta_data = $self->ebt->get_time_analysis;
    #$self->_log (debug => report 'time_analysis get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $self->stash (
        title    => ($detail ? $section_titles{'time_analysis_detail'} : $section_titles{'time_analysis_bingo'}),
        ta_count => $count,
        ta       => $ta_data,
    );
}
sub time_analysis_detail { push @_, 1; goto &time_analysis_bingo; }

sub combs_bingo {
    my ($self, $detail) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count      = $self->ebt->get_count;                     $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $nbcombo    = $self->ebt->get_notes_by_combination;      $xhr and $self->{'progress'}->base_add ($count);
    my $comb_data  = $self->ebt->get_missing_combs_and_history;
    #$self->_log (debug => report 'combs_bingo get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my $missing;
    foreach my $k (sort keys %{ $comb_data->{'missing_pcv'} }) {
        my ($ser, $p, $c, $v) = $k =~ /^(.+)(.)(.)(\d{3})$/;
        $v += 0;

        if (!exists $missing->{"$p$c"}) {
            $missing->{"$p$c"} = {
                pname   => do { local $ENV{'EBT_LANG'} = 'en'; (split /,/, EBT2->printers ($p, $ser))[0] },
                cname   => do { local $ENV{'EBT_LANG'} = 'en'; EBT2->series_countries ($c, $ser) },
                pletter => $p,
                cletter => $c,
                values  => [ $v ],
            };
        } else {
            push @{ $missing->{"$p$c"}{'values'} }, $v;
        }
    }

    my $history_pc; my %hpc_seen; my $hpc_idx = 0;
    foreach my $h (@{ $comb_data->{'history'} }) {
        my $k = sprintf '%s%s%s', @$h{qw/series pc cc/};
        next if $hpc_seen{$k}++;
        push @$history_pc, {
            %$h,
            index        => ++$hpc_idx,
            ## this history ends up in the BBCode, let's assign its flags
            pc_flag      => EBT2->flag ((split /,/, EBT2->printers  ($h->{'pc'}, $h->{'series'}))[0]),
            cc_flag      => EBT2->flag (EBT2->series_countries ($h->{'cc'}, $h->{'series'})),
            country_flag => EBT2->flag ($h->{'country'}),
        }
    }
    #$self->_log (debug => report 'combs_bingo cook', $t0, $count);

    my $presidents = [
        map { [ split /:/ ] } 'any:Any signature', @{ $self->ebt->presidents }
    ];
    $self->stash (
        title       => ($detail ? $section_titles{'combs_detail'} : $section_titles{'combs_bingo'}),
        nbcombo     => $nbcombo,
        series      => $self->ebt->series,
        presidents  => $presidents,
        missing     => $missing,
        history_pc  => $history_pc,
        history_pcv => $comb_data->{'history'},
        count       => $count,
    );
}
sub combs_detail { push @_, 1; goto &combs_bingo; }

sub plate_bingo {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count      = $self->ebt->get_count;        $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $plate_data = $self->ebt->get_plate_bingo;
    #$self->_log (debug => report 'plate_bingo get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my $cooked;
    foreach my $value (
        sort {
            if ('all' eq $a) { return -1; }
            if ('all' eq $b) { return 1; }
            return $a <=> $b;
        } keys %$plate_data
    ) {
        my %plates;
        my %printers;
        my $highest = 0;
        foreach my $sp (sort keys %{ $plate_data->{$value} }) {
            my ($series, $plate) = $sp =~ /^(.*)(.{4})$/;
            my $pc = substr $plate, 0, 1;
            $plates{$sp} = $plate_data->{$value}{$sp};
            $printers{"$series$pc"} ||= {
                series     => $series,
                pc         => $pc,
                pc_iso3166 => (split /,/, EBT2->printers ($pc, $series))[0],
            };
            my $ordinal = substr $plate, 1;
            $highest = $ordinal if $ordinal > $highest;
        }

        push @$cooked, {
            value    => $value,
            plates   => \%plates,
            printers => [ sort { $a->{'pc'} cmp $b->{'pc'} || $a->{'pc_iso3166'} cmp $b->{'pc_iso3166'} } values %printers ],
            highest  => $highest,
        };
    }
    #$self->_log (debug => report 'plate_bingo cook', $t0, $count);

    my $url = $self->url_for;
    $url = '' if $url =~ /gen_output_/;
    $self->stash (
        title       => $section_titles{'plate_bingo'},
        plate_bingo => $cooked,
        url         => $url,
    );
}

sub bad_notes {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count     = $self->ebt->get_count;      $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $bad_notes = $self->ebt->get_bad_notes;
    #$self->_log (debug => report 'bad_notes get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my @cooked;
    my $idx = 0;
    foreach my $bn (@$bad_notes) {
        my $pc = substr $bn->{'short_code'}, 0, 1;
        my $cc = substr $bn->{'serial'},     0, 1;
        if (grep { 'Bad serial number' eq $_ } @{ $bn->{'errors'} }) {
            $bn->{'serial'} = sprintf "%s\x{2026}", substr $bn->{'serial'}, 0, 4;
        } else {
            $bn->{'serial'} =~ s/^([A-Z])....(....)...$/$1xxxx$2xxx/;
        }
        $bn->{'short_code'} = substr $bn->{'short_code'}, 0, 4;
        my $pc_iso3166 = (split /,/, EBT2->printers ($pc, $bn->{'series'}))[0];
        push @cooked, {
            %$bn,
            idx        => ++$idx,
            pc_img     => $pc_iso3166,
            cc_img     => EBT2->series_countries ($cc, $bn->{'series'}),
            bbflag_pc  => EBT2->flag ($pc_iso3166),
            bbflag_cc  => EBT2->flag (EBT2->series_countries ($cc, $bn->{'series'})),
            bbflag_got => EBT2->flag ($bn->{'country'}),
        };
    }
    #$self->_log (debug => report 'bad_notes cook', $t0, $count);

    $self->stash (
        title     => $section_titles{'bad_notes'},
        bad_notes => \@cooked,
    );
}

sub hit_list {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count    = $self->ebt->get_count;               $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $whoami   = $self->ebt->whoami;
    my $hit_data = $self->ebt->get_hit_list ($whoami);
    #$self->_log (debug => report 'hit_list get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my $cooked;
    foreach my $hit (@$hit_data) {
        next if $hit->{'moderated'};
        $hit->{'serial'} =~ s/^([A-Z])....(....)...$/$1xxxx$2xxx/;
        push @$cooked, $hit;
    }
    #$self->_log (debug => report 'hit_list cook', $t0, $count);

    $self->stash (
        title    => $section_titles{'hit_list'},
        hit_list => $cooked,
        whoami   => $whoami,
    );
}

sub hit_times_bingo {
    my ($self, $detail) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count    = $self->ebt->get_count;                   $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $whoami   = $self->ebt->whoami;
    my $hit_list = $self->ebt->get_hit_list ($whoami);
    my $ht       = $self->ebt->get_hit_times ($hit_list);   ## don't include in the progress, it iterates through hits, not notes
    #$self->_log (debug => report 'hit_times get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $self->stash (
        title           => ($detail ? $section_titles{'hit_times_detail'} : $section_titles{'hit_times_bingo'}),
        hit_times_count => (scalar grep { !$_->{'moderated'} } @$hit_list),
        hit_times       => $ht,
    );
}
sub hit_times_detail { push @_, 1; goto &hit_times_bingo; }

sub hit_locations {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count    = $self->ebt->get_count;                $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $nbci     = $self->ebt->get_notes_by_city;        $xhr and $self->{'progress'}->base_add ($count);
    my $whoami   = $self->ebt->whoami;
    my $hit_list = $self->ebt->get_hit_list ($whoami);
    #$self->_log (debug => report 'hit_locations get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    my (%hit_count_by_my_loc, %hit_count_by_their_loc);
    my %arrows;
    my %local_hits;
    foreach my $hit (@$hit_list) {
        next if $hit->{'moderated'};

        my $idx = 0;
        foreach my $user (@{ $hit->{'hit_partners'} }) {
            last if $user eq $whoami->{'name'};
            $idx++;
        }

        my $my_k = join ',', $hit->{'countries'}[$idx], $hit->{'cities'}[$idx];
        $hit_count_by_my_loc{$my_k}++;

        my $num_parts = @{ $hit->{'countries'} };
        foreach my $their_idx (0 .. $num_parts - 1) {
            next if $their_idx == $idx;
            my $their_k = join ',', $hit->{'countries'}[$their_idx], $hit->{'cities'}[$their_idx];
            $hit_count_by_their_loc{$their_k}++;

            if (1 == abs $their_idx - $idx) {   ## only arrows in adjacent hit parts, this is relevant in >= triple hits
                my $arrow_key = sprintf '%s|%s', $their_idx < $idx ? ($their_k, $my_k) : ($my_k, $their_k);
                $arrows{$arrow_key}++;
            }
        }

        ## local hits
        my @cities = uniq map {
            sprintf '%s#%s', $hit->{'countries'}[$_], $hit->{'cities'}[$_]
        } 0 .. $#{ $hit->{'cities'} };
        if (1 == @cities) {
            my $k = join ',', $hit->{'countries'}[0], $hit->{'cities'}[0];
            $local_hits{$k}++;
        }
    }

    my @my_locs;
    foreach my $my_loc (keys %hit_count_by_my_loc) {
        my ($country, $city) = split /,/, $my_loc, 2;
        push @my_locs, {
            country   => $country,
            bbflag    => EBT2->flag ($country),
            city      => $city,
            notes     => $nbci->{$country}{$city}{'total'},
            notes_pct => 100 * $nbci->{$country}{$city}{'total'} / $count,
            hits      => $hit_count_by_my_loc{$my_loc},
            hits_pct  => 100 * $hit_count_by_my_loc{$my_loc} / (sum values %hit_count_by_my_loc),
            ratio     => $nbci->{$country}{$city}{'total'} / $hit_count_by_my_loc{$my_loc},
        };
    }
    { use locale; @my_locs = sort {
        $b->{'notes'} <=> $a->{'notes'} or
        $a->{'city'} cmp $b->{'city'}
    } @my_locs; }

    my @their_locs;
    my $num_their_locs;
    foreach my $their_loc (keys %hit_count_by_their_loc) {
        $num_their_locs++;
        next if $hit_count_by_their_loc{$their_loc} < 2;
        my ($country, $city) = split /,/, $their_loc, 2;
        push @their_locs, {
            country  => $country,
            city     => $city,
            hits     => $hit_count_by_their_loc{$their_loc},
            hits_pct => 100 * $hit_count_by_their_loc{$their_loc} / (sum values %hit_count_by_their_loc),
        };
    }
    { use locale; @their_locs = sort {
        $b->{'hits'} <=> $a->{'hits'} or
        $a->{'city'} cmp $b->{'city'}
    } @their_locs; }

    my @arrows;
    foreach my $k (keys %arrows) {
        next if $arrows{$k} < 2;
        push @arrows, {
            fromto => $k,
            num    => $arrows{$k},
            pct    => 100 * $arrows{$k} / (sum values %arrows),
        };
    }

    my %both_ways;
    foreach my $k (keys %arrows) {
        my ($from, $to) = split /\|/, $k, 2;
        my $reverse_k = sprintf '%s|%s', $to, $from;
        if ($k ne $reverse_k and exists $arrows{$reverse_k}) {
            my @sorted_fromto; { use locale; @sorted_fromto = sort $from, $to; }
            my $sorted_k = sprintf '%s|%s', @sorted_fromto;
            $both_ways{$sorted_k} += $arrows{$k};
        }
    }
    #$self->_log (debug => report 'hit_locations cook', $t0, $count);

    $self->stash (
        title      => $section_titles{'hit_locations'},
        my_locs    => \@my_locs,
        their_locs => \@their_locs,
        num_their_locs => $num_their_locs,
        arrows     => \@arrows,
        local_hits => \%local_hits,
        both_ways  => \%both_ways,
    );
}

sub hit_regions {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count           = $self->ebt->get_count;               $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $whoami          = $self->ebt->whoami;
    my $hit_list        = $self->ebt->get_hit_list ($whoami);
    my $hit_region_data = $self->ebt->get_hit_regions ($whoami, $hit_list);
    #$self->_log (debug => report 'hit_regions get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    my %partners;
    foreach my $h (grep { !$_->{'moderated'} } @$hit_list) {
        foreach my $partner (@{ $h->{'hit_partners'} }) {
            $partners{$partner} = undef;
        }
    }
    my $total_partners = -1 + keys %partners;   ## minus myself

    foreach my $country (sort keys %$hit_region_data) {
        $hit_region_data->{$country}{'__cname'} = $self->_country_names ($country);
    }

    my $url = $self->url_for;
    $url = '' if $url =~ /gen_output_/;
    $self->stash (
        title           => $section_titles{'hit_regions'},
        total_partners  => $total_partners,
        total_hits      => (scalar grep { !$_->{'moderated'} } @$hit_list),
        hit_region_data => $hit_region_data,
        url             => $url,
    );
}

sub hit_analysis {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count    = $self->ebt->get_count;                      $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $whoami   = $self->ebt->whoami;
    my $hit_list = $self->ebt->get_hit_list ($whoami);
    my $ha       = $self->ebt->get_hit_analysis ($hit_list);
    #$self->_log (debug => report 'hit_analysis get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
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
    foreach my $hit (
        map { @{ $_->{'hits'} } }
        @{ $ha->{'lucky_bundles'} }
    ) {
        $hit->{'hit_date'} = (split ' ', $hit->{'hit_date'})[0];
        $hit->{'serial'} =~ s/^([A-Z])....(....)...$/$1xxxx$2xxx/;
    }
    #$self->_log (debug => report 'hit_analysis cook', $t0, $count);

    $self->stash (
        title               => $section_titles{'hit_analysis'},
        whoami              => $whoami,
        longest             => $longest,
        oldest              => $oldest,
        lucky_bundles       => $ha->{'lucky_bundles'},
        other_hit_potential => $ha->{'other_hit_potential'},
    );
}

sub hit_summary {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count        = $self->ebt->get_count;                  $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $activity     = $self->ebt->get_activity;               ## already cached (as part of 'information')
    my $nbvalue      = $self->ebt->get_notes_by_value;         $xhr and $self->{'progress'}->base_add ($count);
    my $whoami       = $self->ebt->whoami;
    my $hit_list     = $self->ebt->get_hit_list ($whoami);     $xhr and $self->{'progress'}->base_add ($count);
    my $hs           = $self->ebt->get_hit_summary ($whoami, $activity, $nbvalue, $count, $hit_list);
    my $hits_dates   = $self->ebt->get_hits_dates ($whoami);
    my $elem_ratio   = $self->ebt->get_elem_ratio ($whoami);
    my $elem_travel_days = $self->ebt->get_elem_travel_days ($whoami);
    my $elem_travel_km   = $self->ebt->get_elem_travel_km ($whoami);
    #$self->_log (debug => report 'hit_summary get', $t0, $count);

    $t0 = [gettimeofday];
    foreach my $hbc_k (keys %{ $hs->{'hits_by_combo'} }) {
        my $pc_iso3166 = (split /,/, EBT2->printers ($hs->{'hits_by_combo'}{$hbc_k}{'pc'}, $hs->{'hits_by_combo'}{$hbc_k}{'series'}))[0];
        my $cc_iso3166 = EBT2->countries ($hs->{'hits_by_combo'}{$hbc_k}{'cc'});
        $hs->{'hits_by_combo'}{$hbc_k}{'cc_iso3166'} = $cc_iso3166;
        $hs->{'hits_by_combo'}{$hbc_k}{'pc_iso3166'} = $pc_iso3166;
        $hs->{'hits_by_combo'}{$hbc_k}{'ccflag'} = EBT2->flag ($cc_iso3166);
        $hs->{'hits_by_combo'}{$hbc_k}{'pcflag'} = EBT2->flag ($pc_iso3166);
    }
    #$self->_log (debug => report 'hit_summary cook', $t0, $count);

    ## chart
    $t0 = [gettimeofday];
    my $dest_img1 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'hits_ratio.svg');
    my $dest_img2 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'hits_travel_days.svg');
    my $dest_img3 = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'hits_travel_km.svg');
    my $gen_charts = !!$hs->{'total'};
    if (!$gen_charts) {
        $self->_log (info => 'no hits, skipping chart generation');
    }
    if ($gen_charts and (!-e $dest_img1 or !-e $dest_img2 or !-e $dest_img3)) {
        my %dpoints;
        my @all_dates;

        foreach my $elem (@$elem_ratio) {
            my ($date, undef, $ratio) = split /=/, $elem;
            push @all_dates, $date;
            push @{ $dpoints{'hit_ratio'} }, $ratio || undef;
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
            output => (encode 'UTF-8', $dest_img1),
            xdata => \@all_dates,
            title => (encode 'UTF-8', $self->l ('Historic hit ratio')),
            dsets => [
                { title => (encode 'UTF-8', $self->l ('Hit ratio')), color => 'black', points => $dpoints{'hit_ratio'} },
            ];
        $xhr and $self->{'progress'}->base_add ($count*0.2);

        -e $dest_img2 or EBTST::Main::Gnuplot::line_chart
            output => (encode 'UTF-8', $dest_img2),
            xdata => $hits_dates,
            title => (encode 'UTF-8', $self->l ('Historic hit travel days')),
            dsets => [
                { title => (encode 'UTF-8', $self->l ('Travel days')), color => 'black', points => $dpoints{'travel_days'} },
            ];
        $xhr and $self->{'progress'}->base_add ($count*0.2);

        -e $dest_img3 or EBTST::Main::Gnuplot::line_chart
            output => (encode 'UTF-8', $dest_img3),
            xdata => $hits_dates,
            title => (encode 'UTF-8', $self->l ('Historic hit travel km')),
            dsets => [
                { title => (encode 'UTF-8', $self->l ('Travel km')), color => 'black', points => $dpoints{'travel_km'} },
            ];
    }
    #$self->_log (debug => report 'hit_summary chart', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count*0.2);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $self->stash (
        title => $section_titles{'hit_summary'},
        hs    => $hs,
    );
}

sub calendar {
    my ($self) = @_;
    my $xhr = $self->req->is_xhr;
    my ($pbase, $ptot) = split m{/}, $self->req->headers->header ('X-Calc-Sections-Progress') // '';

    my $t0 = [gettimeofday];
    my $count    = $self->ebt->get_count;     $xhr and $self->_init_progress (base => $pbase, tot => $ptot);
    my $cal_data = $self->ebt->get_calendar;
    #$self->_log (debug => report 'calendar get', $t0, $count);
    $xhr and $self->{'progress'}->base_add ($count);
    if ($xhr) { $self->res->headers->connection ('close'); return $self->_end_progress; }

    $t0 = [gettimeofday];
    foreach my $y (sort keys %$cal_data) {
        foreach my $m (sort keys %{ $cal_data->{$y} }) {
            my $first_day = '01';
            my $first_dow = $cal_data->{$y}{$m}{'days'}{$first_day}{'dow'};
            my $days_before = $first_dow - 1;

            my $last_day = (sort keys %{ $cal_data->{$y}{$m}{'days'} })[-1];
            my $last_dow = $cal_data->{$y}{$m}{'days'}{$last_day}{'dow'};
            my $days_after = 7 - $last_dow;

            $cal_data->{$y}{$m}{'days_before'} = $days_before;
            $cal_data->{$y}{$m}{'days_after'}  = $days_after;
            $cal_data->{$y}{$m}{'first_day'}   = $first_day;
            $cal_data->{$y}{$m}{'last_day'}    = $last_day;
        }
    }
    #$self->_log (debug => report 'calendar cook', $t0, $count);

    my $url = $self->url_for;
    $url = '' if $url =~ /gen_output_/;
    $self->stash (
        title    => $section_titles{'calendar'},
        cal_data => $cal_data,
        url      => $url,
    );
}

sub configure {
    my ($self) = @_;

    $self->stash (
        msg   => $self->flash ('msg')//'',
        title => $section_titles{'configure'},
        ua    => $self->req->headers->user_agent,
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

    ($fd, $tmpfile) = tempfile 'ebtst-uncompress.XXXXXX', DIR => $tmpdir;
    if (!gunzip $file, $fd, AutoClose => 1) {
        $self->_log (warn => "_decompress: gunzip: $GunzipError");
        unlink $tmpfile or $self->_log (warn => "_decompress: unlink: '$tmpfile': $!");
    } else {
        rename $tmpfile, $file or $self->_log (warn => "_decompress: rename: '$tmpfile' to '$file': $!");
    }

    ($fd, $tmpfile) = tempfile 'ebtst-uncompress.XXXXXX', DIR => $tmpdir;
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
    my $sha = substr +(sha512_hex $self->stash ('user')), 0, 8;

    my $local_notes_file = File::Spec->catfile ($tmpdir, "$sha-notes.csv");
    my $local_hits_file  = File::Spec->catfile ($tmpdir, "$sha-hits.csv");
    unlink $local_notes_file or (2 == $! or $self->_log (warn => "upload: unlink: '$local_notes_file': $!\n"));
    unlink $local_hits_file  or (2 == $! or $self->_log (warn => "upload: unlink: '$local_hits_file': $!"));

    my $some_csv_uploaded = 0;
    if ($notes_csv and $notes_csv->size) {
        $self->_log (debug => "upload: there's notes CSV");
        $notes_csv->move_to ($local_notes_file);
        $some_csv_uploaded = 1;
    }
    if ($hits_csv and $hits_csv->size) {
        $self->_log (debug => "upload: there's hits CSV");
        $hits_csv->move_to ($local_hits_file);
        $some_csv_uploaded = 1;
    }

    if (!$some_csv_uploaded) {
        $self->_log (debug => "upload: no notes or hits given");
        $self->render (text => 'no_csvs', layout => undef, format => 'txt');
        return;
    }

    $self->app->log->debug ("sha ($sha)");
    $self->render (text => $sha, layout => undef, format => 'txt');
    return;
}

sub import {
    my ($self) = @_;
    my $done = 0;

    return $self->render_not_found unless $self->req->is_xhr;

    my $sha = $self->stash ('sha');
    my $local_notes_file = File::Spec->catfile ($tmpdir, "$sha-notes.csv");
    my $local_hits_file  = File::Spec->catfile ($tmpdir, "$sha-hits.csv");

    my $theres_notes = -e $local_notes_file;
    my $theres_hits  = -e $local_hits_file;

    if (!$theres_notes and !$theres_hits) {
        $self->_log (info => "import: no notes or hits, rendering 404");
        return $self->render_not_found;
    }

    if ($theres_notes) {
        my $outfile = File::Spec->catfile ($EBTST::config{'csvs_dir'}, $sha);
        $self->_log (info => "will store a censored copy at '$outfile'");
        if (!unlink $outfile and 'No such file or directory' ne $!) {
            $self->_log (warn => "import: unlink: '$outfile': $!");
        }
        ## we may get the first request for /progress before ->_decompress finishes
        ## initialize progress now, even with a bogus total (progress will be 0 anyway)
        $self->_init_progress (tot => 1);
        $self->_decompress ($local_notes_file);

        my $count = 0; if (open my $fd, '<', $local_notes_file) { <$fd>; $count =()= <$fd>; close $fd; }
        if ($theres_hits) {
            $self->_init_progress (tot => $count*1.1);     ## processing hits takes around 10% of the time of processing notes, hence that 0.1
        } else {
            $self->_init_progress (tot => $count);
        }
        eval { $self->ebt->load_notes ($local_notes_file, $outfile, !$theres_hits); 1; };
        unlink $local_notes_file or $self->_log (warn => "import: unlink: '$local_notes_file': $!\n");
        if ($@ and $@ =~ /Unrecognized notes file/) {
            return $self->_end_progress ('bad_notes');
        }
        $self->{'progress'}->base_add ($count);
        $done = 1;

        my $globpat = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), '*.svg');
        $globpat =~ s/ /\\ /g;    ## usernames may have spaces and glob splits on them. Avoid that
        foreach my $img (glob $globpat) {
            unlink $img or $self->_log (warn => "import: unlink: '$img': $!");
        }
    }
    if ($theres_hits) {
        $self->_decompress ($local_hits_file);

        if (!$theres_notes) {
            if (!$self->ebt->has_notes) {
                $self->render (text => 'no_notes', layout => undef, format => 'txt');
                return;
            }
            $self->_init_progress (tot => $self->ebt->note_count * 0.1);
        }  ## else, the previous if-block has done a $self->{'progress'}->base_add
        eval { $self->ebt->load_hits ($local_hits_file); 1; };
        unlink $local_hits_file  or $self->_log (warn => "import: unlink: '$local_hits_file': $!");
        if ($@ and $@ =~ /Unrecognized hits file/) {
            return $self->_end_progress ('bad_hits');
        }
        $done = 1;
        my $globpat = File::Spec->catfile ($self->stash ('images_dir'), $self->stash ('user'), 'hits_*.svg');
        $globpat =~ s/ /\\ /g;
        foreach my $img (glob $globpat) {
            unlink $img or $self->_log (warn => "import: unlink: '$img': $!");
        }
    }

    return $self->_end_progress ('information');
}

sub _prepare_html_dir {
    my ($self, $dest_dir) = @_;

    system qq[rm -rf "$dest_dir"];
    if (-1 == $?) {
        die "system: $!";
    } elsif (my $sig = $? & 127) {
        die sprintf "system: child died with signal $sig";
    } elsif (my $rc = $? >> 8) {
        die "system: child exited with value $rc";
    }

    if (!mkdir $dest_dir) {
        die "Couldn't create directory: '$dest_dir': $!\n";
    }

    if (!mkdir "$dest_dir/images") {
        die "Couldn't create directory: '$dest_dir/images': $!\n";
    }

    if (!mkdir "$dest_dir/images/" . $self->stash ('user')) {
        die "Couldn't create directory: '$dest_dir/images/".$self->stash ('user')."': $!\n";
    }

    my $cmd = sprintf "bash -c 'cp -a %s/{*.gif,countries,regions,values} %s/stats/foo/images/'", $self->stash ('images_dir'), $self->stash ('statics_dir');
    $self->_log (debug => "cmd ($cmd)");
    system $cmd;
    if (-1 == $?) {
        die "system: $!";
    } elsif (my $sig = $? & 127) {
        die sprintf "system: child died with signal $sig";
    } elsif (my $rc = $? >> 8) {
        die "system: child exited with value $rc";
    }

    my ($src, $dest);

    ## don't link but copy ebt.css, so generated stats don't break when the CSS is changed
    $src  = File::Spec->catfile ($self->stash ('statics_dir'), 'ebt.css');
    $dest = File::Spec->catfile ($dest_dir,                    'ebt.css');
    copy $src, $dest or $self->_log (warn => "copy: '$src' to '$dest': $!");

    return;
}

sub _save_html {
    my ($self, $html_dir, $html_text, @req_params) = @_;

    my $index_symlink_done = 0;
    foreach my $param (@req_params) {
        my $partial_html = encode 'UTF-8', $self->render_to_string (template => "main/$param", format => 'html');
        #if (my $rss = $self->rss_process) {
        #    $self->app->log->debug ("gen_output: process RSS is $rss Kb");
        #}
        my $title = encode 'UTF-8', $self->l ($section_titles{$param});
        my $html_copy = $html_text;
        $html_copy =~ s/<!-- content -->/$partial_html/;
        $html_copy =~ s/<!-- __TITLE__ -->/$title/;

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
        my $id = eval { $tr->td->a->{'id'}; };
        $@ and next;    ## this happens in the cell containing the username. Ignore the error
        unless (grep { $_ eq $id } @req_params) {
            $tr->replace ('');
        }
    }
    return $dom->to_string;
}

sub _ua_get {
    my ($self, $tot, @req_params) = @_;
    my $pbase = 0;
    my $count = $self->ebt->get_count;

    my $c = Mojo::Cookie::Response->new->
        name ('sid')->
        value ($self->stash ('sess')->sid)->
        domain ('localhost')->
        path ('/');

    my $cj = Mojo::UserAgent::CookieJar->new->add ($c);

    my $ua = Mojo::UserAgent->new->cookie_jar ($cj)->inactivity_timeout (300);
    $ua->on (start => sub {
        my ($ua, $tx) = @_;
        $self->_log (debug => sprintf 'ua on start: setting header "X-Calc-Sections-Progress: %s"', "$pbase/$tot");
        $tx->req->headers->header ('X-Requested-With', 'XMLHttpRequest');        ## so the methods update their progress
        $tx->req->headers->header ('X-Calc-Sections-Progress', "$pbase/$tot");   ## so they init the progress object with the given base
    });

    foreach my $rp (@req_params) {
        my $url;
        if ('production' eq $self->app->mode) {
            my $parts = $self->req->url->base->path->parts;
            if ($parts and @$parts) {
                $self->_log (debug => "base path parts (@$parts)");
                $url = sprintf 'http://localhost:%d/%s/%s', $self->tx->local_port, (join '/', @$parts), $rp;
            } else {
                $url = sprintf 'http://localhost:%d/%s', $self->tx->local_port, $rp;
            }
        } else {
            $url = "/$rp";
        }
        $self->_log (debug => "getting url ($url)");
        my $tx = $ua->get ($url);   ## $self->app->config->{'hypnotoad'}{'listen'}[0] could be useful too
        if (!$tx->success) {
            my ($msg, $err) = $tx->error;
            $msg //= '<undef>';
            $err //= '<undef>';
            $self->_log (warn => "ua: msg ($msg) err ($err)");
        }
        $pbase += ($mults{$rp}//1) * $count;
    }
    #if (my $rss = $self->rss_process) { $self->app->log->debug ("calc_sections after multiple ua->get's: process RSS is $rss Kb"); }
    return;
}

sub calc_sections {
    my ($self) = @_;
    my @params = qw/
        information value countries printers locations regions travel_stats huge_table short_codes nice_serials
        coords_bingo notes_per_year notes_per_month top_days time_analysis_bingo time_analysis_detail
        combs_bingo combs_detail plate_bingo bad_notes hit_list hit_times_bingo hit_times_detail
        hit_locations hit_regions hit_analysis hit_summary calendar
    /;

    return $self->render_not_found unless $self->req->is_xhr;

    my @req_params = grep { $self->param ($_) } @params;
    @req_params = qw/information value countries printers locations/ unless @req_params;
    $self->ebt->set_checked_boxes (@req_params);
    $self->_log (debug => "calc_sections: req_params (@{[ sort @req_params ]})");

    my $mult; foreach my $rp (@req_params) { $mult += $mults{$rp} // 1; }

    my $t0 = [gettimeofday];
    $self->_init_progress (tot => $mult * $self->ebt->get_count);
    $self->_ua_get ($mult * $self->ebt->get_count, @req_params);
    $self->_log (debug => report 'calc_sections', $t0);

    my $filename = substr +(sha512_hex rand), 0, 8;
    my $tmpfile = File::Spec->catfile ($tmpdir, "out-$filename");
    $self->_log (debug => "storing req_params in '$tmpfile'");
    store \@req_params, $tmpfile;

    $self->_end_progress ($filename);

    return;
}

sub gen_output {
    my ($self) = @_;

    my $tmpfile = File::Spec->catfile ($tmpdir, 'out-' . $self->stash ('filename'));
    return $self->render_not_found unless -e $tmpfile;
    $self->_log (debug => "retrieving req_params from file '$tmpfile'");
    my @req_params = @{ retrieve $tmpfile };
    $self->_log (debug => "loaded req_params (@{[ sort @req_params ]})");
    unlink $tmpfile or $self->_log (warn => "unlink: '$tmpfile': $!");

    $self->$_ for @req_params;

    my $html_dir = File::Spec->catfile ($self->stash ('html_dir'), $self->stash ('user'));
    $self->_log (debug => "gen_output: html_dir '$html_dir'");
    $self->_prepare_html_dir ($html_dir);
    my $html_output = encode 'UTF-8', $self->render_to_string (template => 'layouts/offline', format => 'html', images_prefix => '../../');
    $html_output = $self->_trim_html_sections ($html_output, @req_params);

    my $t0 = [gettimeofday];
    $self->_save_html ($html_dir, $html_output, @req_params);

    my $src = File::Spec->catfile ($self->stash ('statics_dir'), sprintf 'images/%s', $self->stash ('user'));
    my $globpat = "$src/static/*"; $globpat =~ s/ /\\ /g;
    defined unlink glob $globpat or $self->_log (warn => "unlink: $!");
    $globpat = "$src/*.svg"; $globpat =~ s/ /\\ /g;
    foreach my $svg (glob $globpat) {
        my $dest_dir = "$html_dir/images/".$self->stash ('user');
        copy $svg, $dest_dir or $self->_log (warn => "copy: '$svg' to '$dest_dir': $!");
    }

    my @rendered_bbcode;
    foreach my $param (@req_params) {
        ## missing templates yield an undef result
        my $r = $self->render_to_string (template => "main/$param", format => 'txt');
        push @rendered_bbcode, { title => $section_titles{$param}, text => $r };
    }
    #$self->_log (debug => report 'gen_output render', $t0);

    $self->stash (
        format     => 'html',
        title      => $section_titles{'bbcode'},
        user       => undef,
        url        => $self->stash ('public_stats'),
        req_params => [ map { $section_titles{$_} } @req_params ],
        bbcode     => \@rendered_bbcode,
    );
}

1;
