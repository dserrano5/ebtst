package EBT2::NoteValidator;

use warnings;
use strict;
use List::Util qw/sum/;
use List::MoreUtils qw/uniq/;
use MIME::Base64;

sub note_serial_cksum {
    my ($s) = map uc, @_;

    return 0 if !defined $s or $s !~ /^[EFGHLMNPSTUVXYZ]\d{11}$/;
    return 0 if $s =~ /0$/;

    $s =~ s/^(.)/ (ord $1) - 64 /e;
    $s = sum split //, $s while 1 != length $s;

    return 8 == $s;
}

sub validate_note {
    my ($hr) = @_;
    my @errors;
    my $v = $hr->{'value'};
    my $pc = substr $hr->{'short_code'}, 0, 1;
    my $cc = substr $hr->{'serial'}, 0, 1;
    my $plate = substr $hr->{'short_code'}, 0, 4;
    my $position = substr $hr->{'short_code'}, 4, 2;

    push @errors, "Bad value '$v'" unless grep { $_ eq $v } @{ EBT2->values };
    push @errors, "Bad year '$hr->{'year'}'" if '2002' ne $hr->{'year'};
    if ($hr->{'serial'} =~ /^[EFGHLMNPSTUVXYZ]\d{11}$/) {
        push @errors, "Bad checksum for serial number '$hr->{'serial'}'" unless note_serial_cksum $hr->{'serial'};
    } else {
        push @errors, "Bad serial number '$hr->{'serial'}'";
    }

    ## date_entered has already been validated in load_notes

    #push @errors, "Bad city '$hr->{'city'}'" unless length $hr->{'city'};
    #push @errors, "Bad country '$hr->{'country'}'" unless length $hr->{'country'};
    #push @errors, "Bad zip '$hr->{'zip'}'" unless length $hr->{'zip'};  ## irish notes may not have a zip code

    if ($hr->{'short_code'} !~ /[DEFGHJKLMNPRTU]\d{3}[A-J][0-6]/) {
        push @errors, "Bad short code '$hr->{'short_code'}'";
    } else {
        if (5 == $v or 10 == $v) {
            push @errors, "Bad short code position '$position'" if $position !~ /^[A-J][0-6]$/;
        } elsif (20 == $v) {
            push @errors, "Bad short code position '$position'" if $position !~ /^[A-I][0-6]$/;
        } else {
            push @errors, "Bad short code position '$position'" if $position !~ /^[A-H][0-5]$/;
        }
    }

    if (!grep { $_ eq $plate } @{ $EBT2::all_plates{$cc}{$v} }) {
        push @errors, "Plate '$plate' doesn't exist for $v/$cc";
    }

    push @errors, "Bad note id '$hr->{'id'}'" if $hr->{'id'} !~ /^\d+$/;
    push @errors, "Bad number of times entered '$hr->{'times_entered'}'" if $hr->{'times_entered'} !~ /^\d+$/;
    push @errors, "Bad status of moderated hit '$hr->{'moderated_hit'}'" if $hr->{'moderated_hit'} !~ /^[01]$/;
    push @errors, "Bad latitude '$hr->{'lat'}'"   if length $hr->{'lat'}  and $hr->{'lat'}  !~ /^ -? \d{1,2} (?: \. \d+ )? $/x;
    push @errors, "Bad longitude '$hr->{'long'}'" if length $hr->{'long'} and $hr->{'long'} !~ /^ -? \d{1,3} (?: \. \d+ )? $/x;

    return encode_base64 +(join ';', @errors), '';
}

1;
