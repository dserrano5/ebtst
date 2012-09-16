#!/usr/bin/perl

use warnings;
use strict;
use utf8; binmode *STDOUT, ':encoding(utf8)'; binmode *STDERR, ':encoding(utf8)';
use Cwd;
use File::Basename 'dirname';
use Test::More;
use Test::Mojo;

my ($t, $csrftoken);

sub next_is_xhr {
    $t->ua->once (start => sub {
        my ($ua, $tx) = @_;
        $tx->req->headers->header ('X-Requested-With', 'XMLHttpRequest');
    });
}

if (-f '/tmp/ebt2-storable') { unlink '/tmp/ebt2-storable' or die "unlink: '/tmp/ebt2-storable': $!"; }
if (-f '/home/hue/.ebt/ebtst-user-data/foouser/db') { unlink '/home/hue/.ebt/ebtst-user-data/foouser/db' or die "unlink: '/home/hue/.ebt/ebtst-user-data/foouser/db': $!"; }
unlink glob '/home/hue/ll/lang/perl/ebt-mojo-iframes2/public/images/foouser/*svg';
unlink glob '/home/hue/ll/lang/perl/ebt-mojo-iframes2/public/images/latinºchars/*svg';
unlink glob '/home/hue/ll/lang/perl/ebt-mojo-iframes2/public/images/unicode⑤chars/*svg';
unlink glob '/home/hue/ll/lang/perl/ebt-mojo-iframes2/public/images/latuniº⑤chars/*svg';
$ENV{'BASE_DIR'} = File::Spec->catfile (getcwd, (dirname __FILE__), '..');

$t = Test::Mojo->new ('EBTST');

## wrong password
$t->get_ok ('/')->status_is (200)->element_exists ('#mainbody #repl form[id="login"]', 'login form');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->form->input->[0]->{'value'};

