#!/usr/bin/perl

use warnings;
use strict;
use Test::More;
use MIME::Base64;
use Storable qw/thaw/;
use EBT2;
use EBT2::Data;
use EBT2::Constants ':all';

my $obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
ok $obj->{'db'};
ok !$obj->has_notes, 'Object reports having no notes';

## load_notes, load_db, check
$obj->load_notes ('t/notes1.csv');
ok $obj->has_notes, 'Object reports having some notes';
ok defined $obj->{'notes'}, 'There are notes after loading notes CSV';
is scalar @{ $obj->{'notes'} }, 2, 'Correct number of notes';
is +(split ';', $obj->{'notes'}[1], NCOLS)[HIT], '', 'No hits at all after initial loading of notes CSV';
$obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$obj->load_db;
ok defined $obj->{'notes'}, 'There are notes after loading db';
is scalar @{ $obj->{'notes'} }, 2, 'Correct number of notes';

## load_hits, check
$obj->load_hits ('t/hits1.csv');
is +(split ';', $obj->{'notes'}[0], NCOLS)[HIT], '', 'No spurious hits after loading hits CSV';
is ref (thaw decode_base64 +(split ';', $obj->{'notes'}[1], NCOLS)[HIT]), 'HASH', 'There is a hit after loading hits CSV';
$obj->load_db;
is +(split ';', $obj->{'notes'}[0], NCOLS)[HIT], '', 'No spurious hits after loading db';
is ref (thaw decode_base64 +(split ';', $obj->{'notes'}[1], NCOLS)[HIT]), 'HASH', 'There is a hit after loading db';

## load new notes, check hits are still there
$obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$obj->load_notes ('t/notes1.csv');
$obj->load_hits ('t/hits1.csv');
ok defined $obj->{'notes'}, 'There are notes after loading CSV';
is scalar @{ $obj->{'notes'} }, 2, 'Correct number of notes';
is ref (thaw decode_base64 +(split ';', $obj->{'notes'}[1], NCOLS)[HIT]), 'HASH', 'There is a hit after loading hits CSV';
$obj->load_notes ('t/notes1.csv');
ok defined $obj->{'notes'}, 'There are notes after loading CSV';
is scalar @{ $obj->{'notes'} }, 2, 'Correct number of notes';
is +(split ';', $obj->{'notes'}[1], NCOLS)[HIT], '', 'No hits after loading new notes CSV';

## use another CSV for the following tests
$obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$obj->load_notes ('t/notes2.csv');
ok defined $obj->{'notes'}, 'There are notes after loading CSV';
is scalar @{ $obj->{'notes'} }, 6, 'Correct number of notes';

SKIP: {
    skip 'Pay attention to note_getter with params before testing it', 14;

    my ($c, $iter);

    is ref ($iter = $obj->note_getter), 'CODE', 'Iterator returned';
    $c = 0; while (my $notes = $iter->()) { $c++; }
    is $c, 6, 'One by one: did 6 iterations';

    is ref ($iter = $obj->note_getter (interval => '3n')), 'CODE', 'Iterator returned';
    $c = 0; while (my $notes = $iter->()) { $c++; }
    is $c, 2, 'Three by three: did 2 iterations';

    is ref ($iter = $obj->note_getter (interval => '1d')), 'CODE', 'Iterator returned';
    $c = 0; while (my $notes = $iter->()) { $c++; }
    is $c, 366, 'Daily: did 366 iterations';

    is ref ($iter = $obj->note_getter (interval => '1w')), 'CODE', 'Iterator returned';
    $c = 0; while (my $notes = $iter->()) { $c++; }
    is $c, 53, 'Weekly: did 53 iterations';

    is ref ($iter = $obj->note_getter (interval => '1m')), 'CODE', 'Iterator returned';
    $c = 0; while (my $notes = $iter->()) { $c++; }
    is $c, 13, 'Monthly: did 13 iterations';

    is ref ($iter = $obj->note_getter (interval => '1y')), 'CODE', 'Iterator returned';
    $c = 0; while (my $notes = $iter->()) { $c++; }
    is $c, 2, 'Yearly: did 2 iterations';

    is ref ($iter = $obj->note_getter (interval => 'all')), 'CODE', 'Iterator returned';
    $c = 0; while (my $notes = $iter->()) { $c++; }
    is $c, 1, 'All: did 1 iteration';
};

done_testing 38;
#unlink '/tmp/ebt2-storable' or warn "unlink: '/tmp/ebt2-storable': $!";
