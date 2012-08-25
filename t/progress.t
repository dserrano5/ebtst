#!perl

package Sess;

sub new { bless {}, shift }

## $self->data ('param');
## $self->data (param => 42);
sub data {
    my ($self, @params) = @_;
    my ($key, $val) = @params;

    return $self->{$key} = $val if defined $val;
    return $self->{$key};
}

sub flush {}

sub clear {
    my ($self, $key) = @_;
    delete $self->{$key};
}

1;


package main;

use warnings;
use strict;
use Test::More;

use_ok 'EBTST::Main::Progress';
my $sess = Sess->new;
{
    my $obj = new_ok 'EBTST::Main::Progress', [ sess => $sess, tot => 2000 ];
    is $sess->data ('progress'), '0/2000', 'correctly initialized';

    is $obj->set (0), $obj, 'set to 0';
    is $sess->data ('progress'), '0/2000', '0 has been set';

    is $obj->set (500), $obj, 'set to 500';
    is $sess->data ('progress'), '500/2000', '500 has been set';

    is $obj->base (1000), $obj, 'change base';
    is $sess->data ('progress'), '1000/2000', 'value is updated after changing base';

    is $obj->set (200), $obj, 'set to 1000+200';
    is $sess->data ('progress'), '1200/2000', '1000+200 has been set';

    is $obj->set (1200), $obj, 'set to 1000+1200';
    is $sess->data ('progress'), '2200/2200', 'tot changes when setting a higher value';
}
is $sess->data ('progress'), '2200/2200', 'session still alive when object is destroyed';

done_testing 14;
