package EBT2::NoteValidator;

use warnings;
use strict;
use List::Util qw/sum/;

sub note_serial_cksum {
    my ($s) = map uc, @_;

    return 0 if !defined $s or $s !~ /^[A-Z]\d{11}$/;
    return 0 if $s =~ /0$/;

    $s =~ s/^(.)/ (ord $1) - 64 /e;
    $s = sum split //, $s while 1 != length $s;

    return 8 == $s;
}

sub validate_note {
    my ($hr) = @_;
    my @errors;

    push @errors, "Bad value '$hr->{'value'}'" unless grep { $_ eq $hr->{'value'} } @{ EBT2->values };
    push @errors, "Bad year '$hr->{'year'}'" if '2002' ne $hr->{'year'};
    push @errors, "Invalid checksum for serial number '$hr->{'serial'}'" unless note_serial_cksum $hr->{'serial'};
    push @errors, "Bad date '$hr->{'date_entered'}'" if
        $hr->{'date_entered'} !~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/ and
        $hr->{'date_entered'} !~ m{^\d{2}/\d{2}/\d{2} \d{2}:\d{2}$};
    #push @errors, "Bad city '$hr->{'city'}'" unless length $hr->{'city'};
    #push @errors, "Bad country '$hr->{'country'}'" unless length $hr->{'country'};
    #push @errors, "Bad zip '$hr->{'zip'}'" unless length $hr->{'zip'};  ## irish notes haven't a zip code
    push @errors, "Bad short code '$hr->{'short_code'}'" if $hr->{'short_code'} !~ /^([DEFGHJKLMNPRTU]\d{3}[A-J][0-6])$/;
    push @errors, "Bad id '$hr->{'id'}'" if $hr->{'id'} !~ /^\d+$/;
    push @errors, "Bad latitude '$hr->{'lat'}'"  if length $hr->{'lat'}  and $hr->{'lat'}  !~ /^ -? \d+ (?: \. \d+ )? $/x;
    push @errors, "Bad longitude '$hr->{'long'}'" if length $hr->{'long'} and $hr->{'long'} !~ /^ -? \d+ (?: \. \d+ )? $/x;

    my $k_pcv         = sprintf '%s%s%03d', (substr $hr->{'short_code'}, 0, 1), (substr $hr->{'serial'}, 0, 1), $hr->{'value'};
    my $visible_k_pcv = sprintf '%s/%s %d', (substr $hr->{'short_code'}, 0, 1), (substr $hr->{'serial'}, 0, 1), $hr->{'value'};
    push @errors, "Bad combination '$visible_k_pcv'" if !exists $EBT2::combs_pc_cc_val{$k_pcv};

    return @errors ? \@errors : ();
}

1;
