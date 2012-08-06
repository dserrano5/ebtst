package EBTST::Main::Gnuplot;

use warnings;
use strict;
use Chart::Gnuplot;

sub line_chart {
    my (%args) = @_;

    my %gp_dset_args = (
        xdata    => $args{'xdata'},
        style    => 'lines',
        linetype => 'solid',
        timefmt  => '%Y-%m-%d %H:%M:%S',
    );

    my @gp_dsets;
    foreach my $dset (@{ $args{'dsets'} }) {
        push @gp_dsets, Chart::Gnuplot::DataSet->new (
            %gp_dset_args,
            ydata => $dset->{'points'},
            title => $dset->{'title'},
            color => $dset->{'color'},
        );
    }

    my $gp = Chart::Gnuplot->new (
        #imagesize => '8, 6',   ## default: '10, 7' for some reason
        output    => $args{'output'},
        #title     => 'Title',
        #xlabel    => 'Time',
        #ylabel    => 'Notes',
        timeaxis  => 'x',
        #bg        => 'white',
        #logscale  => 'y',
        #yrange    => [ 0, '*' ],
        grid => {
            type  => 'dot',
            width => 1,
            color => 'grey',
        },
        xtics => {
            labelfmt => '%Y-%m-%d',
            rotate   => 90,
            offset   => '0, -5',
        },
        legend => {
            position => 'bmargin left',
            align    => 'right',
            order    => 'horizontal',
            border   => { width => 1 },
        },
    );
    $gp->plot2d (@gp_dsets);
}

## the datasets must be in order, nearest to the zero line first
sub bar_chart {
    my (%args) = @_;

    my %gp_dset_args = (
        xdata    => [ 0..$#{ $args{'labels'} } ],
        style    => 'boxes',
        linetype => 'solid',
    );

    my @gp_dsets;
    my @acum;  ## we need to sum values, to make the illusion to create stacked boxes (actually they are tall ones, placed behind the smaller ones)
    foreach my $dset (@{ $args{'dsets'} }) {
        $acum[$_] += $dset->{'points'}[$_]//0 for 0..$#{ $dset->{'points'} };
        unshift @gp_dsets, Chart::Gnuplot::DataSet->new (
            %gp_dset_args,
            ydata    => [ @acum ],
            title    => $dset->{'title'},
            color    => $dset->{'color'},
            using    => 2,
            linetype => 'solid',
        );
    }
    my @labels;
    for my $idx (0..$#{ $args{'labels'} }) {
        push @labels, sprintf '"%s" %d', $args{'labels'}[$idx], $idx;
    }

    my $gp = Chart::Gnuplot->new (
        output       => $args{'output'},
        boxwidth     => '0.75 absolute',
        'style fill' => ($args{'bar_border'} ? 'solid 1 border lt -1' : 'solid 1'),
        yrange       => [ 0, '*' ],
        grid => {
            type   => 'dot',
            width  => 1,
            color  => 'grey',
            xlines => 'off',
        },
        legend => {
            position => 'rmargin top',
            align    => 'right',
            order    => 'vertical invert',  ## 'invert' doesn't seem to work with 'horizontal', and we need it since we plot the datasets in reverse order
            border => {
                width => 1,
            },
        },
    );
    $gp->plot2d (@gp_dsets);
}

## the datasets must be in order, nearest to the zero line first
sub bartime_chart {
    my (%args) = @_;
    my $xdata;
    my $boxes_limit = 500;      ## showing a lot of boxes is slow

    my @xdata;
    my $idx_last_point = $#{ $args{'dsets'}[0]{'points'} };

    my $nata = int @{ $args{'xdata'} } / $boxes_limit; $nata ||= 1;

    my $xdata_done = 0;
    my @totals;
    foreach my $dset (@{ $args{'dsets'} }) {
        my @points;
        foreach my $idx (0..$idx_last_point) {
            next if 0 != $idx % $nata;
            push @points, $dset->{'points'}[$idx];
            $xdata_done or push @xdata, $args{'xdata'}[$idx];
        }
        $dset->{'points'} = \@points;
        if ($args{'percent'}) { map { $totals[$_] += $points[$_] } 0..$#points; }
        $xdata_done = 1;
    }
    $xdata = \@xdata;

    ## transform into percent
    if ($args{'percent'}) {
        foreach my $dset (@{ $args{'dsets'} }) {
            foreach my $idx (0..$#{ $dset->{'points'} }) {
                next unless $totals[$idx];
                $dset->{'points'}[$idx] = 100 * $dset->{'points'}[$idx] / $totals[$idx];
            }
        }
    }

    my %gp_dset_args = (
        xdata    => $xdata,
        style    => 'boxes',
        linetype => 'solid',
        timefmt  => '%Y-%m-%d %H:%M:%S',
    );

    my @gp_dsets;
    my @acum;  ## we need to sum values, to make the illusion to create stacked boxes (actually they are tall ones, placed behind the smaller ones)
    foreach my $dset (@{ $args{'dsets'} }) {
        $acum[$_] += $dset->{'points'}[$_]//0 for 0..$#{ $dset->{'points'} };
        unshift @gp_dsets, Chart::Gnuplot::DataSet->new (
            %gp_dset_args,
            ydata    => [ @acum ],
            title    => $dset->{'title'},
            color    => $dset->{'color'},
            using    => '1:3',
            linetype => 'solid',
        );
    }
    my $gp = Chart::Gnuplot->new (
        output       => $args{'output'},
        timeaxis  => 'x',
        #boxwidth     => '0.75 absolute',
        'style fill' => ($args{'bar_border'} ? 'solid 1 border lt -1' : 'solid 1'),
        #yrange       => [ 0, '*' ],
        grid => {
            type   => 'dot',
            width  => 1,
            color  => 'grey',
            xlines => 'off',
        },
        xtics => {
            labelfmt => '%Y-%m-%d',
            rotate   => 90,
            offset   => '0, -5',
        },
        legend => {
            position => 'rmargin top',
            align    => 'right',
            order    => 'vertical invert',  ## 'invert' doesn't seem to work with 'horizontal', and we need it since we plot the datasets in reverse order
            border => {
                width => 1,
            },
        },
    );
    $gp->plot2d (@gp_dsets);
}

1;
