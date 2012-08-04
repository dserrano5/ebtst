#!/usr/bin/perl

use warnings;
use strict;
use Test::More;

use EBT2;
use EBT2::Data;
use EBT2::Stats;

my $data_obj = new_ok 'EBT2::Data', [ db => '/tmp/ebt2-storable' ];
$data_obj->load_db;
ok defined $data_obj->{'notes'}, 'There are notes after loading db';
is scalar @{ $data_obj->{'notes'} }, 7, 'Correct number of notes';

my $st = new_ok 'EBT2::Stats';

my $res;
$res = $st->activity ($data_obj);
is ref $res, 'HASH', 'activity';
is $res->{'activity'}{'first_note'}{'date'}, '2010-02-11', 'First note date';
is $res->{'activity'}{'longest_active_period_notes'}, 4, 'Longest active period, given in notes';
is $res->{'activity'}{'active_days_count'}, 2, 'Active days count';

$res = $st->count ($data_obj);
is ref $res, 'HASH', 'count';
is $res->{'count'}, 7, 'Note count';
is $res->{'total_value'}, 640, 'Total value';
is ref $res->{'signatures'}, 'HASH', 'Signatures';

$res = $st->notes_by_value ($data_obj);
is ref $res, 'HASH', 'notes_by_value';
is $res->{'notes_by_value'}{'10'}, 1, 'One 10€ note';
is $res->{'notes_by_value'}{'20'}, 4, 'Four 20€ notes';
is $res->{'notes_by_value'}{'50'}, 1, 'One 50€ note';
is $res->{'notes_by_value'}{'500'}, 1, 'One 500€ note';

$res = $st->lowest_short_codes ($data_obj);
is ref $res, 'HASH', 'fooest_short_codes';
is ref $res->{'lowest_short_codes'}, 'HASH', 'lowest_short_codes';
is $res->{'lowest_short_codes'}{'F'}{'500'}{'sort_key'}, 'F001B4P42**0', 'F/P is ok (500€)';
is $res->{'lowest_short_codes'}{'F'}{'all'}{'sort_key'}, 'F001B4P42**0', 'F/P is ok (all values)';

done_testing 21;
