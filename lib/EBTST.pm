package EBTST;

use Mojo::Base 'Mojolicious';
use File::Spec;
use Config::General;
use DBI;
use EBT2;

my $work_dir = EBT2::_work_dir;
my $cfg_file = File::Spec->catfile ($work_dir, 'ebtst.cfg');
-r $cfg_file or die "Can't find configuration file '$cfg_file'\n";
our %config = Config::General->new (-ConfigFile => $cfg_file, -IncludeRelative => 1, -UTF8 => 1)->getall;

my $sess_dir                    = $config{'session_dir'}       // die "'session_dir' isn't configured";
my $user_data_basedir           = $config{'user_data_basedir'} // die "'user_data_basedir' isn't configured";
my $html_dir                    = $config{'html_dir'}    // File::Spec->catfile ($ENV{'BASE_DIR'}, 'public', 'stats');
my $statics_dir                 = $config{'statics_dir'} // File::Spec->catfile ($ENV{'BASE_DIR'}, 'public');
my $images_dir                  = File::Spec->catfile ($config{'statics_dir'} ? $config{'statics_dir'} : ($ENV{'BASE_DIR'}, 'public'), 'images');
my $session_expire              = $config{'session_expire'} // 30;
my $base_href                   = $config{'base_href'};
our @graphs_colors              = $config{'graphs_colors'} ? (split /[\s,]+/, $config{'graphs_colors'}) : ('blue', 'green', '#FFBF00', 'red', 'black');
my $hypnotoad_listen            = $config{'hypnotoad_listen'} // 'http://localhost:3000'; $hypnotoad_listen = [ $hypnotoad_listen ] if 'ARRAY' ne ref $hypnotoad_listen;
my $hypnotoad_is_proxy          = $config{'hypnotoad_is_proxy'} // 0;
my $hypnotoad_heartbeat_timeout = $config{'hypnotoad_heartbeat_timeout'} // 60;
my $base_parts = @{ Mojo::URL->new ($base_href)->path->parts };

