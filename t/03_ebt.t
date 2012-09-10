#!/usr/bin/perl

use warnings;
use strict;
use Test::More;
use MIME::Base64;
use Storable qw/thaw/;
use EBT2;
use EBT2::Constants ':all';

my $obj = new_ok 'EBT2', [ db => '/tmp/ebt2-storable' ];
ok $obj->{'data'};
ok $obj->{'stats'};
ok !$obj->has_notes;

$obj->load_notes ('t/notes1.csv');
ok $obj->has_notes;
ok defined $obj->{'data'}{'notes'}, 'There are some notes after loading CSV';
is scalar @{ $obj->{'data'}{'notes'} }, 2, 'Correct number of notes';
$obj->load_hits ('t/hits1.csv');
is ref (thaw decode_base64 +(split ';', $obj->{'data'}{'notes'}[1], NCOLS)[HIT]), 'HASH', 'There is a hit after loading hits CSV';
is +(split ';', $obj->{'data'}{'notes'}[0], NCOLS)[HIT],, '', 'No spurious hits after loading hits CSV';

$obj->load_notes ('t/notes1.csv');
is +(split ';', $obj->{'data'}{'notes'}[1], NCOLS)[HIT], '', 'No hits after loading new notes CSV';
is ref $obj->{'notes'}[0]{'hit'}, '', 'No spurious hits after loading new notes CSV';

$obj->load_db;
ok defined $obj->{'data'}{'notes'}, 'There are notes after loading db';
is scalar @{ $obj->{'data'}{'notes'} }, 2, 'Correct number of notes';
is +(split ';', $obj->{'data'}{'notes'}[1], NCOLS)[HIT], '', 'No spurious hits after loading db';
is +(split ';', $obj->{'data'}{'notes'}[0], NCOLS)[HIT], '', 'No spurious hits after loading db';

my $gotten;
$gotten = $obj->get_activity;
is ref $gotten, 'HASH', 'activity';
is $gotten->{'first_note'}{'date'}, '2010-01-26', 'First note date';
is $gotten->{'longest_active_period_notes'}, 1, 'Longest active period, given in notes';
is $gotten->{'active_days_count'}, 2, 'Active days count';

$gotten = $obj->get_count;
is $gotten, 2, 'Notes count';
$gotten = $obj->get_total_value;
is $gotten, 30, 'Total value';
$gotten = $obj->get_signatures;
is ref $gotten, 'HASH', 'Some signature';   ## TODO: all signatures, not only found ones

$gotten = $obj->get_days_elapsed;
like $gotten, qr/^\d+/, 'Days elapsed';

$gotten = $obj->get_notes_by_value;
is $gotten->{'10'}, 1, 'One 10€ note';
is $gotten->{'20'}, 1, 'One 20€ note';

done_testing 25;
unlink '/tmp/ebt2-storable' or warn "unlink: '/tmp/ebt2-storable': $!";
