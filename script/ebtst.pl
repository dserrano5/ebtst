#!/usr/bin/env perl

use 5.010;
use strict;
use warnings;
use File::Basename 'dirname';
use File::Spec;
use lib join '/', File::Spec->splitdir (dirname (__FILE__)), 'lib';
use lib join '/', File::Spec->splitdir (dirname (__FILE__)), '..', 'lib';

# Check if Mojo is installed
eval 'use Mojolicious::Commands';
die <<"EOF" if $@;
It looks like you don't have the Mojolicious Framework installed.
Please visit http://mojolicio.us for detailed installation instructions.

EOF

$ENV{'MOJO_APP'} ||= 'EBTST';
Mojolicious::Commands->start (@ARGV);
#Mojolicious::Commands->start ('daemon', '--listen' => 'http://localhost:8080');
