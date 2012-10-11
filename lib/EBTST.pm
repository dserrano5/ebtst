package EBTST;

use Mojo::Base 'Mojolicious';
use Mojo::Util qw/xml_escape/;
use File::Spec;
use Carp qw/croak confess/;
use Fcntl ':flock';
use Config::General;
#use Devel::Size qw/total_size/;
use DBI;
use EBT2;

my $work_dir = EBT2::_work_dir;
my $cfg_file = File::Spec->catfile ($work_dir, 'ebtst.cfg');
-r $cfg_file or die "Can't find configuration file '$cfg_file'\n";
our %config = Config::General->new (-ConfigFile => $cfg_file, -IncludeRelative => 1, -UTF8 => 1)->getall;

defined $config{'users_db'} or die "'users_db' isn't configured\n";
defined $config{'csvs_dir'} or die "'csvs_dir' isn't configured\n";
my $sess_dir                    = $config{'session_dir'}       // die "'session_dir' isn't configured\n";
my $user_data_basedir           = $config{'user_data_basedir'} // die "'user_data_basedir' isn't configured\n";
my $html_dir                    = $config{'html_dir'}    // File::Spec->catfile ($ENV{'BASE_DIR'}, 'public', 'stats');
my $statics_dir                 = $config{'statics_dir'} // File::Spec->catfile ($ENV{'BASE_DIR'}, 'public');
my $images_dir                  = File::Spec->catfile ($config{'statics_dir'} ? $config{'statics_dir'} : ($ENV{'BASE_DIR'}, 'public'), 'images');
my $session_expire              = $config{'session_expire'} // 30;
my $base_href                   = $config{'base_href'};
our @graphs_colors              = $config{'graphs_colors'} ? (split /[\s,]+/, $config{'graphs_colors'}) : ('blue', 'green', '#FFBF00', 'red', 'black');
my $max_rss_size                = $config{'max_rss_size'} // 150e3;
my $hypnotoad_listen            = $config{'hypnotoad_listen'} // 'http://localhost:3000'; $hypnotoad_listen = [ $hypnotoad_listen ] if 'ARRAY' ne ref $hypnotoad_listen;
my $hypnotoad_accepts           = $config{'hypnotoad_accepts'} // 1000;             ## Mojo::Server::Hypnotoad default
my $hypnotoad_keep_alive_requests = $config{'hypnotoad_keep_alive_requests'} // 25; ## Mojo::Server::Hypnotoad default
my $hypnotoad_is_proxy          = $config{'hypnotoad_is_proxy'} // 0;
my $hypnotoad_heartbeat_timeout = $config{'hypnotoad_heartbeat_timeout'} // 60;
my $hypnotoad_workers           = $config{'hypnotoad_workers'} // 4;                ## Mojo::Server::Hypnotoad default
my $base_parts = @{ Mojo::URL->new ($base_href)->path->parts };

sub _mkdir {
    my ($dir) = @_;
    my @parents;

    my @parts = split m{/}, $dir;

    my $is_abs = '/' eq substr $dir, 0, 1;
    my $start = 0 + $is_abs;
    foreach my $last ($start..$#parts) {
        push @parents, join '/', @parts[0..$last];
    }

    foreach my $p (@parents) {
        next if -d $p;
        mkdir $p or die "mkdir: '$p': $!";
    }

    return;
}

sub helper_rss_process {
    my ($self) = @_;

    local $_;
    if (open my $fd, '<', "/proc/$$/status") {
        while (<$fd>) {
            next unless /^VmRSS:\s*(\d+)\s*kB/;
            close $fd;
            return $1;
        }
    } else {
        $self->app->log->warn ("helper_rss_process: open: '/proc/$$/status': $!");
    }
}

sub _inc {
    my ($coderef, $filename) = @_;

    return if $filename !~ m{EBTST/I18N/..\.pm};

    my $class = $filename;
    $class =~ s{/}{::}g;
    $class =~ s/\.pm$//;

    my $contents = q{
        package _CLASS;

        use Mojo::Base 'EBTST::I18N';
        use EBTST::I18N;

        EBTST::I18N::setup_lex +(split '::', __PACKAGE__)[-1], \our %Lexicon;

        1;
    };
    $contents =~ s/_CLASS/$class/;

    return \$contents;
}

