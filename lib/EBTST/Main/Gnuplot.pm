package EBTST::Main::Gnuplot;

use warnings;
use strict;
use DateTime;
use List::MoreUtils qw/zip/;
use Chart::Gnuplot;

## this function modifies the 'points' element in each dataset in @$dsets
sub _quantize {
    my ($limit, $xdata, $dsets) = @_;

    my $graph_type = (caller 1)[3];
    $graph_type =~ s/.*::(\w+)_chart$/$1/;

    ## we draw a point every X amount of time. @intervals contains the latest date for notes to be in a given point
    ## ie the first point represents the note at (or just before) $intervals[0]

    my $first_dt = DateTime->new (zip @{[ qw/year month day hour minute second/ ]}, @{[ split /[ :-]/, $xdata->[0]  ]})->epoch;
    my $last_dt  = DateTime->new (zip @{[ qw/year month day hour minute second/ ]}, @{[ split /[ :-]/, $xdata->[-1] ]})->epoch;
    my $interval_duration = ($last_dt - $first_dt) / $limit;
    my @intervals = map {
        DateTime->from_epoch (epoch => $first_dt + $interval_duration * $_)->strftime ('%Y-%m-%d %H:%M:%S')
    } 1 .. $limit;

    my @new_xdata;
    my @points;
    my @last_pushed;
    my $last_idx = 0;
    OUTER:
    foreach my $limit_date (@intervals) {
        ## if a lot of time has passed, $cur_xdata could be greater than this $limit_date
        ## (never true in the first iteration)
        my $cur_xdata = $xdata->[ $last_idx ];
        if (1 == ($cur_xdata cmp $limit_date)) {
            ## push $limit_date to @new_xdata and...
            push @new_xdata, $limit_date;
            foreach my $dset_idx (0 .. $#$dsets) {
                if ('bartime' eq $graph_type) {
                    ## ...each last pushed value to each datasets, so the bartime graphs don't have any gaps
                    push @{ $points[$dset_idx] }, $last_pushed[$dset_idx];
                } else {
                    ## ...undef to each dataset
                    push @{ $points[$dset_idx] }, undef;
                }
            }

            next;
        }

        while (1) {
            if ($last_idx > $#$xdata) {
                ## at this point:
                ## - $limit_date should be eq $intervals[-1];
                ## - $cur_xdata should be undef
                if ($limit_date ne $intervals[-1]) {
                    warn "about to exit loop but limit_date ($limit_date) isn't the last elem in intervals ($intervals[-1])";
                }
                if (defined $cur_xdata) {
                    warn "about to exit loop but cur_xdata is defined ($cur_xdata)";
                }
                last OUTER;
            }
            if (1 == ($cur_xdata cmp $limit_date)) {
                ## push new point to @new_xdata and to the datasets
                push @new_xdata, $xdata->[ $last_idx-1 ];
                foreach my $dset_idx (0 .. $#$dsets) {
                    push @{ $points[$dset_idx] }, $dsets->[$dset_idx]{'points'}[ $last_idx-1 ];
                    $last_pushed[$dset_idx] = $dsets->[$dset_idx]{'points'}[ $last_idx-1 ];
                }

                last;
            }
            $last_idx++;
            $cur_xdata = $xdata->[ $last_idx ];
        }
    }
    ## at this point, $last_idx should be == 1 + $#$xdata == @$xdata
    if ($last_idx != @$xdata) {
        warn "premature exit from loop";
    }

    ## push last point to @new_xdata and to the datasets. Update the 'points' elem in each dataset with the new values
    push @new_xdata, $xdata->[ $last_idx-1 ];
    foreach my $dset_idx (0 .. $#$dsets) {
        push @{ $points[$dset_idx] }, $dsets->[$dset_idx]{'points'}[ $last_idx-1 ];
        $dsets->[$dset_idx]{'points'} = $points[$dset_idx];
    }

    undef @points;

    ## check that @new_xdata and the datasets have the same number of points
    my $npoints = @new_xdata;
    foreach my $dset_idx (0 .. $#$dsets) {
        if ($npoints != @{ $dsets->[$dset_idx]{'points'} }) {
            warn sprintf "new dataset $dset_idx has %d points instead of \@new_xdata's $npoints", scalar @{ $dsets->[$dset_idx]{'points'} };
        }
    }

    return \@new_xdata;
}

sub line_chart {
    my (%args) = @_;

    my ($xdata) = _quantize 10000, $args{'xdata'}, $args{'dsets'};      ## showing a lot of points is both cpu- and memory-intensive

    my %gp_dset_args = (
        xdata    => $xdata,
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
        title     => $args{'title'},
        #xlabel    => 'Time',
        #ylabel    => 'Notes',
        timeaxis  => 'x',
        #bg        => 'white',
        ($args{'logscale'} ? (logscale => $args{'logscale'}) : ()),
        ($args{'yrange'} ? (yrange => $args{'yrange'}) : ()),
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
    foreach my $idx (0..$#{ $args{'labels'} }) {
        push @labels, sprintf '"%s" %d', $args{'labels'}[$idx], $idx;
    }

    my $gp = Chart::Gnuplot->new (
        encoding     => 'utf8',
        terminal     => 'svg fsize 9',
        #imagesize   => '800, 600',
        output       => $args{'output'},
        title        => $args{'title'},
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

    my ($xdata) = _quantize 500, $args{'xdata'}, $args{'dsets'};      ## showing a lot of boxes is slow

    ## transform into percent
    if ($args{'percent'}) {
        my @totals;
        foreach my $idx (0 .. $#$xdata) {
            foreach my $dset_idx (0 .. $#{ $args{'dsets'} }) {
                next unless defined $args{'dsets'}[$dset_idx]{'points'}[$idx];
                $totals[$idx] += $args{'dsets'}[$dset_idx]{'points'}[$idx];
            }
        }

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
        encoding     => 'utf8',
        terminal     => 'svg fsize 9',
        #imagesize   => '800, 600',
        output       => $args{'output'},
        title        => $args{'title'},
        timeaxis  => 'x',
        #boxwidth     => '0.75 absolute',
        'style fill' => ($args{'bar_border'} ? 'solid 1 border lt -1' : 'solid 1'),
        ($args{'yrange'} ? (yrange => $args{'yrange'}) : $args{'percent'} ? (yrange => [ 0, 100 ]) : ()),
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
