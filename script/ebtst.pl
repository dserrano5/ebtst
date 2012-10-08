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

print 'Enter encryption key: ';
system 'stty -echo'; my $enc_key = <>; system 'stty echo'; print "\n";
END { system 'stty echo'; }
chomp $enc_key;

$ENV{'EBTST_ENC_KEY'} = $enc_key;
$ENV{'MOJO_APP'} ||= 'EBTST';
$ENV{'MOJO_MAX_MESSAGE_SIZE'} = 260*1024*1024;
$ENV{'MOJO_LOG_LEVEL'} = 'debug';
Mojolicious::Commands->start (@ARGV);
#Mojolicious::Commands->start ('daemon', '--listen' => 'http://localhost:8080');