my $srand;
sub bd_set_env_initial_stash {
    my $self = shift;

    my $al = $self->tx->req->content->headers->accept_language // ''; $ENV{'LANG'} = substr $al, 0, 2;  ## could be improved...

    $srand ||= srand;   ## suboptimal but otherwise I get repeated TIDs among different child processes
    $ENV{'EBTST_SRC_IP'} = $self->tx->remote_address;
    $ENV{'EBTST_TID'} = join '', map { ('a'..'z','A'..'Z',0..9)[rand 62] } 1..12;
    delete $ENV{'EBTST_USER'};

    $self->stash (base_href     => $base_href);
    $self->stash (checked_boxes => {});
    $self->stash (html_hrefs    => {});
    $self->stash (public_stats  => undef);
    $self->stash (has_notes     => undef);
    $self->stash (has_hits      => undef);
    $self->stash (has_bad_notes => undef);
    $self->stash (user          => undef);
    $self->stash (msg           => '');
    $self->stash (title         => '');
}

sub helper_ebt {
    my ($self) = @_;

    if (ref $self->stash ('ebt')) {
        my $ret = $self->stash ('ebt');
        return $ret;
    } else {
        confess "Oops, this shouldn't happen";
    }
}

sub helper_color {
    my ($self, $num, $what) = @_;
    my $color;

    if ('notes' eq $what) {
        if (!$num)                             { $color = '#B0B0B0';
        } elsif ($num >=    1 and $num <=  49) { $color = $graphs_colors[0];
        } elsif ($num >=   50 and $num <=  99) { $color = $graphs_colors[1];
        } elsif ($num >=  100 and $num <= 499) { $color = $graphs_colors[2];
        } elsif ($num >=  500 and $num <= 999) { $color = $graphs_colors[3];
        } elsif ($num >= 1000)                 { $color = $graphs_colors[4];
        } else {
            die "Should not happen, num ($num) what ($what)";
        }
    } elsif ('hits' eq $what) {
        if (!$num)                         { $color = '#B0B0B0';
        } elsif ($num ==  1)               { $color = $graphs_colors[0];
        } elsif ($num ==  2)               { $color = $graphs_colors[1];
        } elsif ($num >=  3 and $num <= 4) { $color = $graphs_colors[2];
        } elsif ($num >=  5 and $num <= 9) { $color = $graphs_colors[3];
        } elsif ($num >= 10)               { $color = $graphs_colors[4];
        } else {
            die "Should not happen, num ($num) what ($what)";
        }
    } else {
        die "Don't know what to color";
    }

    return $color;
}

## only used from templates/main/help.html.ep, which uses a different mechanism for translations
sub helper_l2 {
    my ($self, $txt) = @_;

    my $ret = $self->l ($txt);
    return $ret if '_' ne substr $ret, 0, 1;

    my @save_langs = $self->stash->{i18n}->languages;
    $self->stash->{i18n}->languages ('en');
    $ret = $self->l ($txt);
    $self->stash->{i18n}->languages (@save_langs);

    return $ret;
}

## for the hit templates
sub helper_hit_partners {
    my ($self, $mode, $my_id, $partners, $partner_ids) = @_;

    my $before = 1;
    my @visible;
    foreach my $idx (0 .. $#$partners) {
        my $name = $partners->[$idx];
        my $id   = $partner_ids->[$idx];
        if ($id eq $my_id) { $before = 0; next; }
        if ($before) {
            if ('html' eq $mode) {
                push @visible,
                    (sprintf '<a href="https://en.eurobilltracker.com/profile/?user=%s">%s</a>', $id, xml_escape $name),
                    '<img src="images/red_arrow.gif">';
            } elsif ('txt' eq $mode) {
                push @visible, sprintf "[color=darkred]%s[/color] [url=https://en.eurobilltracker.com/profile/?user=%s]%s[/url]", ($self->l ('from')), $id, $name;
            }
        } else {
            if ('html' eq $mode) {
                push @visible,
                    '<img src="images/blue_arrow.gif">',
                    (sprintf '<a href="https://en.eurobilltracker.com/profile/?user=%s">%s</a>', $id, xml_escape $name);
            } elsif ('txt' eq $mode) {
                push @visible, sprintf "[color=darkblue]%s[/color] [url=https://en.eurobilltracker.com/profile/?user=%s]%s[/url]", ($self->l ('to')), $id, $name;
            }
        }
    }
    return join ' ', @visible;
}

