package EBTST::Main::Progress;

use warnings;
use strict;

sub new {
    my ($class, %args) = @_;

    my %attrs;
    $attrs{$_} = delete $args{$_} for qw/sess base tot/;
    %args and die sprintf 'unrecognized parameters: %s', join ', ', sort keys %args;

    exists $attrs{'sess'} or die "need a 'sess' parameter";
    exists $attrs{'tot'}  or die "need a 'tot' parameter";
    $attrs{'base'} //= 0;

    $attrs{'sess'}->can ('data')  or die "parameter 'sess' can not ->data()";
    $attrs{'sess'}->can ('clear') or die "parameter 'sess' can not ->clear()";
    $attrs{'sess'}->can ('flush') or die "parameter 'sess' can not ->flush()";

    my $self = bless {
        %attrs,
    }, $class;

    return $self->set (0);
}

sub set {
    my ($self, $done) = @_;

#warn "set: done ($done)\n";
    $done += $self->{'base'};
    $self->{'tot'} = $done if $done > $self->{'tot'};

#warn sprintf "%s: set: setting session to done ($done)\n", scalar localtime;
    $self->{'sess'}->data (progress => sprintf '%d/%d', $done, $self->{'tot'});
    $self->{'sess'}->flush;
    return $self;
}

sub base {
    my ($self, $base) = @_;
    $self->{'base'} = $base;
    return $self->set (0);
}

sub base_add {
    my ($self, $base) = @_;
    $self->{'base'} += $base;
    return $self->set (0);
}

1;
