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
$obj->load_notes (undef, 't/notes1.csv');
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
$obj->load_notes (undef, 't/notes1.csv');
$obj->load_hits ('t/hits1.csv');
ok defined $obj->{'notes'}, 'There are notes after loading CSV';
is scalar @{ $obj->{'notes'} }, 2, 'Correct number of notes';
is ref (thaw decode_base64 +(split ';', $obj->{'notes'}[1], NCOLS)[HIT]), 'HASH', 'There is a hit after loading hits CSV';
$obj->load_notes (undef, 't/notes1.csv');
ok defined $obj->{'notes'}, 'There are notes after loading CSV';
is scalar @{ $obj->{'notes'} }, 2, 'Correct number of notes';
is +(split ';', $obj->{'notes'}[1], NCOLS)[HIT], '', 'No hits after loading new notes CSV';

## use another CSV for the following tests
$obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$obj->load_notes (undef, 't/notes2.csv');
ok defined $obj->{'notes'}, 'There are notes after loading CSV';
is scalar @{ $obj->{'notes'} }, 7, 'Correct number of notes';

my $c;

$c = 0; while (my $notes = $obj->note_getter) {
    $c++;
    is scalar @$notes, 1, 'One note in chunk';
}
is $c, 7, 'One by one: did 7 iterations';

$c = 0; while (my $notes = $obj->note_getter (interval => '3n')) {
    $c++;
    ok @$notes >= 1 && @$notes <= 3, 'From 1 to 3 notes in chunk';
}
is $c, 3, 'Three by three: did 3 iterations';

$c = 0; while (my $notes = $obj->note_getter (interval => '1d')) { $c++; }
is $c, 366, 'Daily: did 366 iterations';

$c = 0; while (my $notes = $obj->note_getter (interval => '1w')) { $c++; }
is $c, 53, 'Weekly: did 53 iterations';

$c = 0; while (my $notes = $obj->note_getter (interval => '1m')) { $c++; }
is $c, 13, 'Monthly: did 13 iterations';

$c = 0; while (my $notes = $obj->note_getter (interval => '1y')) { $c++; }
is $c, 2, 'Yearly: did 2 iterations';

$c = 0;
while (my $notes = $obj->note_getter (interval => 'all')) {
    $c++;
    is scalar @$notes, 7, '7 notes in chunk';
    is $notes->[ 0][DATE_ENTERED], '2010-02-11 11:25:32', 'Correct date of first note';
    is $notes->[-1][DATE_ENTERED], '2011-02-11 09:08:07', 'Correct date of last note';
}
is $c, 1, 'All: did 1 iteration';

$c = 0;
while (my $notes = $obj->note_getter (interval => 'all')) {
    $c++;
    is scalar @$notes, 7, '7 notes in chunk';
    is $notes->[ 0][DATE_ENTERED], '2010-02-11 11:25:32', 'Correct date of first note';
    is $notes->[-1][DATE_ENTERED], '2011-02-11 09:08:07', 'Correct date of last note';
}
is $c, 1, 'All: did 1 iteration';

## use another CSV for the following tests
$obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$obj->load_notes (undef, 't/notes-sigs.csv');
my @sigs = qw/JCT JCT MD MD WD WD JCT JCT WD WD JCT JCT WD WD JCT JCT/;
$c = 0;
while (my $notes = $obj->note_getter) {
    is $notes->[0][SIGNATURE], $sigs[$c], "Correct signature in shared plate, note " . ($c+1);
    $c++;
}

done_testing 65;
unlink '/tmp/ebt2-storable' or warn "unlink: '/tmp/ebt2-storable': $!";