$t->post_form_ok ('/login' => {
    user => 'foouser',
    pass => 'invalid pass',
    #csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/index/, 'redir to index');

## session needed
$t->get_ok ('/progress')->status_is (302)->header_like (Location => qr/index/, 'session needed');
$t->get_ok ('/configure')->status_is (302)->header_like (Location => qr/index/, 'session needed');

## EBT2 object needed
$t->get_ok ('/value')->status_is (302)->header_like (Location => qr/index/, 'EBT2 object needed');

## correct password
$t->get_ok ('/');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->form->input->[0]->{'value'};

$t->post_form_ok ('/login' => {
    user => 'foouser',
    pass => 'foopass',
    #csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/, 'login ok');

## with session
$t->get_ok ('/progress')->status_is (200)->content_type_is ('application/json')->json_content_is ({ cur => 0, total => 1 }, 'default progress');
$t->get_ok ('/configure')->status_is (200)->element_exists ('#mainbody #repl #config_form table tr td input[name=notes_csv_file]', 'configure form')->content_unlike (qr/short_codes/, 'configure without sections');

## EBT2 object needed
$t->get_ok ('/value')->status_is (302)->header_like (Location => qr/configure/, 'EBT2 object needed')->content_unlike (qr/short_codes/, 'no sections');

## upload notes CSV
$t->get_ok ('/configure');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->[1]->form->input->[0]->{'value'};

$t->post_form_ok ('/upload', {
    notes_csv_file => { file => 't/notes1.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain')->content_like (qr/^[0-9a-f]{8}$/, 'upload notes');
my $sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;

$t->get_ok ("/import/$sha")->status_is (404);

my $bad_sha = $sha; $bad_sha =~ tr/0-9a-f/a-f0-9/;
next_is_xhr; $t->get_ok ("/import/$bad_sha")->status_is (404);
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain')->content_is ('information', 'import');

## correct data
$t->get_ok ('/information')->status_is (200)->content_like (qr/\bSignatures:.*\bDuisenberg 0.*\bTrichet 2.*\bDraghi 0\b/s, 'correct data')->content_like (qr/short_codes/, 'with sections');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->[0]->form->input->{'value'};

## /configuration and /help now must show the entire menu
$t->get_ok ('/configure')->status_is (200)->content_like (qr/short_codes/, 'configure has sections');
$t->get_ok ('/help')->status_is (200)->content_like (qr/short_codes/, 'help has sections');

## BBCode/HTML generation
$t->post_form_ok ('/calc_sections', { information => 1, value => 1, })->status_is (404);
next_is_xhr; $t->post_form_ok ('/calc_sections', {
    information => 1,
    value       => 1,
    #csrftoken   => $csrftoken,
})->status_is (200)->content_type_is ('text/plain')->content_like (qr/^[0-9a-z]{8}$/, 'calc_sections');

$t->get_ok ('/information.txt')->status_is (200)->content_type_is ('text/plain')->content_like (qr/Signatures:.*\bDuisenberg 0.*\bTrichet 2.*\bDraghi 0\b/s, 'BBCode information');
$t->get_ok ('/value.txt')->status_is (200)->content_like (qr/\b20\b.*\b1\b.*\b50\.00 %.*\b20\b/s, 'BBCode value');

## upload hits CSV
next_is_xhr; $t->post_form_ok ('/upload', {
    hits_csv_file => { file => 't/hits1.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain')->content_like (qr/^[0-9a-z]{8}$/, 'upload hits');

$sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain')->content_is ('information', 'import hits');

## hit_analysis isn't broken with less than 10 hits
$t->get_ok ('/hit_analysis')->status_is (200)->content_like (qr{<td class="small_cell"><a href="[^"]*">Lxxxx2379xxx</a></td>}, 'hit analysis');

## upload notes and hits CSV
$t->get_ok ('/information');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->[0]->form->input->{'value'};

next_is_xhr; $t->post_form_ok ('/upload', {
    notes_csv_file => { file => 't/notes3.csv' },
    hits_csv_file => { file => 't/hits3.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain')->content_like (qr/^[0-9a-z]{8}$/, 'upload notes and hits');

$sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain')->content_is ('information', 'import notes and hits');

## moderated hits don't appear in hit_list
$t->get_ok ('/hit_list')->status_is (200)->content_unlike (qr/Exxxx0534xxx/, 'moderated hits are ignored');

## but their count appears in hit_summary
$t->get_ok ('/hit_summary')->status_is (200)->content_like (qr/1\s+international\),\s+plus\s+1\s+moderated/, 'but they are counted');

## Kosovo
$t->get_ok ('/locations')->status_is (200)->content_like (qr/Kosovo/, 'Kosovo support');

## logging out
$t->get_ok ('/logout')->status_is (302)->header_like (Location => qr/index/, 'log out');

## logout with an empty database
$t->get_ok ('/');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->form->input->[0]->{'value'};

$t->post_form_ok ('/login' => {
    user => 'emptyuser',
    pass => 'emptypass',
    #csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/, 'log in with empty user');

$t->get_ok ('/information')->status_is (302)->header_like (Location => qr/configure/, 'redir to configure');
$t->get_ok ('/register')->status_is (302)->header_like (Location => qr/information/, 'GET register with session');
$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => 'bar',
    pass2 => 'bar2',
})->status_is (302)->header_like (Location => qr/information/, 'POST register with session');
$t->get_ok ('/logout')->status_is (302)->header_like (Location => qr/index/, 'logout from empty user');

$t->get_ok ('/register')->status_is (200)->content_like (qr/Confirm passphrase/, 'GET register');
$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => 'bar',
    pass2 => 'bar2',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with different passwords');
$t->post_form_ok ('/register' => {
    user  => 'fo<€',
    pass1 => 'bar',
    pass2 => 'bar',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with bad username');
$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => 'b<ar',
    pass2 => 'b<ar',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with bad password');
$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => 'bar',
    pass2 => 'bar',
})->status_is (302)->header_like (Location => qr/configure/, 'POST register');

my $users_file = $t->ua->app->config ('users_db');
open my $fd, '<:encoding(UTF-8)', $users_file or die "open: '$users_file': $!"; my @lines = <$fd>; close $fd;
my $user = pop @lines; chomp $user;
is $user, 'fo€:d82c4eb5261cb9c8aa9855edd67d1bd10482f41529858d925094d173fa662aa91ff39bc5b188615273484021dfb16fd8284cf684ccf0fc795be3aa2fc1e6c181';

$t->get_ok ('/configure')->status_is (200)->element_exists ('#mainbody #repl #config_form table tr td input[name=notes_csv_file]', 'configure form')->content_unlike (qr/short_codes/, 'configure without sections');
$t->get_ok ('/logout');

$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => 'bar42',
    pass2 => 'bar42',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with already existing user');

## restore user db
open $fd, '>:encoding(UTF-8)', $users_file or die "open: '$users_file': $!"; print $fd $_ for @lines; close $fd;

## users with latin-* characters in username
$t->get_ok ('/logout');
$t->post_form_ok ('/login' => {
    user => 'latinºchars',
    pass => 'foopass',
    #csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/, 'log in with latin-* chars user');
$t->get_ok ('/information')->status_is (200);

## users with unicode characters in username
$t->get_ok ('/logout');
$t->post_form_ok ('/login' => {
    user => 'unicode⑤chars',
    pass => 'foopass',
    #csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/, 'log in with unicode chars user');
$t->get_ok ('/information')->status_is (200);

## users with both latin-* and unicode characters in username
$t->get_ok ('/logout');
$t->post_form_ok ('/login' => {
    user => 'latuniº⑤chars',
    pass => 'foopass',
    #csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/, 'log in with latin-* and unicode chars user');
$t->get_ok ('/information')->status_is (200);

done_testing 157;
unlink '/tmp/ebt2-storable' or warn "unlink: '/tmp/ebt2-storable': $!";
