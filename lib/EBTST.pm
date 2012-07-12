package EBTST;

## sacar datos estáticos de EBT.pm y meterlos en configuración
## seleccionar un conjunto de billetes, principalmente los introducidos en un periodo determinado de tiempo, y sacar las estadísticas

use Mojo::Base 'Mojolicious';
use FindBin;
use EBT2;

my $db = '/tmp/ebt2-storable';

sub startup {
    my ($self) = @_;

    my $ebt;
    eval { $ebt = EBT2->new (db => $db); };
    $@ and die "Initializing model: $@\n";
    eval { $ebt->load_db; };
    if ($@ and $@ !~ /No such file or directory/) {
        warn "Loading db: $@\n";
    }

    $self->helper (ebt => sub { return $ebt; });
    $self->secret ('[12:36:04] gnome-screensaver-dialog: gkr-pam: unlocked login keyring');   ## :P
    $self->defaults (layout => 'online');
    $self->plugin ('I18N');

    #$self->hook (before_dispatch => sub {
    #    my ($self) = @_;
    #    #$ENV{'EBT_LANG'} = (split /[;,-]/, $self->req->headers->accept_language)[0];
    #    $ENV{'EBT_LANG'} = substr +($self->req->headers->accept_language // 'en'), 0, 2;
    #});

    my $r = $self->routes;

    my $r_has_notes = $r->under (sub {
        my ($self) = @_;

        $self->stash (has_notes => $self->ebt->has_notes);
        return 1;
    });
    $r_has_notes->get ('/configure')->to ('main#configure');
    $r_has_notes->post ('/upload')->to ('main#upload');

    my $u = $r_has_notes->under (sub {
        my ($self) = @_;

        if (!$self->ebt->has_notes) {
            $self->redirect_to ('configure');
            return 0;
        }

        return 1;
    });

    $u->get ('/')->to ('main#index');
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
