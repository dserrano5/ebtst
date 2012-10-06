#!/usr/bin/perl

use warnings;
use strict;
use Test::More;
use File::Copy;
use EBT2;

my @dbs = sort glob 't/dbs/*';
if (@dbs) {
    plan tests => 47 * @dbs;
} else {
    plan skip_all => 'No databases';
}

foreach my $db (@dbs) {
    note $db;
    copy $db, '/tmp/ebt2-storable' or die "copy: $!";

    my $gotten;

    my $obj = new_ok 'EBT2', [ db => '/tmp/ebt2-storable' ];
    $obj->load_db;

    ok defined $obj->has_notes, 'has_notes';

    my $count = $obj->get_count;
    like $count, qr/^\d+$/, 'get_count';

    my $ac = $obj->get_activity;
    like $ac->{'first_note'}{'date'}, qr/^20\d\d-\d\d-\d\d$/, 'get_activity: first_note';
    like $ac->{'active_days_count'}, qr/^\d+$/, 'get_activity: active_days_count';

    like defined $obj->get_total_value, qr/^\d+$/, 'get_total_value';
    is ref $obj->get_signatures, 'HASH', 'get_signatures';
    like $obj->get_days_elapsed, qr/^\d+/, 'get_days_elapsed';
    is ref $obj->get_notes_dates, 'ARRAY', 'get_notes_dates';

    $gotten = $obj->get_elem_notes_by_president;
    my @enbp = split /,/, $gotten;
    is @enbp, $count, 'get_elem_notes_by_president: number of elements';
    my %sigs; foreach my $sig (@enbp) { $sigs{$sig} = undef; } delete @sigs{qw/WD JCT MD _UNK/};
    is keys %sigs, 0, 'get_elem_notes_by_president: only known sigs';

    is ref $obj->get_notes_by_value, 'HASH', 'get_notes_by_value';
    is ref $obj->get_first_by_value, 'HASH', 'get_first_by_value';
    is ref $obj->get_notes_by_cc, 'HASH', 'get_notes_by_cc';
    is ref $obj->get_first_by_cc, 'HASH', 'get_first_by_cc';
    is ref $obj->get_notes_by_pc, 'HASH', 'get_notes_by_pc';
    is ref $obj->get_first_by_pc, 'HASH', 'get_first_by_pc';
    is ref $obj->get_notes_by_country, 'HASH', 'get_notes_by_country';
    is ref $obj->get_notes_by_city, 'HASH', 'get_notes_by_city';

    $gotten = [ split /#/, $obj->get_elem_notes_by_city ];
    is @$gotten, $count, 'get_elem_notes_by_city';

    is ref $obj->get_alphabets, 'HASH', 'get_alphabets';
    is ref $obj->get_travel_stats, 'HASH', 'get_travel_stats';
    is ref $obj->get_huge_table, 'HASH', 'get_huge_table';
    is ref $obj->get_lowest_short_codes, 'HASH', 'get_lowest_short_codes';
    is ref $obj->get_highest_short_codes, 'HASH', 'get_highest_short_codes';
    is ref $obj->get_nice_serials, 'ARRAY', 'get_nice_serials';
    is ref $obj->get_numbers_in_a_row, 'HASH', 'get_numbers_in_a_row';
    is ref $obj->get_different_digits, 'HASH', 'get_different_digits';
    is ref $obj->get_coords_bingo, 'HASH', 'get_coords_bingo';
    is ref $obj->get_notes_per_year, 'HASH', 'get_notes_per_year';
    is ref $obj->get_notes_per_month, 'HASH', 'get_notes_per_month';
    is ref $obj->get_top10days, 'HASH', 'get_top10days';
    is ref $obj->get_top10months, 'HASH', 'get_top10months';
    is ref $obj->get_time_analysis, 'HASH', 'get_time_analysis';
    is ref $obj->get_notes_by_dow, 'HASH', 'get_notes_by_dow';
    is ref $obj->get_missing_combs_and_history, 'HASH', 'get_missing_combs_and_history';
    is ref $obj->get_notes_by_combination, 'HASH', 'get_notes_by_combination';
    is ref $obj->get_plate_bingo, 'HASH', 'get_plate_bingo';

    if ($obj->has_bad_notes) {
        is ref $obj->get_bad_notes, 'ARRAY', 'get_bad_notes';
    } else {
        is ref $obj->get_bad_notes, '', 'get_bad_notes';
    }

    my $hl = $obj->get_hit_list ($obj->whoami);
    is ref $hl, 'ARRAY', 'get_hit_list';

    is ref $obj->get_hits_dates, 'ARRAY', 'get_hits_dates';

    $gotten = [ split ',', $obj->get_elem_travel_days ];
    is @$gotten, (grep { !$_->{'moderated'} } @$hl), 'get_elem_travel_days';

    $gotten = [ split ',', $obj->get_elem_travel_km ];
    is @$gotten, (grep { !$_->{'moderated'} } @$hl), 'get_elem_travel_km';

    if (@$hl) {
        is ref $obj->get_hit_times ($hl), 'HASH', 'get_hit_times';
    } else {
        is ref $obj->get_hit_times ($hl), '', 'get_hit_times';
    }
    is ref $obj->get_hit_analysis ($hl), 'HASH', 'get_hit_analysis';
    is ref $obj->get_hit_summary ($obj->whoami, $ac, $count, $hl), 'HASH', 'get_hit_summary';
    is ref $obj->get_calendar, 'HASH', 'get_calendar';
}