sub ad_rss_sigquit {
    my ($self) = @_;

    my $rss = $self->rss_process or return;
    if ($rss > $max_rss_size) {
        $self->app->log->debug ("process $$ RSS is $rss Kb, sending SIGQUIT and closing connection");
        $self->res->headers->connection ('close');
        kill QUIT => $$;    ## hypnotoad-specific, breaks morbo
    }# else { $self->app->log->debug ("process $$ RSS is $rss Kb"); }
    return;
}

## would put this into an after_dispatch hook, but $self->stash('ebt') doesn't seem to be available there
#sub log_sizes {
#    my ($log, $ebt) = @_;
#
#    my %sizes = (
#        ebt2 => (total_size $ebt),
#        (map { $_ => total_size $ebt->{'data'}{$_} } keys %{ $ebt->{'data'} }),
#    );
#
#    foreach my $k (
#        reverse
#        sort { ($sizes{$a}) <=> ($sizes{$b}) }
#        grep { $sizes{$_} > $sizes{'ebt2'}/100 and $sizes{$_} > 512*1024 }
#        keys %sizes
#    ) {
#        $log->debug (sprintf '%35s: %6.0f Kb', $k, ($sizes{$k})/1024);
#    }
#}

## TODO: I don't think this is the right place for this code
sub helper_html_hrefs {
    my ($self) = @_;

    my %done_data;
    my @keys = $self->ebt->done_data;
    @keys and undef @done_data{@keys};

    my %html_hrefs;
    $html_hrefs{'information'}          = undef if exists $done_data{'activity'};
    $html_hrefs{'value'}                = undef if exists $done_data{'notes_by_value'};
    $html_hrefs{'countries'}            = undef if exists $done_data{'notes_by_cc'};
    $html_hrefs{'printers'}             = undef if exists $done_data{'notes_by_pc'};
    $html_hrefs{'locations'}            = undef if exists $done_data{'notes_by_city'};
    $html_hrefs{'travel_stats'}         = undef if exists $done_data{'travel_stats'};
    $html_hrefs{'huge_table'}           = undef if exists $done_data{'huge_table'};
    $html_hrefs{'short_codes'}          = undef if exists $done_data{'highest_short_codes'};
    $html_hrefs{'nice_serials'}         = undef if exists $done_data{'nice_serials'};
    $html_hrefs{'coords_bingo'}         = undef if exists $done_data{'coords_bingo'};
    $html_hrefs{'notes_per_year'}       = undef if exists $done_data{'notes_per_year'};
    $html_hrefs{'notes_per_month'}      = undef if exists $done_data{'notes_per_month'};
    $html_hrefs{'top_days'}             = undef if exists $done_data{'top10days'};
    $html_hrefs{'time_analysis_bingo'}  = undef if exists $done_data{'time_analysis'};
    $html_hrefs{'time_analysis_detail'} = undef if exists $done_data{'time_analysis'};
    $html_hrefs{'combs_bingo'}          = undef if exists $done_data{'notes_by_combination'};
    $html_hrefs{'combs_detail'}         = undef if exists $done_data{'notes_by_combination'};
    $html_hrefs{'plate_bingo'}          = undef if exists $done_data{'plate_bingo'};
    $html_hrefs{'hit_list'}             = undef if exists $done_data{'hit_list'};
    $html_hrefs{'hit_times_bingo'}      = undef if exists $done_data{'hit_times'};
    $html_hrefs{'hit_times_detail'}     = undef if exists $done_data{'hit_times'};
    $html_hrefs{'hit_locations'}        = undef if exists $done_data{'notes_by_city'} and exists $done_data{'hit_list'};
    $html_hrefs{'hit_analysis'}         = undef if exists $done_data{'hit_analysis'};
    $html_hrefs{'hit_summary'}          = undef if exists $done_data{'hit_summary'};
    $html_hrefs{'calendar'}             = undef if exists $done_data{'calendar'};

    return %html_hrefs;
}

