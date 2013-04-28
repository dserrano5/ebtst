#!/usr/bin/perl

use warnings;
use strict;
use Test::More;
use MIME::Base64;
use Storable qw/thaw/;
use EBT2;
use EBT2::Util qw/set_xor_key _xor serial_remove_meaningless_figures2/;
use EBT2::Data;
use EBT2::Constants ':all';

set_xor_key 'test';

plan tests => 86;

my @notes;

my $obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
ok $obj->{'db'};
ok !$obj->has_notes, 'Object reports having no notes';

## load_notes, load_db, check
$obj->load_notes (undef, 't/notes1.csv');
ok $obj->has_notes, 'Object reports having some notes';
ok defined $obj->{'notes'}, 'There are notes after loading notes CSV';
@notes = map { _xor $_ } @{ $obj->{'notes'} };
is scalar @notes, 2, 'Correct number of notes';
is +(split ';', $notes[1], NCOLS)[HIT], '', 'No hits at all after initial loading of notes CSV';
$obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$obj->load_db;
ok defined $obj->{'notes'}, 'There are notes after loading db';
is scalar @notes, 2, 'Correct number of notes';

## load_hits, check
$obj->load_hits (undef, 't/hits1.csv');
@notes = map { _xor $_ } @{ $obj->{'notes'} };
is +(split ';', $notes[0], NCOLS)[HIT], '', 'No spurious hits after loading hits CSV';
is ref (thaw decode_base64 +(split ';', $notes[1], NCOLS)[HIT]), 'HASH', 'There is a hit after loading hits CSV';
$obj->load_db;
@notes = map { _xor $_ } @{ $obj->{'notes'} };
is +(split ';', $notes[0], NCOLS)[HIT], '', 'No spurious hits after loading db';
is ref (thaw decode_base64 +(split ';', $notes[1], NCOLS)[HIT]), 'HASH', 'There is a hit after loading db';

## load new notes, check hits are still there
$obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$obj->load_notes (undef, 't/notes1.csv');
$obj->load_hits (undef, 't/hits1.csv');
ok defined $obj->{'notes'}, 'There are notes after loading CSV';
@notes = map { _xor $_ } @{ $obj->{'notes'} };
is scalar @notes, 2, 'Correct number of notes';
is ref (thaw decode_base64 +(split ';', $notes[1], NCOLS)[HIT]), 'HASH', 'There is a hit after loading hits CSV';
$obj->load_notes (undef, 't/notes1.csv');
ok defined $obj->{'notes'}, 'There are notes after loading CSV';
@notes = map { _xor $_ } @{ $obj->{'notes'} };
is scalar @notes, 2, 'Correct number of notes';
is ref (thaw decode_base64 +(split ';', $notes[1], NCOLS)[HIT]), 'HASH', 'Hits are still there after loading new notes CSV';

## use another CSV for the following tests: note getter
$obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$obj->load_notes (undef, 't/notes2.csv');
ok defined $obj->{'notes'}, 'There are notes after loading CSV';
@notes = map { _xor $_ } @{ $obj->{'notes'} };
is scalar @notes, 7, 'Correct number of notes';

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


## use another CSV for the following tests: signatures in shared plates
$obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$obj->load_notes (undef, 't/notes-sigs.csv');
my @sigs = qw/JCT JCT MD MD WD WD JCT JCT WD WD JCT JCT WD WD JCT JCT/;
$c = 0;
while (my $notes = $obj->note_getter) {
    is $notes->[0][SIGNATURE], $sigs[$c], "Correct signature in shared plate, note " . ($c+1);
    $c++;
}

while (my $notes = $obj->note_getter (interval => 'all')) {
    is $notes->[-4][COUNTRY], 'ci',   'Ivory Coast is recognized';
    is $notes->[-3][COUNTRY], 'rskm', 'Kosovo is recognized';
    is $notes->[-2][COUNTRY], 'ba',   'Bosnia-Herzegovina is recognized';
    is $notes->[-1][COUNTRY], 'rsme', 'Serbia and Montenegro is recognized';
}

## europa notes
$obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$obj->load_notes (undef, 't/notes-europa.csv');
@notes = map { _xor $_ } @{ $obj->{'notes'} };
is scalar @notes, 7, 'Correct number of notes';


is +(serial_remove_meaningless_figures2 '2002', 20,    'E001A1', 'H00000'), 'H**000', 'Remove meaningless figures in E/H';
is +(serial_remove_meaningless_figures2 '2002', 5,     'E001A1', 'H00000'), 'H00000', 'Remove meaningless figures in E/H 5';
is +(serial_remove_meaningless_figures2 '2002', undef, 'F001A1', 'N00000'), 'N**000', 'Remove meaningless figures in F/N';
is +(serial_remove_meaningless_figures2 '2002', 5,     'F001A1', 'P00000'), 'P00**0', 'Remove meaningless figures in F/P 5';
is +(serial_remove_meaningless_figures2 '2002', 500,   'F001A1', 'P00000'), 'P**000', 'Remove meaningless figures in F/P 500';
is +(serial_remove_meaningless_figures2 '2002', undef, 'G001A1', 'H00000'), 'H00000', 'Remove meaningless figures in G/H';
is +(serial_remove_meaningless_figures2 '2002', undef, 'G001A1', 'N00000'), 'N00000', 'Remove meaningless figures in G/N';
is +(serial_remove_meaningless_figures2 '2002', undef, 'K001A1', 'T00000'), 'T00000', 'Remove meaningless figures in K/T';
is +(serial_remove_meaningless_figures2 '2002', undef, 'L001A1', 'U00000'), 'U**000', 'Remove meaningless figures in L/U';
is +(serial_remove_meaningless_figures2 '2002', undef, 'T001A1', 'Z00000'), 'Z0**00', 'Remove meaningless figures in M/V';
is +(serial_remove_meaningless_figures2 '2002', undef, 'U001A1', 'M00000'), 'M00000', 'Remove meaningless figures in U/M';
is +(serial_remove_meaningless_figures2 '2013', undef, 'U001A1', 'UB0000'), 'U**000', 'Remove meaningless figures in Europa U/U';
is +(serial_remove_meaningless_figures2 '2013', undef, 'V001A1', 'VB0000'), 'VB0000', 'Remove meaningless figures in Europa V/V';


## use another CSV for the following tests: incomplete hits file
$obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
note 'these 4 warnings are ok since the hits CSV file is incomplete';
$obj->load_notes (undef, 't/notes10.csv');
eval { $obj->load_hits (undef, 't/hits10.csv') };
like $@, qr/Unrecognized hits file/, 'bad hits file';


unlink '/tmp/ebt2-storable' or warn "unlink: '/tmp/ebt2-storable': $!";
