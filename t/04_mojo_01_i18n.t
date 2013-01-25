#!/usr/bin/perl

use warnings;
use strict;
use utf8; binmode *STDOUT, ':encoding(utf8)'; binmode *STDERR, ':encoding(utf8)';
use Cwd;
use File::Basename 'dirname';
use Test::More;
use Test::Mojo;

plan tests => 114;

my ($t, $csrftoken);

## all words that don't need translation (e.g. "Trichet")
my %es; $es{$_} = $_ for 
    qw{
        EBTST EUR foouser BBCode/HTML Dioniz Duisenberg Trichet Draghi 
        :flag-at: :flag-be: :flag-cy: :flag-de: :flag-es: :flag-fi: :flag-fr: :flag-gr: :flag-ie: :flag-it: :flag-mt: :flag-nl: :flag-pt: :flag-si: :flag-sk: :flag-uk:
        :arrow: :note-5: :note-10: :note-20: :note-50: :note-100: :note-200: :note-500:
    },
    'A' .. 'Z',                                         ## country/printer codes, alphabets
    qw/Belgrade Lipjan Madrid Paris Visoko/,            ## cities used in testing
    qw/BBB AAAAA AAAAAA/,                               ## nice serials
    qw/Lxxxx Sxxxx Vxxxx Txxxx Lxxxx Vxxxx Sxxxx xxx/,  ## hit list
    qw/Spain/,                                          ## help
;
my @bbcode_tags = (
    '[b]', '[/b]', '[i]', '[/i]', '[table]', '[/table]', '[tr]', '[/tr]', '[td]', '[/td]',
    '[url=https://eurobilltracker.com/notes/?id=', '[url=https://en.eurobilltracker.com/profile/?user=', '[/url]',
    '[color=black]', '[color=blue]', '[color=green]', '[color=red]', '[color=#000]', '[color=#B0B0B0]', '[color=#C0A000]', '[color=darkblue]', '[color=darkred]', '[/color]',
    '[img]/images/ba.gif[/img]',
    '[img]/images/rskm.gif[/img]',
    '[img]/images/rsme.gif[/img]',
);

sub next_is_xhr {
    $t->ua->once (start => sub {
        my ($ua, $tx) = @_;
        $tx->req->headers->header ('X-Requested-With', 'XMLHttpRequest');
    });
}

sub remove_xlated {
    my $dom = $t->tx->res->dom;
    $dom->find ('script')->each (sub { shift->replace ('') });
    my $all_text = sprintf ' %s ', $dom->all_text;    ## \W in the regex doesn't match either ^ or $. Workaround that

    ## @bbcode_tags first, otherwise we remove the spanish preposition 'de' as part of values %es and end up with ':flag-:' instead of ':flag-de:'
    $all_text =~ s/$_//g for reverse sort { (length $a) <=> (length $b) } map quotemeta, @bbcode_tags;
    foreach my $pattern (reverse sort { (length $a) <=> (length $b) } map quotemeta, values %es) {
        ## one of the help texts has some embedded HTML, which isn't present in $all_text. Remove it from the substitution pattern too
        $pattern =~ s{\\<img\\ src\\=\\"images\\/values\\/\d+\\\.gif\\"\\>}{}g;

        ## ignore case in the first letter. Some templates call ucfirst on the translated text
        if ($pattern =~ /^(\w)(.*)/) { $pattern = "(?i)$1(?-i)$2"; }

        ## can't use \b around the pattern because some sentences begin/end with non alphanumerics (e.g. "Combinations (bingo) = Combinaciones (bingo)")
        $all_text =~ s/(?<=[\W\d])$pattern(?=[\W\d])//g;
    }

    $all_text =~ s/^[\W\d]+//;
    $all_text =~ s/[\W\d]+/ /g;
    $all_text =~ s/[\W\d]+$//;
    return $all_text;
}

if (-f '/tmp/ebt2-storable') { unlink '/tmp/ebt2-storable' or die "unlink: '/tmp/ebt2-storable': $!"; }
if (-f '/home/hue/.ebt/ebtst-user-data/foouser/db') { unlink '/home/hue/.ebt/ebtst-user-data/foouser/db' or die "unlink: '/home/hue/.ebt/ebtst-user-data/foouser/db': $!"; }

$ENV{'BASE_DIR'} = File::Spec->catfile (getcwd, (dirname __FILE__), '..');

open my $esfd, '<:encoding(UTF-8)', 'es.txt' or die "open: 'es.txt': $!";
while (<$esfd>) {
    next if /^\s*$/;
    next if /^#/;
    chomp;
    my ($orig, $xlated) = split /\s*=\s*/, $_, 2;
    die "Repeated translation '$orig'\n" if exists $es{$orig};
    $es{$orig} = $xlated;
}
close $esfd;

$::enc_key = 'test';
my $all_text;
$t = Test::Mojo->new ('EBTST');
$t->ua->on (start => sub {
    my ($ua, $tx) = @_;
    $tx->req->headers->header ('Accept-Language', 'es');
});

$t->get_ok ('/'); $all_text = remove_xlated; is $all_text, '', 'translation of /';

$t->post_form_ok ('/login' => {
    user => 'foouser',
    pass => 'foopass',
})->status_is (302);

$t->get_ok ('/configure'); $all_text = remove_xlated; is $all_text, '', 'translation of /configure';

$t->post_form_ok ('/upload', {
    notes_csv_file => { file => 't/notes5.csv' },
    hits_csv_file  => { file => 't/hits5.csv' },
})->status_is (200);
my $sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200);

foreach my $section (qw/
    information value countries printers locations travel_stats huge_table short_codes nice_serials coords_bingo notes_per_year notes_per_month
    top_days time_analysis_bingo time_analysis_detail combs_bingo combs_detail plate_bingo hit_list hit_times_bingo hit_times_detail
    hit_locations hit_analysis hit_summary calendar help
/) {
    $t->get_ok ("/$section");     $all_text = remove_xlated; is $all_text, '', "translation of /$section";
    $t->get_ok ("/$section.txt"); $all_text = remove_xlated; is $all_text, '', "translation of /$section.txt";
}

$t->ua->unsubscribe ('start');
