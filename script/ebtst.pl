#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;
use Cwd;
use File::Basename 'dirname';
use File::Spec;

BEGIN {
    if ('/' eq substr __FILE__, 0, 1) {
        $ENV{'BASE_DIR'} = File::Spec->catfile (        (dirname __FILE__), '..');
    } else {
        $ENV{'BASE_DIR'} = File::Spec->catfile (getcwd, (dirname __FILE__), '..');
    }
}
use lib File::Spec->catfile ($ENV{'BASE_DIR'}, 'lib');

# Check if Mojo is installed
eval 'use Mojolicious::Commands';
die <<"EOF" if $@;
It looks like you don't have the Mojolicious Framework installed.
Please visit http://mojolicio.us for detailed installation instructions.

EOF

my $keyfile = File::Spec->catfile ($ENV{'HOME'}, '.ebt', 'ebtst-key');
open my $fd, '<', $keyfile or die "open: '$keyfile': $!\n";
$::enc_key = <$fd>; chomp $::enc_key;
close $fd;

$ENV{'MOJO_MAX_MESSAGE_SIZE'} = 260*1024*1024;
$ENV{'MOJO_LOG_LEVEL'} = 'debug';
Mojolicious::Commands->start_app (EBTST => @ARGV);
