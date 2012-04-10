#!/usr/bin/perl

use warnings;
use strict;
use Test::More;
use Test::Mojo;

if (-f '/tmp/ebt2-storable') { unlink '/tmp/ebt2-storable' or die "unlink: '/tmp/ebt2-storable': $!"; }

my $t = Test::Mojo->new ('EBTST');
$t->get_ok ('/')->status_is (302)->header_like (Location => qr/information/);
$t->get_ok ('/information')->status_is (302)->header_like (Location => qr/configure/);
$t->get_ok ('/configure')->status_is (200)->element_exists ('#mainbody #repl #upload table tr td input[name=notes_csv_file]');
$t->post_form_ok ('/upload', { notes_csv_file => { file => 't/notes1.csv' } })->status_is (302)->header_like (Location => qr/information/);
ok -f '/tmp/ebt2-storable', 'Database created';
$t->get_ok ('/information')->status_is (200)->content_like (qr/Signatures.*Trichet 2\b/s);
$t->get_ok ('/information.txt')->status_is (200)->content_type_is ('text/plain')->content_like (qr/Signatures.*Trichet 2\b/s);
$t->get_ok ('/value.txt')->status_is (200)->content_like (qr/\b20\b.*\b1\b.*\b50\.00 %.*\b20\b/s);

$t->post_form_ok ('/bbcode', {
    information => 1,
    value       => 1,
})->status_is (200)->content_like (qr{\[/b] notes/day\n\n\n\[b]Number of notes by value});

done_testing 26;
