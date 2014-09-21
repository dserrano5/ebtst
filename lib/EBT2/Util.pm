package EBT2::Util;

use warnings;
use strict;
use Digest::SHA qw/sha512/;
use Exporter;

our @ISA = qw/Exporter/;
our @EXPORT_OK = qw/set_xor_key _xor serial_remove_meaningless_figures2/;

my $xor_key;

sub set_xor_key {
    my ($key) = @_;
    $key // die 'set_xor_key: no key specified';
    $xor_key = sha512 $key;
}

sub _xor {
    my ($data) = @_;

    return unless defined $data;
    if (ref $data) { die sprintf "_xor: received a '%s' instead of a scalar", ref $data; }

    my $xor = $xor_key // die '_xor: no key has been set';

    while (1) {
        if (length $data <= length $xor) {
            $xor = substr $xor, 0, length $data;
            return $data ^ $xor;
        } else {
            $xor .= $xor;
        }
    }
}

## this is:
## - for sorting
## - for presentation
## - used in the process of signature guessing when plates are shared
sub serial_remove_meaningless_figures2 {
    my ($series, $value, $short, $serial) = @_;

    my $pc = substr $short, 0, 1;
    my $cc = substr $serial, 0, 1;

    if ('2002' eq $series) {
        if ('M' eq $cc or 'T' eq $cc) {
            #$serial = $cc . '*' . substr $serial, 2;

        } elsif ('N' eq $cc) {
            if ('G' ne $pc) {
                $serial = $cc . '**' . substr $serial, 3;
            }

        } elsif ('H' eq $cc) {
            if ('G' ne $pc) {
                if (5 != $value) {
                    $serial = $cc . '**' . substr $serial, 3;
                }
            }

        } elsif ('U' eq $cc) {
            if ($short =~ /^L087/ and $serial =~ /^U([0-9][0-9])/ and $1 >= 85) {
                ## https://forum.eurobilltracker.com/viewtopic.php?f=20&t=50011&view=unread#p1082050
                ## the first three significant digits are 1st, 2nd and 5th (U85**0, U86**4)
                $serial = $cc . (substr $serial, 1, 2) . '**' . substr $serial, 5;
            } else {
                $serial = $cc . '**' . substr $serial, 3;
            }

        } elsif ('P' eq $cc) {
            if ('F' eq $pc) {
                if (500 == $value) {
                    $serial = $cc . '**' . substr $serial, 3;
                } else {
                    $serial = $cc . (substr $serial, 1, 2) . '**' . substr $serial, 5;
                }
            }

        } elsif ('Z' eq $cc) {
            $serial = $cc . (substr $serial, 1, 1) . '**' . substr $serial, 4;

        }
    } elsif ('europa' eq $series) {
        if ('U' eq $cc or 'S' eq $cc) {
            $serial = $cc . '**' . substr $serial, 3;
        }
        if ('N' eq $cc or 'Z' eq $cc) {
            $serial = $cc . (substr $serial, 1, 1) . '**' . substr $serial, 4;
        }
        return $serial;
    }

    return $serial;
}

1;
