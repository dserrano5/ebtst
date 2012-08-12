package EBTST::Main::Gnuplot;

use warnings;
use strict;
use DateTime;
use List::MoreUtils qw/zip/;
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
        encoding  => 'utf8',
        terminal  => 'svg fsize 9',
        #imagesize => '800, 600',
        output    => $args{'output'},
        #title     => 'Title',
        #xlabel    => 'Time',
        #ylabel    => 'Notes',
        timeaxis  => 'x',
        #bg        => 'white',
        ($args{'logscale'} ? (logscale => $args{'logscale'}) : ()),
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
            width    => 1,
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
        encoding     => 'utf8',
        terminal     => 'svg fsize 9',
        #imagesize   => '800, 600',
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
        xtics => {
            labels => \@labels,
        },
        legend => {
            position => 'rmargin top',
            width    => 1,
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
    my $boxes_limit = 500;      ## showing a lot of boxes is slow

    ## we draw a bar every X amount of time. @intervals contains the latest date for notes to be in a given bar
    ## ie the first bar represents the note at (or just before) $intervals[0]

    my $first_dt = DateTime->new (zip @{[ qw/year month day hour minute second/ ]}, @{[ split /[ :-]/, $args{'xdata'}[0]  ]})->epoch;
    my $last_dt  = DateTime->new (zip @{[ qw/year month day hour minute second/ ]}, @{[ split /[ :-]/, $args{'xdata'}[-1] ]})->epoch;
    my $interval_duration = ($last_dt - $first_dt) / $boxes_limit;
    my @intervals = map {
        DateTime->from_epoch (epoch => $first_dt + $interval_duration * $_)->strftime ('%Y-%m-%d %H:%M:%S')
    } 1 .. $boxes_limit;

    my @xdata;
    my $idx_last_point = $#{ $args{'dsets'}[0]{'points'} };
    my $xdata_done = 0;
    my @totals;
    foreach my $dset (@{ $args{'dsets'} }) {
        my @points;
        my $interval_idx = 0;

        foreach my $idx (0..$idx_last_point) {
            my $cmp = $args{'xdata'}[$idx] cmp $intervals[$interval_idx];
            next if -1 == $cmp;

            ## found a note entered at (or later than) the current interval
            ## plot it (or the one before)
            if (0 == $cmp) {        ## this happens at the last iteration (if floating point precision doesn't meddle)
                push @points, $dset->{'points'}[$idx];
                $xdata_done or push @xdata, $args{'xdata'}[$idx];
            } elsif (1 == $cmp) {
                push @points, $dset->{'points'}[$idx-1];
                $xdata_done or push @xdata, $args{'xdata'}[$idx-1];
            }

            ## now set the next interval
            ## if there's a lot of time between two notes, we may have to increase $interval_idx more than once
            do {
                $interval_idx++;
            } while $interval_idx < $#intervals and -1 != ($args{'xdata'}[$idx] cmp $intervals[$interval_idx]);
        }

        $dset->{'points'} = \@points;
        if ($args{'percent'}) { map { $totals[$_] += $points[$_] } 0..$#points; }
        $xdata_done = 1;
    }

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
        xdata    => \@xdata,
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
        encoding     => 'utf8',
        terminal     => 'svg fsize 9',
        #imagesize   => '800, 600',
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
            width    => 1,
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
