package EBTST;

## sacar datos estáticos de EBT.pm y meterlos en configuración
## seleccionar un conjunto de billetes, principalmente los introducidos en un periodo determinado de tiempo, y sacar las estadísticas

use Mojo::Base 'Mojolicious';
use File::Spec;
use File::Basename 'dirname';
use Config::General;
use FindBin;
use DBI;
use EBT2;

my $work_dir = EBT2::_work_dir;
my $cfg_file = File::Spec->catfile ($work_dir, 'ebtst.cfg');
-r $cfg_file or die "Can't find configuration file '$cfg_file'\n";
our %config = Config::General->new (-ConfigFile => $cfg_file, -IncludeRelative => 1, -UTF8 => 1)->getall;

my $sess_dir = $config{'session_dir'};
my $user_data_basedir = $config{'user_data_basedir'};
my $html_dir = $config{'html_dir'} // join '/', dirname(__FILE__), '..', 'public', 'stats';
my $session_expire = $config{'session_expire'} // 30;
my $obj_store;

sub startup {
    my ($self) = @_;

    if ($self->mode eq 'production') {
        $self->hook (before_dispatch => sub {
            my $self = shift;

            ## Move first part from path to base path in production mode
            push @{$self->req->url->base->path->parts}, shift @{$self->req->url->path->parts};
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
    $self->secret ('[12:36:04] gnome-screensaver-dialog: gkr-pam: unlocked login keyring');   ## :P
    $self->defaults (layout => 'online');
    $self->plugin ('I18N');
    $self->plugin ('Mojolicious::Plugin::CSRFDefender');
    $self->plugin (session => {
        stash_key     => 'sess',
        store         => [ dbi => { dbh => $dbh } ],
        expires_delta => $session_expire * 60,
    });

    #$self->hook (before_dispatch => sub {
    #    my ($self) = @_;
    #    #$ENV{'EBT_LANG'} = (split /[;,-]/, $self->req->headers->accept_language)[0];
    #    $ENV{'EBT_LANG'} = substr +($self->req->headers->accept_language // 'en'), 0, 2;
    #});

    my $r = $self->routes;

    my $r_has_notes_hits = $r->under (sub {
        my ($self) = @_;
        my $t = time;

        ## expire old $obj_store entries
        my @sids_to_del;
        for (keys %$obj_store) {
            push @sids_to_del, $_ if $t - $obj_store->{$_}{'ts'} > $session_expire * 60 / 3;
        }
        delete @$obj_store{@sids_to_del};

        if (ref $self->stash ('sess') and $self->stash ('sess')->load) {
            my $user = $self->stash ('sess')->data ('user');
            my $sid = $self->stash ('sess')->sid;

            my $user_data_dir = File::Spec->catfile ($user_data_basedir, $user);
            my $db            = File::Spec->catfile ($user_data_dir, 'db');

            $self->stash (user      => $user);
            $self->stash (html_dir  => $html_dir);

            if (!-d $user_data_dir) { mkdir $user_data_dir or die "mkdir: '$user_data_dir': $!"; }
            if (!-d $html_dir)      { mkdir $html_dir      or die "mkdir: '$html_dir': $!"; }

            if ($obj_store->{$sid}) {
                $self->stash (ebt => $obj_store->{$sid}{'obj'});
            } else {
                eval { $self->stash (ebt => EBT2->new (db => $db)); };
                $@ and die "Initializing model: '$@'\n";
                eval { $self->ebt->load_db; };
                if ($@ and $@ !~ /No such file or directory/) {
                    warn "Loading db: '$@'. Going on anyway.\n";
                }
                $obj_store->{$sid}{'obj'} = $self->stash ('ebt');
            }
            $obj_store->{$sid}{'ts'} = $t;

            $self->stash (has_notes => $self->ebt->has_notes);
            $self->stash (has_hits  => $self->ebt->has_hits);

            return 1;
        }

        $self->stash (has_notes => undef);
        $self->stash (has_hits => undef);
        $self->stash (user => undef);
        return 1;
    });
    $r_has_notes_hits->get ('/')->to ('main#index');
    $r_has_notes_hits->get ('/index')->to ('main#index');
    $r_has_notes_hits->post ('/login')->to ('main#login');
    my $r_user = $r_has_notes_hits->under (sub {
        my ($self) = @_;

        if (ref $self->stash ('sess') and $self->stash ('sess')->sid) {
            return 1;
        }
        $self->redirect_to ('index');
        return 0;
    });
    $r_user->get ('/configure')->to ('main#configure');
    $r_user->post ('/upload')->to ('main#upload');

    my $u = $r_user->under (sub {
        my ($self) = @_;

        if (!$self->stash ('has_notes')) {
            $self->redirect_to ('configure');
            return 0;
        }

        return 1;
    });
    $u->get ('/logout')->to ('main#logout');
    #$u->get ('/quit')->to ('main#quit');
    #$u->get ('/help')->to ('main#help');
    $u->get ('/information')->to ('main#information');
    $u->get ('/value')->to ('main#value');
    $u->get ('/countries')->to ('main#countries');
    $u->get ('/locations')->to ('main#locations');
    $u->get ('/printers')->to ('main#printers');
    $u->get ('/huge_table')->to ('main#huge_table');
    $u->get ('/short_codes')->to ('main#short_codes');
    $u->get ('/nice_serials')->to ('main#nice_serials');
    $u->get ('/coords_bingo')->to ('main#coords_bingo');
    $u->get ('/notes_per_year')->to ('main#notes_per_year');
    $u->get ('/notes_per_month')->to ('main#notes_per_month');
    $u->get ('/top_days')->to ('main#top_days');
    $u->get ('/time_analysis')->to ('main#time_analysis');
    $u->get ('/combs')->to ('main#combs');
    #$u->any ([qw/get post/], '/evolution')->to ('main#evolution');
    $u->get ('/plate_bingo')->to ('main#plate_bingo');
    $u->get ('/hit_list')->to ('main#hit_list');
    $u->get ('/hits_by_month')->to ('main#hits_by_month');
    $u->get ('/hit_analysis')->to ('main#hit_analysis');
    $u->post ('/gen_output')->to ('main#gen_output');
    #$u->get ('/charts')->to ('main#charts');
}

1;