sub startup {
    my ($self) = @_;

    $self->app->config ({
        hypnotoad => {
            listen => $hypnotoad_listen,
            proxy  => $hypnotoad_is_proxy,
        }
    });

    ## In case of CSRF token mismatch, Mojolicious::Plugin::CSRFDefender calls render without specifying a layout,
    ## then our layout 'online' is rendered and Mojo croaks on non-declared variables. Work that around.
    $self->hook (before_dispatch => sub {
        my $self = shift;

        my $al = $self->tx->req->content->headers->accept_language // ''; $ENV{'LANG'} = substr $al, 0, 2;  ## could be improved...
        $self->stash (base_href     => $base_href);
        $self->stash (checked_boxes => {});
        $self->stash (public_stats  => undef);
        $self->stash (has_notes     => undef);
        $self->stash (has_hits      => undef);
        $self->stash (has_bad_notes => undef);
        $self->stash (user          => undef);
    });

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

    $self->helper (ebt => sub {
        my ($self) = @_;

        if (ref $self->stash ('ebt')) {
            my $ret = $self->stash ('ebt');
            return $ret;
        } else {
            die "Oops, this shouldn't happen";
        }
    });
    $self->helper (color => sub {
        my ($self, $num) = @_;
        my $color;

        if (!$num)                             { $color = '#B0B0B0';
        } elsif ($num >=    1 and $num <=  49) { $color = $graphs_colors[0];
        } elsif ($num >=   50 and $num <=  99) { $color = $graphs_colors[1];
        } elsif ($num >=  100 and $num <= 499) { $color = $graphs_colors[2];
        } elsif ($num >=  500 and $num <= 999) { $color = $graphs_colors[3];
        } elsif ($num >= 1000)                 { $color = $graphs_colors[4];
        } else {
            die "Should not happen, num ($num)";
        }

        return $color;
    });
    $self->secret ('[12:36:04] gnome-screensaver-dialog: gkr-pam: unlocked login keyring');   ## :P
    $self->defaults (layout => 'online');
    $self->plugin ('I18N');
    $self->plugin ('Mojolicious::Plugin::CSRFDefender');
    $self->plugin (session => {
        stash_key     => 'sess',
        store         => [ dbi => { dbh => $dbh } ],
        expires_delta => $session_expire * 60,
    });

    my $r = $self->routes;

    my $r_has_notes_hits = $r->under (sub {
        my ($self) = @_;

        if (ref $self->stash ('sess') and $self->stash ('sess')->load) {
            my $user = $self->stash ('sess')->data ('user');
            my $sid = $self->stash ('sess')->sid;
            $self->app->log->debug ("user: '$user'");

            my $gnuplot_img_dir = File::Spec->catfile ($images_dir, $user);
            if (!-d $gnuplot_img_dir) {
                if (!mkdir $gnuplot_img_dir) {
                    die "Couldn't create directory: '$gnuplot_img_dir': $!\n";
                }
                if (!mkdir "$gnuplot_img_dir/static") {
                    die "Couldn't create directory: '$gnuplot_img_dir/static': $!\n";
                }
            }

            my $user_data_dir = File::Spec->catfile ($user_data_basedir, $user);
            my $db            = File::Spec->catfile ($user_data_dir, 'db');

            if (!-d $user_data_dir) { mkdir $user_data_dir or die "mkdir: '$user_data_dir': $!"; }
            if (!-d $html_dir)      { mkdir $html_dir      or die "mkdir: '$html_dir': $!"; }

            eval { $self->stash (ebt => EBT2->new (db => $db)); };
            $@ and die "Initializing model: '$@'\n";   ## TODO: this isn's working
            eval { $self->ebt->load_db; };
            if ($@ and $@ !~ /No such file or directory/) {
                $self->app->log->warn ("loading db: '$@'. Going on anyway.\n");
            }
            $self->stash ('sess')->extend_expires;

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
            $self->stash (checked_boxes => \%cbs);
            $self->stash (has_notes     => $self->ebt->has_notes);
            $self->stash (has_hits      => $self->ebt->has_hits);
            $self->stash (has_bad_notes => $self->ebt->has_bad_notes);
            $self->stash (user          => $user);
            $self->stash (html_dir      => $html_dir);
            $self->stash (statics_dir   => $statics_dir);
            $self->stash (images_dir    => $images_dir);
        }

        return 1;
    });
    $r_has_notes_hits->get ('/')->to ('main#index');
    $r_has_notes_hits->get ('//')->to ('main#index');
    $r_has_notes_hits->get ('/index')->to ('main#index');
    $r_has_notes_hits->post ('/login')->to ('main#login');

    my $r_user = $r_has_notes_hits->under (sub {
        my ($self) = @_;

        if (ref $self->stash ('sess') and $self->stash ('sess')->sid) {
            return 1;
        }

        my $requested_url = $self->req->url->path->leading_slash (0)->to_string;
        $requested_url = '' if grep { $_ eq $requested_url } qw/logout index gen_output/;
        $requested_url = 'configure' if 'upload' eq $requested_url;
        $self->flash (requested_url => $requested_url);
        $self->redirect_to ('index');
        return 0;
    });
    $r_user->get ('/configure')->to ('main#configure');
    $r_user->post ('/upload')->to ('main#upload');
    $r_user->get ('/help')->to ('main#help');
    $r_user->get ('/logout')->to ('main#logout');

    my $u = $r_user->under (sub {
        my ($self) = @_;

        if (!$self->stash ('has_notes')) {
            $self->redirect_to ('configure');
            return 0;
        }

        return 1;
    });
    $u->get ('/information')->to ('main#information');
    $u->get ('/value')->to ('main#value');
    $u->get ('/countries')->to ('main#countries');
    $u->get ('/printers')->to ('main#printers');
    $u->get ('/locations')->to ('main#locations');
    $u->get ('/travel_stats')->to ('main#travel_stats');
    $u->get ('/huge_table')->to ('main#huge_table');
    $u->get ('/short_codes')->to ('main#short_codes');
    $u->get ('/nice_serials')->to ('main#nice_serials');
    $u->get ('/coords_bingo')->to ('main#coords_bingo');
    $u->get ('/notes_per_year')->to ('main#notes_per_year');
    $u->get ('/notes_per_month')->to ('main#notes_per_month');
    $u->get ('/top_days')->to ('main#top_days');
    $u->get ('/time_analysis_bingo')->to ('main#time_analysis_bingo');
    $u->get ('/time_analysis_detail')->to ('main#time_analysis_detail');
    $u->get ('/combs_bingo')->to ('main#combs_bingo');
    $u->get ('/combs_detail')->to ('main#combs_detail');
    #$u->any ([qw/get post/], '/evolution')->to ('main#evolution');
    $u->get ('/plate_bingo')->to ('main#plate_bingo');
    $u->get ('/bad_notes')->to ('main#bad_notes');
    $u->get ('/hit_list')->to ('main#hit_list');
    $u->get ('/hit_times_bingo')->to ('main#hit_times_bingo');
    $u->get ('/hit_times_detail')->to ('main#hit_times_detail');
    $u->get ('/hit_analysis')->to ('main#hit_analysis');
    $u->get ('/hit_summary')->to ('main#hit_summary');
    $u->post ('/gen_output')->to ('main#gen_output');
    #$u->get ('/charts')->to ('main#charts');
}

1;
