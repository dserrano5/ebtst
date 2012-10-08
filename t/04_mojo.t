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

$ENV{'EBTST_ENC_KEY'} = 'test';
$t = Test::Mojo->new ('EBTST');


my $users_file = $t->ua->app->config ('users_db');
open my $fd, '<:encoding(UTF-8)', $users_file or die "open: '$users_file': $!"; my @lines = <$fd>; close $fd;
if (5 != @lines) { die 'user database is broken'; }

## wrong password
$t->get_ok ('/')->status_is (200)->element_exists ('#mainbody #repl form[id="login"]', 'login form')->text_is ('div#error_msg' => '', 'no error_msg');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->form->input->[0]->{'value'};

$t->post_form_ok ('/login' => {
    user => 'foouser',
    pass => 'invalid pass',
    #csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/index/, 'redir to index');

$t->get_ok ('/index')->status_is (200)->text_is ('div#error_msg' => 'Wrong username/passphrase', 'Wrong username/passphrase');

## session needed
$t->get_ok ('/progress')->status_is (302)->header_like (Location => qr/index/, 'session needed');
$t->get_ok ('/configure')->status_is (302)->header_like (Location => qr/index/, 'session needed');

## EBT2 object needed
$t->get_ok ('/value')->status_is (302)->header_like (Location => qr/index/, 'EBT2 object needed');

## correct password
$t->get_ok ('/')->text_is ('div#error_msg' => '', 'no error_msg');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->form->input->[0]->{'value'};

$t->post_form_ok ('/login' => {
    user => 'foouser',
    pass => 'foopass',
    #csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/, 'login ok');

## with session
$t->get_ok ('/progress')->status_is (200)->content_type_is ('application/json')->json_content_is ({ cur => 0, total => 1 }, 'default progress');
$t->get_ok ('/configure')->status_is (200)->element_exists ('#mainbody #repl #config_form table tr td input[name=notes_csv_file]', 'configure form')->
    content_unlike (qr/short_codes/, 'configure without sections')->text_is ('div#error_msg' => '', 'no error_msg');

## EBT2 object needed
$t->get_ok ('/value')->status_is (302)->header_like (Location => qr/configure/, 'EBT2 object needed');


$t->get_ok ('/configure')->text_is ('div#error_msg' => '', 'no error_msg');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->[1]->form->input->[0]->{'value'};

$t->post_form_ok ('/upload', {
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_is ('no_csvs', 'upload with no CSVs');


## upload hits CSV, which is an error without notes
$t->post_form_ok ('/upload', {
    hits_csv_file => { file => 't/hits1.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/^[0-9a-f]{8}$/, 'upload hits without notes in the database');
my $sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_is ('no_notes', 'import hits with no notes in the database');


## upload notes CSV
$t->post_form_ok ('/upload', {
    notes_csv_file => { file => 't/notes1.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/^[0-9a-f]{8}$/, 'upload notes');
$sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;

$t->get_ok ("/import/$sha")->status_is (404);

my $bad_sha = $sha; $bad_sha =~ tr/0-9a-f/a-f0-9/;
next_is_xhr; $t->get_ok ("/import/$bad_sha")->status_is (404);
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_is ('information', 'import');

## correct data
$t->get_ok ('/information')->status_is (200)->content_like (qr/\bSignatures:.*\bDuisenberg 0.*\bTrichet 2.*\bDraghi 0\b/s, 'correct data')->
    content_like (qr/short_codes/, 'with sections')->content_unlike (qr/hit_list/, 'with no hit sections')->text_is ('div#error_msg' => '', 'no error_msg');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->[0]->form->input->{'value'};

## /configuration and /help now must show the entire menu
$t->get_ok ('/configure')->status_is (200)->content_like (qr/short_codes/, 'configure has sections')->content_unlike (qr/hit_list/, 'with no hit sections')->
    text_is ('div#error_msg' => '', 'no error_msg');
$t->get_ok ('/help')->status_is (200)->content_like (qr/short_codes/, 'help has sections')->content_unlike (qr/hit_list/, 'with no hit sections')->
    text_is ('div#error_msg' => '', 'no error_msg');

## /travel_stats differentiates cities with the same name in different countries
$t->get_ok ('/travel_stats')->status_is (200)->content_like (qr{Number of locations: <b>2</b>}, 'travel_stats');


## upload again
$t->post_form_ok ('/upload', {
    notes_csv_file => { file => 't/notes1.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/^[0-9a-f]{8}$/, 'upload notes again');
$sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_is ('information', 'import');
$t->get_ok ('/information')->status_is (200)->content_like (qr/\bSignatures:.*\bDuisenberg 0.*\bTrichet 2.*\bDraghi 0\b/s, 'correct data')->
    content_like (qr/short_codes/, 'with sections')->content_unlike (qr/hit_list/, 'with no hit sections')->text_is ('div#error_msg' => '', 'no error_msg');


## BBCode/HTML generation
$t->post_form_ok ('/calc_sections', { information => 1, value => 1, })->status_is (404);
next_is_xhr; $t->post_form_ok ('/calc_sections', {
    information => 1,
    value       => 1,
    #csrftoken   => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/^[0-9a-z]{8}$/, 'calc_sections');

$t->get_ok ('/information.txt')->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/Signatures:.*\bDuisenberg 0.*\bTrichet 2.*\bDraghi 0\b/s, 'BBCode information');
$t->get_ok ('/value.txt')->status_is (200)->content_like (qr/\b20\b.*\b1\b.*\b50\.00 %.*\b20\b/s, 'BBCode value');

## upload hits CSV
next_is_xhr; $t->post_form_ok ('/upload', {
    hits_csv_file => { file => 't/hits1.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/^[0-9a-z]{8}$/, 'upload hits');

$sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_is ('information', 'import hits');

foreach my $section (qw/
    information value countries printers locations travel_stats huge_table short_codes nice_serials coords_bingo notes_per_year notes_per_month
    top_days time_analysis_bingo time_analysis_detail combs_bingo combs_detail plate_bingo hit_list hit_times_bingo hit_times_detail
    hit_locations hit_analysis hit_summary calendar
/) {
    $t->get_ok ("/$section")->status_is (200)->content_unlike (qr{<b>(?:comment|Madrid|Paris|28801|foo|dserrano⑤)</b>}, "escaped markup in $section");
}

## hit_analysis isn't broken with less than 10 hits
$t->get_ok ('/hit_analysis')->status_is (200)->content_like (qr{<td class="small_cell"><a href="[^"]*">Lxxxx2000xxx</a></td>}, 'hit analysis');


## one broken note, inserted today
my @now = localtime; my $now = sprintf '%d-%02d-%02d %02d:%02d:%02d', 1900+$now[5], 1+$now[4], @now[3,2,1,0];
system qq{sed -e 's/__TODAY__/$now/' <t/one-broken-note.csv >/tmp/one-broken-note.csv} and die "system: $!$?";
$t->post_form_ok ('/upload', {
    notes_csv_file => { file => '/tmp/one-broken-note.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/^[0-9a-f]{8}$/, 'upload notes');
unlink '/tmp/one-broken-note.csv' or warn "unlink: '/tmp/one-broken-note.csv': $!";
$sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_is ('information', 'import');
foreach my $section (qw/
    information value countries printers locations travel_stats huge_table short_codes nice_serials coords_bingo notes_per_year notes_per_month
    top_days time_analysis_bingo time_analysis_detail combs_bingo combs_detail plate_bingo hit_list hit_times_bingo hit_times_detail
    hit_locations hit_analysis hit_summary calendar
/) {
    $t->get_ok ("/$section")->status_is (200);
    $t->get_ok ("/$section.txt")->status_is (200);
}


## one passive moderated hit
$t->post_form_ok ('/upload', {
    notes_csv_file => { file => 't/one-passive-mod-hit-notes.csv' },
    hits_csv_file  => { file => 't/one-passive-mod-hit-hits.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/^[0-9a-f]{8}$/, 'upload notes');
$sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_is ('information', 'import');
foreach my $section (qw/
    information value countries printers locations travel_stats huge_table short_codes nice_serials coords_bingo notes_per_year notes_per_month
    top_days time_analysis_bingo time_analysis_detail combs_bingo combs_detail plate_bingo hit_list hit_times_bingo hit_times_detail
    hit_locations hit_analysis hit_summary calendar
/) {
    $t->get_ok ("/$section")->status_is (200);
    $t->get_ok ("/$section.txt")->status_is (200);
}


## upload notes and hits CSV
$t->get_ok ('/information');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->[0]->form->input->{'value'};

next_is_xhr; $t->post_form_ok ('/upload', {
    notes_csv_file => { file => 't/notes5.csv' },
    hits_csv_file => { file => 't/hits5.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/^[0-9a-z]{8}$/, 'upload notes and hits');

$sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_is ('information', 'import notes and hits');

## moderated hits don't appear in hit_list
$t->get_ok ('/hit_list')->status_is (200)->content_unlike (qr/Xxxxx2000xxx/, 'moderated hits are ignored');

## both ways hits
$t->get_ok ('/hit_locations')->status_is (200)->text_is ('table#both_ways_hits > tr:nth-of-type(2) > td:nth-of-type(2)' => '7', 'both ways hits');

## but their count appears in hit_summary
$t->get_ok ('/hit_summary')->status_is (200)->content_like (qr/7\s+international\),\s+plus\s+2\s+moderated/, 'but they are counted');

## misc countries
$t->get_ok ('/locations')->status_is (200)->content_like (qr/Kosovo/, 'Kosovo support')->content_like (qr/Serbia and Montenegro/)->content_like (qr/Bosnia-Herzegovina/);


## incorrect uploads
$t->post_form_ok ('/upload', {
    notes_csv_file => { file => 't/hits1.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/^[0-9a-f]{8}$/, 'upload bad notes CSV');
$sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_is ('bad_notes', 'import bad notes CSV');

$t->post_form_ok ('/upload', {
    hits_csv_file => { file => 't/notes1.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/^[0-9a-f]{8}$/, 'upload bad hits CSV');
$sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_is ('bad_hits', 'import bad hits CSV');

$t->post_form_ok ('/upload', {
    notes_csv_file => { file => 't/hits1.csv' },
    hits_csv_file => { file => 't/notes1.csv' },
    #csrftoken => $csrftoken,
})->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_like (qr/^[0-9a-f]{8}$/, 'upload bad notes and hits CSVs');
$sha = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->text;
next_is_xhr; $t->get_ok ("/import/$sha")->status_is (200)->content_type_is ('text/plain; charset=utf-8')->content_is ('bad_notes', 'import bad notes and hits CSVs');

## logging out
$t->get_ok ('/logout')->status_is (302)->header_like (Location => qr/index/, 'log out');

$t->get_ok ('/');
#$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->form->input->[0]->{'value'};

$t->post_form_ok ('/login' => {
    user => 'emptyuser',
    pass => 'emptypass',
    #csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/, 'log in with emptyuser');
$t->get_ok ('/information')->status_is (302)->header_like (Location => qr/configure/, 'redir to configure');


## registration
$t->get_ok ('/register')->status_is (302)->header_like (Location => qr/information/, 'GET register with session');
$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => 'barbar',
    pass2 => 'barbar2',
})->status_is (302)->header_like (Location => qr/information/, 'POST register with session');
$t->get_ok ('/logout')->status_is (302)->header_like (Location => qr/index/, 'logout from emptyuser');

$t->get_ok ('/register')->status_is (200)->content_like (qr/Confirm passphrase/, 'GET register');
$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => 'barbar',
    pass2 => 'barbar2',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with different passwords')->text_is ('div#error_msg' => 'Passwords do not match');
$t->post_form_ok ('/register' => {
    user  => 'fo<€',
    pass1 => 'barbar',
    pass2 => 'barbar',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with bad username')->text_is ('div#error_msg' => 'Username contains invalid characters');
$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => 'b<arbar',
    pass2 => 'b<arbar',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with bad password')->text_is ('div#error_msg' => 'Password contains invalid characters');
$t->post_form_ok ('/register' => {
    user  => 'fo"€',
    pass1 => 'b>arbar',
    pass2 => 'b>arbar',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with bad username and password')->text_is ('div#error_msg' => 'Username and password contain invalid characters');
$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => 'barbar',
    pass2 => 'barbar',
})->status_is (302)->header_like (Location => qr/configure/, 'POST register');

open $fd, '<:encoding(UTF-8)', $users_file or die "open: '$users_file': $!"; @lines = <$fd>; close $fd;
my $user = pop @lines; chomp $user;
is $user, 'fo€:bc828d429f21f3488802914fcd262e54a99e53f80870a041c24080aa01304eb5feec4962df145e1be2cc7ef40384de59e601923d4ef34d713dd49d616844bed4';

$t->get_ok ('/configure')->status_is (200)->element_exists ('#mainbody #repl #config_form table tr td input[name=notes_csv_file]', 'configure form')->
    content_unlike (qr/short_codes/, 'configure without sections')->text_is ('div#error_msg' => 'Registration successful');
$t->get_ok ('/logout');

$t->post_form_ok ('/register' => {
    user  => '',
    pass1 => 'bar42bar',
    pass2 => 'bar42bar',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with empty user')->text_is ('div#error_msg' => 'Empty user or password');

$t->post_form_ok ('/register' => {
    user  => '  ',
    pass1 => 'bar42bar',
    pass2 => 'bar42bar',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with only-spaces user')->text_is ('div#error_msg' => 'Empty user or password');

$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => '',
    pass2 => '',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with empty password')->text_is ('div#error_msg' => 'Empty user or password');

$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => 'foo',
    pass2 => 'foo',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with short password')->text_is ('div#error_msg' => 'Password is too short');

$t->post_form_ok ('/register' => {
    user  => '',
    pass1 => '',
    pass2 => '',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with empty user and password')->text_is ('div#error_msg' => 'Empty user or password');

$t->post_form_ok ('/register' => {
    user  => 'fo€',
    pass1 => 'bar42bar',
    pass2 => 'bar42bar',
})->status_is (200)->content_like (qr/Confirm passphrase/, 'POST register with already existing user')->text_is ('div#error_msg' => 'User already exists');

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


## MSIE warning
$t->ua->once (start => sub {
    my ($ua, $tx) = @_;
    $tx->req->headers->header ('User-Agent', 'Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0)');
});
$t->get_ok ('/configure')->status_is (200)->content_like (qr/CSV upload doesn't work with Internet Explorer/);



done_testing 550;
