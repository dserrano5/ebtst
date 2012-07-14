package EBTST;

## sacar datos estáticos de EBT.pm y meterlos en configuración
## seleccionar un conjunto de billetes, principalmente los introducidos en un periodo determinado de tiempo, y sacar las estadísticas

use Mojo::Base 'Mojolicious';
use File::Spec;
use Config::General;
use FindBin;
use DBI;
use EBT2;

my $work_dir = EBT2::_work_dir;
my $cfg_file = File::Spec->catfile ($work_dir, 'ebtst.cfg');
-r $cfg_file or die "Can't find configuration file '$cfg_file'\n";
my %config = Config::General->new (-ConfigFile => $cfg_file, -IncludeRelative => 1, -UTF8 => 1)->getall;

my $sess_dir = '/home/hue/.ebt/session-store';
my $user_data_basedir = '/home/hue/.ebt/user-data';

sub startup {
    my ($self) = @_;

    my $ebt;
    my $dbh = DBI->connect ('dbi:CSV:', undef, undef, {
        f_dir            => $sess_dir,
        f_encoding       => "utf8",
        #csv_eol          => "\r\n",
        #csv_sep_char     => ",",
        #csv_quote_char   => '"',
        #csv_escape_char  => '"',
        RaiseError       => 1,
        #PrintError       => 1,
    }) or die $DBI::errstr;

    $self->helper (ebt => sub { return $ebt; });
    $self->secret ('[12:36:04] gnome-screensaver-dialog: gkr-pam: unlocked login keyring');   ## :P
    $self->defaults (layout => 'online');
    $self->plugin ('I18N');
    $self->plugin ('Mojolicious::Plugin::CSRFDefender');
    $self->plugin (session => {
        stash_key     => 'sess',
        store         => [ dbi => { dbh => $dbh } ],
        expires_delta => 30*60,
    });

    #$self->hook (before_dispatch => sub {
    #    my ($self) = @_;
    #    #$ENV{'EBT_LANG'} = (split /[;,-]/, $self->req->headers->accept_language)[0];
    #    $ENV{'EBT_LANG'} = substr +($self->req->headers->accept_language // 'en'), 0, 2;
    #});

    my $r = $self->routes;

    my $r_has_notes = $r->under (sub {
        my ($self) = @_;

        $self->stash (has_notes => defined $self->ebt && $self->ebt->has_notes);
        $self->stash (user => undef);
        return 1;
    });
    $r_has_notes->get ('/')->to ('main#index');
    $r_has_notes->post ('/login')->to ('main#login');
    my $r_user = $r_has_notes->under (sub {
        my ($self) = @_;

        if (ref $self->stash ('sess') and $self->stash ('sess')->load) {
            my $user = $self->stash ('sess')->data ('user');

            my $user_data_dir = File::Spec->catfile ($user_data_basedir, $user);
            my $html_dir      = File::Spec->catfile ($user_data_dir, 'html');
            my $db            = File::Spec->catfile ($user_data_dir, 'db');

            $self->stash (user      => $user);
            $self->stash (html_dir  => $html_dir);

            if (!-d $user_data_dir) { mkdir $user_data_dir or die "mkdir: '$user_data_dir': $!"; }
            if (!-d $html_dir)      { mkdir $html_dir      or die "mkdir: '$html_dir': $!"; }
            eval { $ebt = EBT2->new (db => $db); };
            $@ and die "Initializing model: '$@'\n";
            eval { $ebt->load_db; };
            if ($@ and $@ !~ /No such file or directory/) {
                warn "Loading db: '$@'. Going on anyway.\n";
            }
            $self->stash (has_notes => $self->ebt->has_notes);

            return 1;
        }
        $self->redirect_to ('/');
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
    $u->post ('/gen_output')->to ('main#gen_output');
    #$u->get ('/charts')->to ('main#charts');
}

1;