sub startup {
    my ($self) = @_;

    push @INC, \&_inc;

    _mkdir $sess_dir;
    _mkdir $html_dir;
    _mkdir $statics_dir;
    _mkdir $images_dir;
    _mkdir $config{'csvs_dir'};

    $self->types->type (txt => 'text/plain; charset=utf-8');

    ## quickly hackly emulate the relevant CREATE TABLE
    if (!-f "$sess_dir/session") {
        open my $fd, '>', "$sess_dir/session" or die "open: '$sess_dir/session': $!";
        print $fd "sid,data,expires\n";
        close $fd;
    }

    $self->app->config ({
        hypnotoad => {
            accepts           => $hypnotoad_accepts,
            keep_alive_requests => $hypnotoad_keep_alive_requests,
            listen            => $hypnotoad_listen,
            proxy             => $hypnotoad_is_proxy,
            heartbeat_timeout => $hypnotoad_heartbeat_timeout,
            workers           => $hypnotoad_workers,
        },
        users_db => $config{'users_db'},
        ## TODO: fill this
    });

    $self->app->log->unsubscribe ('message');
    $self->app->log->on (message => sub {
        ## ripped from Mojo::Log
        my ($self, $level, @messages) = @_;
        return unless my $handle = $self->handle;

        return if $messages[-1] =~ /Routing to a callback\.$/;
        my $txt = $self->format ($level, @messages);
        my $ip   = $ENV{'EBTST_SRC_IP'} // 'no_ip';
        my $user = $ENV{'EBTST_USER'}   // 'no_user';
        my $tid  = $ENV{'EBTST_TID'}    // 'no_tid';
        my $pid  = $$;
        $txt =~ s/^(\[[^]]+\]) (\[\w+\]) /$1 [$ip] [$user] [$pid] [$tid] $2 /;

        flock $handle, LOCK_EX;
        croak "Can't write to log: $!" unless defined $handle->syswrite ($txt);
        flock $handle, LOCK_UN;
    });

    ## In case of CSRF token mismatch, Mojolicious::Plugin::CSRFDefender calls render without specifying a layout,
    ## then our layout 'online' is rendered and Mojo croaks on non-declared variables. Work that around.
    $self->hook (before_dispatch => \&bd_set_env_initial_stash);

    $self->hook (after_dispatch  => \&ad_rss_sigquit);

    if ($self->mode eq 'production') {
        $self->hook (before_dispatch => sub {
            my $self = shift;

            ## Move prefix from path to base path
            push @{$self->req->url->base->path->parts}, shift @{$self->req->url->path->parts} for 1..$base_parts;
            $self->stash (production => 1);
        });
    } else {
        $self->hook (before_dispatch => sub {
            my $self = shift;

            $self->stash (production => 0);
        });
    }

    my $dbh = DBI->connect ('dbi:CSV:', undef, undef, {
        f_dir            => $sess_dir,
        f_encoding       => 'utf8',
        #csv_eol          => "\r\n",
        #csv_sep_char     => ",",
        #csv_quote_char   => '"',
        #csv_escape_char  => '"',
        RaiseError       => 1,
        #PrintError       => 1,
    }) or die $DBI::errstr;

    $self->helper (ebt => \&helper_ebt);
    $self->helper (color => \&helper_color);
    $self->helper (l2 => \&helper_l2);
    $self->helper (hit_partners => \&helper_hit_partners);
    $self->helper (rss_process => \&helper_rss_process);
    $self->helper (html_hrefs => \&helper_html_hrefs);
    $self->secret ('[12:36:04] gnome-screensaver-dialog: gkr-pam: unlocked login keyring');   ## :P
    $self->defaults (layout => 'online');
    $self->plugin ('I18N');

    ## - load /index
    ## - wait some minutes/hours
    ## - try to log in
    ## - boom
    #$self->plugin ('Mojolicious::Plugin::CSRFDefender');

    $self->plugin (session => {
        stash_key     => 'sess',
        store         => [ dbi => { dbh => $dbh } ],
        expires_delta => $session_expire * 60,
    });

    my $r = $self->routes;

    my $r_session_loaded = $r->under (sub {
        my ($self) = @_;

        ref $self->stash ('sess') and $self->stash ('sess')->load;
        $self->stash (requested_url => $self->req->url->path->leading_slash (0)->to_string);   ## $self->current_route ?
        $self->stash (user          => $self->stash ('sess')->data ('user'));
        $ENV{'EBTST_USER'} = $self->stash ('user');

        return 1;
    });
    $r_session_loaded->get ('/')->to ('main#index');
    $r_session_loaded->get ('//')->to ('main#index');
    $r_session_loaded->get ('/index')->to ('main#index');
    $r_session_loaded->post ('/login')->to ('main#login');
    $r_session_loaded->route ('/register')->via (qw/GET POST/)->to ('main#register');

    my $r_session = $r_session_loaded->under (sub {
        my ($self) = @_;

        return 1 if ref $self->stash ('sess') and $self->stash ('sess')->sid;

        my $requested_url = $self->stash ('requested_url');
        $self->app->log->debug (sprintf 'set flash: requested_url (before tampering) is (%s)', $requested_url);
        $self->render_not_found if 'progress' eq $requested_url;
        $requested_url = '' if grep { $_ eq $requested_url } qw/logout index calc_sections/;
        $requested_url = '' if $requested_url =~ /^gen_output_/;
        $requested_url = '' if $requested_url =~ m{^import/};
        $requested_url = 'configure' if 'upload' eq $requested_url;
        $self->flash (requested_url => $requested_url);

        if ($self->req->is_xhr) {
            $self->app->log->debug ("no session, is_xhr, redirecting to index, requested_url ($requested_url)");
            $self->render (layout => undef, text => 'index');
        } else {
            $self->app->log->debug ("no session, redirecting to index, requested_url ($requested_url)");
            $self->redirect_to ('index');
        }

        return 0;
    });
    $r_session->get ('/progress')->to ('main#progress');
    $r_session->get ('/logout')->to ('main#logout');
    $r_session->post ('/upload')->to ('main#upload');

    my $r_ebt = $r_session->under (sub {
        my ($self) = @_;

        my $user = $self->stash ('user');
        my $sid = $self->stash ('sess')->sid;

        my $gnuplot_img_dir = File::Spec->catfile ($images_dir, $user);
        my $user_data_dir   = File::Spec->catfile ($user_data_basedir, $user);
        my $db              = File::Spec->catfile ($user_data_dir, 'db');
        _mkdir $gnuplot_img_dir;
        _mkdir "$gnuplot_img_dir/static";
        _mkdir $user_data_dir;

        eval { $self->stash (ebt => EBT2->new (db => $db)); };
        $@ and die "Initializing model: '$@'\n";   ## TODO: this isn's working
        $self->ebt->set_bbcode_flags_base_href ($base_href);
        eval { $self->ebt->load_db; };
        if ($@ and $@ !~ /No such file or directory/) {
            $self->app->log->warn (sprintf "%s: loading db: '%s'. Going on anyway.", $self->stash ('requested_url'), $@);
        }
        $self->ebt->set_logger ($self->app->log);
        #$self->ebt->set_enc_key ($::enc_key);
        $self->ebt->set_xor_key ($::enc_key);
        $self->stash ('sess')->extend_expires;
        #$self->req->is_xhr or log_sizes $self->app->log, $self->ebt;

        if (-e File::Spec->catfile ($html_dir, $user, 'index.html')) {
            my $url;
            if ($base_href) {
                my $stripped = $base_href; $stripped =~ s{/*$}{};
                $url = sprintf '%s/stats/%s', $stripped, $user;
            } else {
                $url = sprintf 'stats/%s/%s', $user, 'index.html';
            }
            $self->stash (public_stats => $url);
        }

        my $cbs = $self->ebt->get_checked_boxes // [];
        my %cbs; @cbs{@$cbs} = (1) x @$cbs;

        my %html_hrefs = $self->html_hrefs;
        $html_hrefs{ $self->stash ('requested_url') } = undef;  ## we are going to work on this right now, so set it as done in the template
        ## TODO: if users requests e.g. notes_per_year, then we should set as done all sections in EBT2's time bundle
        ## err, it's already working... O_o

        $self->stash (checked_boxes => \%cbs);
        $self->stash (html_hrefs    => \%html_hrefs);
        $self->stash (has_notes     => $self->ebt->has_notes);
        $self->stash (has_hits      => $self->ebt->has_hits);
        $self->stash (has_bad_notes => $self->ebt->has_bad_notes);
        $self->stash (html_dir      => $html_dir);
        $self->stash (statics_dir   => $statics_dir);
        $self->stash (images_dir    => $images_dir);

        return 1;

    });

    ## needs EBT2 object, calls ->load_notes
    $r_ebt->route ('/import/:sha', sha => qr/[0-9a-f]{8}/)->name ('import')->to ('main#import');

    ## need EBT2 object for showing the entire menu if $self->stash ('has_notes');
    $r_ebt->get ('/configure')->to ('main#configure');
    $r_ebt->get ('/help')->to ('main#help');

    my $r_notes = $r_ebt->under (sub {
        my ($self) = @_;

        if (!$self->stash ('has_notes')) {
            $self->app->log->debug ('has no notes, redirecting to configure');
            $self->redirect_to ('configure');
            return 0;
        }

        return 1;
    });
    $r_notes->get ('/information')->to ('main#information');
    $r_notes->get ('/value')->to ('main#value');
    $r_notes->get ('/countries')->to ('main#countries');
    $r_notes->get ('/printers')->to ('main#printers');
    $r_notes->get ('/locations')->to ('main#locations');
    $r_notes->get ('/travel_stats')->to ('main#travel_stats');
    $r_notes->get ('/huge_table')->to ('main#huge_table');
    $r_notes->get ('/short_codes')->to ('main#short_codes');
    $r_notes->get ('/nice_serials')->to ('main#nice_serials');
    $r_notes->get ('/coords_bingo')->to ('main#coords_bingo');
    $r_notes->get ('/notes_per_year')->to ('main#notes_per_year');
    $r_notes->get ('/notes_per_month')->to ('main#notes_per_month');
    $r_notes->get ('/top_days')->to ('main#top_days');
    $r_notes->get ('/time_analysis_bingo')->to ('main#time_analysis_bingo');
    $r_notes->get ('/time_analysis_detail')->to ('main#time_analysis_detail');
    $r_notes->get ('/combs_bingo')->to ('main#combs_bingo');
    $r_notes->get ('/combs_detail')->to ('main#combs_detail');
    $r_notes->get ('/plate_bingo')->to ('main#plate_bingo');
    $r_notes->get ('/bad_notes')->to ('main#bad_notes');
    $r_notes->get ('/hit_list')->to ('main#hit_list');
    $r_notes->get ('/hit_times_bingo')->to ('main#hit_times_bingo');
    $r_notes->get ('/hit_times_detail')->to ('main#hit_times_detail');
    $r_notes->get ('/hit_locations')->to ('main#hit_locations');
    $r_notes->get ('/hit_analysis')->to ('main#hit_analysis');
    $r_notes->get ('/hit_summary')->to ('main#hit_summary');
    $r_notes->get ('/calendar')->to ('main#calendar');
    $r_notes->post ('/calc_sections')->to ('main#calc_sections');
    $r_notes->route ('/gen_output_:filename', filename => qr/[0-9a-f]{8}/)->name ('gen_output')->to ('main#gen_output');
    #$r_notes->get ('/charts')->to ('main#charts');
}

1;
