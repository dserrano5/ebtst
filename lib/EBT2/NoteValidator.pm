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

    return "bad value" unless grep { $_ eq $hr->{'value'} } @{ $EBT2::config{'values'} };
    return "bad year" if '2002' ne $hr->{'year'};
    return "bad serial" unless note_serial_cksum $hr->{'serial'};
    return "bad date" if
        $hr->{'date_entered'} !~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/ and
        $hr->{'date_entered'} !~ m{^\d{2}/\d{2}/\d{2} \d{2}:\d{2}$};
    return "bad city" unless length $hr->{'city'};
    return "bad country" unless length $hr->{'country'};
    #return "bad zip" unless length $hr->{'zip'};  ## irish notes haven't a zip code
    return "bad short code" if $hr->{'short_code'} !~ /^([DEFGHJKLMNPRTU]\d{3}[A-J][0-6])$/;
    return "bad id" if $hr->{'id'} !~ /^\d+$/;
    return "bad latitude"  if length $hr->{'lat'}  and $hr->{'lat'}  !~ /^ -? \d+ (?: \. \d+ )? $/x;
    return "bad longitude" if length $hr->{'long'} and $hr->{'long'} !~ /^ -? \d+ (?: \. \d+ )? $/x;

    return;
}

1;
