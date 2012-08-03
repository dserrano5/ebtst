#!/usr/bin/perl

use warnings;
use strict;
use Cwd;
use File::Basename 'dirname';
use Test::More;
use Test::Mojo;

my ($t, $csrftoken);

if (-f '/tmp/ebt2-storable') { unlink '/tmp/ebt2-storable' or die "unlink: '/tmp/ebt2-storable': $!"; }
$ENV{'BASE_DIR'} = File::Spec->catfile (getcwd, (dirname __FILE__), '..');

$t = Test::Mojo->new ('EBTST');

## wrong password
$t->get_ok ('/')->status_is (200)->element_exists ('#mainbody #repl form[id="login"]');
$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->form->input->[0]->{'value'};

$t->post_form_ok ('/login' => {
    user => 'foouser',
    pass => 'invalid pass',
    csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/index/);

## correct password
$t->get_ok ('/');
$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->form->input->[0]->{'value'};

$t->post_form_ok ('/login' => {
    user => 'foouser',
    pass => 'foopass',
    csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/);

## upload notes CSV
$t->get_ok ('/configure')->status_is (200)->element_exists ('#mainbody #repl #upload table tr td input[name=notes_csv_file]');
$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->[1]->form->input->[0]->{'value'};

$t->post_form_ok ('/upload', {
    notes_csv_file => { file => 't/notes1.csv' },
    csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/);

## correct data
$t->get_ok ('/information')->status_is (200)->content_like (qr/\bSignatures:.*\bDuisenberg 0.*\bTrichet 2.*\bDraghi 0\b/s);
$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->[0]->form->input->{'value'};

## BBCode/HTML generation
$t->post_form_ok ('/gen_output', {
    information => 1,
    value       => 1,
    csrftoken   => $csrftoken,
})->status_is (200)->content_like (qr{\[/b] notes/day\n\n\n\[b]Number of notes by value});

$t->get_ok ('/information.txt')->status_is (200)->content_type_is ('text/plain')->content_like (qr/Signatures:.*\bDuisenberg 0.*\bTrichet 2.*\bDraghi 0\b/s);
$t->get_ok ('/value.txt')->status_is (200)->content_like (qr/\b20\b.*\b1\b.*\b50\.00 %.*\b20\b/s);

## upload hits CSV
$t->post_form_ok ('/upload', {
    hits_csv_file => { file => 't/hits1.csv' },
    csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/);

## hit_analysis isn't broken with less than 10 hits
$t->get_ok ('/hit_analysis')->status_is (200)->content_like (qr{<td class="small_cell">Lxxxx2379xxx</td>});

## upload notes and hits CSV
$t->get_ok ('/information');
$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->[0]->form->input->{'value'};

$t->post_form_ok ('/upload', {
    notes_csv_file => { file => 't/notes3.csv' },
    hits_csv_file => { file => 't/hits3.csv' },
    csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/);

## moderated hits don't appear in hit_list
$t->get_ok ('/hit_list')->status_is (200)->content_unlike (qr/Exxxx0534xxx/);

## but their count appears in hit_summary
$t->get_ok ('/hit_summary')->status_is (200)->content_like (qr/plus\s+1\s+moderated/);

## logging out
$t->get_ok ('/logout')->status_is (302)->header_like (Location => qr/index/);

## logout with an empty database
$t->get_ok ('/');
$csrftoken = Mojo::DOM->new ($t->tx->res->content->asset->slurp)->html->body->div->form->input->[0]->{'value'};

$t->post_form_ok ('/login' => {
    user => 'emptyuser',
    pass => 'emptypass',
    csrftoken => $csrftoken,
})->status_is (302)->header_like (Location => qr/information/);
$t->get_ok ('/information')->status_is (302)->header_like (Location => qr/configure/);
$t->get_ok ('/logout')->status_is (302)->header_like (Location => qr/index/);

done_testing 58;
