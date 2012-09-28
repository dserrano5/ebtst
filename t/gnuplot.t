#!/usr/bin/perl
use warnings;
use strict;
use Test::More;
use EBTST::Main::Gnuplot;

sub line_chart {
    my ($dsets, $xdata);

    ## group 1
    ## - all quantized points has some data
    ## - even quantization value
    ## - odd number of elements

    $dsets = [
        { points => [  1 ..  9 ] },
        { points => [ 11 .. 19 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 6,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',
            '2010-01-01 00:03:00',

            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:07:00',
            '2010-01-01 00:08:00',
            '2010-01-01 00:09:00',
        ], 
        $dsets;

    is scalar @$xdata, 6, 'line_chart: group 1: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:03:00',
        '2010-01-01 00:05:00',
        '2010-01-01 00:07:00',
        '2010-01-01 00:09:00',
    ], 'line_chart: group 1: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 6, 'line_chart: group 1: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 6, 'line_chart: group 1: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  3,  5,  7,  9 ], 'line_chart: group 1: dataset 0';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 13, 15, 17, 19 ], 'line_chart: group 1: dataset 1';


    ## group 2
    ## - all quantized points has some data
    ## - even quantization value
    ## - even number of elements

    $dsets = [
        { points => [  1 ..  8 ] },
        { points => [ 11 .. 18 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 6,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',
            '2010-01-01 00:03:00',

            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:07:00',
            '2010-01-01 00:08:00',
        ], 
        $dsets;

    is scalar @$xdata, 6, 'line_chart: group 2: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:03:00',
        '2010-01-01 00:04:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:08:00',
    ], 'line_chart: group 2: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 6, 'line_chart: group 2: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 6, 'line_chart: group 2: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  3,  4,  6,  8 ], 'line_chart: group 2: dataset 1';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 13, 14, 16, 18 ], 'line_chart: group 2: dataset 2';


    ## group 3
    ## - all quantized points has some data
    ## - odd quantization value
    ## - odd number of elements

    $dsets = [
        { points => [  1 ..  9 ] },
        { points => [ 11 .. 19 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 5,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',

            '2010-01-01 00:03:00',
            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:07:00',
            '2010-01-01 00:08:00',
            '2010-01-01 00:09:00',
        ], 
        $dsets;

    is scalar @$xdata, 5, 'line_chart: group 3: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:04:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:09:00',
    ], 'line_chart: group 3: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 5, 'line_chart: group 3: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 5, 'line_chart: group 3: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  4,  6,  9 ], 'line_chart: group 3: dataset 1';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 14, 16, 19 ], 'line_chart: group 3: dataset 2';

    ## group 4
    ## - all quantized points has some data
    ## - odd quantization value
    ## - even number of elements

    $dsets = [
        { points => [  1 ..  8 ] },
        { points => [ 11 .. 18 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 5,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',

            '2010-01-01 00:03:00',
            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:07:00',
            '2010-01-01 00:08:00',
        ], 
        $dsets;

    is scalar @$xdata, 5, 'line_chart: group 4: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:04:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:08:00',
    ], 'line_chart: group 4: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 5, 'line_chart: group 4: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 5, 'line_chart: group 4: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  4,  6,  8 ], 'line_chart: group 4: dataset 1';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 14, 16, 18 ], 'line_chart: group 4: dataset 2';

    ## group 5
    ## - not all quantized points has some data (there is some time between notes)
    ## - even quantization value
    ## - odd number of elements

    $dsets = [
        { points => [  1 ..  9 ] },
        { points => [ 11 .. 19 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 6,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',
            '2010-01-01 00:03:00',

            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:27:00',
            '2010-01-01 00:28:00',
            '2010-01-01 00:29:00',
        ], 
        $dsets;

    is scalar @$xdata, 6, 'line_chart: group 5: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:03:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:20:20',
        '2010-01-01 00:29:00',
    ], 'line_chart: group 5: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 6, 'line_chart: group 5: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 6, 'line_chart: group 5: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  3,  6, undef,  9 ], 'line_chart: group 5: dataset 0';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 13, 16, undef, 19 ], 'line_chart: group 5: dataset 1';

    ## group 6
    ## - not all quantized points has some data (there is some time between notes)
    ## - even quantization value
    ## - even number of elements

    $dsets = [
        { points => [  1 ..  8 ] },
        { points => [ 11 .. 18 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 6,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',
            '2010-01-01 00:03:00',

            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:27:00',
            '2010-01-01 00:28:00',
        ], 
        $dsets;

    is scalar @$xdata, 6, 'line_chart: group 6: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:03:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:19:40',
        '2010-01-01 00:28:00',
    ], 'line_chart: group 6: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 6, 'line_chart: group 6: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 6, 'line_chart: group 6: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  3,  6, undef,  8 ], 'line_chart: group 6: dataset 0';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 13, 16, undef, 18 ], 'line_chart: group 6: dataset 1';

    ## group 7
    ## - not all quantized points has some data (there is some time between notes)
    ## - odd quantization value
    ## - odd number of elements

    $dsets = [
        { points => [  1 ..  9 ] },
        { points => [ 11 .. 19 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 5,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',

            '2010-01-01 00:03:00',
            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:27:00',
            '2010-01-01 00:28:00',
            '2010-01-01 00:29:00',
        ], 
        $dsets;

    is scalar @$xdata, 5, 'line_chart: group 7: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:20:00',
        '2010-01-01 00:29:00',
    ], 'line_chart: group 7: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 5, 'line_chart: group 7: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 5, 'line_chart: group 7: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  6, undef,  9 ], 'line_chart: group 7: dataset 0';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 16, undef, 19 ], 'line_chart: group 7: dataset 1';

    ## group 8
    ## - not all quantized points has some data (there is some time between notes)
    ## - odd quantization value
    ## - even number of elements

    $dsets = [
        { points => [  1 ..  8 ] },
        { points => [ 11 .. 18 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 5,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',

            '2010-01-01 00:03:00',
            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:27:00',
            '2010-01-01 00:28:00',
        ], 
        $dsets;

    is scalar @$xdata, 5, 'line_chart: group 8: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:19:20',
        '2010-01-01 00:28:00',
    ], 'line_chart: group 8: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 5, 'line_chart: group 8: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 5, 'line_chart: group 8: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  6, undef,  8 ], 'line_chart: group 8: dataset 0';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 16, undef, 18 ], 'line_chart: group 8: dataset 1';
}

sub bartime_chart {
    my ($dsets, $xdata);

    ## group 1
    ## - all quantized points has some data
    ## - even quantization value
    ## - odd number of elements

    $dsets = [
        { points => [  1 ..  9 ] },
        { points => [ 11 .. 19 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 6,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',
            '2010-01-01 00:03:00',

            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:07:00',
            '2010-01-01 00:08:00',
            '2010-01-01 00:09:00',
        ], 
        $dsets;

    is scalar @$xdata, 6, 'bartime_chart: group 1: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:03:00',
        '2010-01-01 00:05:00',
        '2010-01-01 00:07:00',
        '2010-01-01 00:09:00',
    ], 'bartime_chart: group 1: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 6, 'bartime_chart: group 1: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 6, 'bartime_chart: group 1: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  3,  5,  7,  9 ], 'bartime_chart: group 1: dataset 0';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 13, 15, 17, 19 ], 'bartime_chart: group 1: dataset 1';


    ## group 2
    ## - all quantized points has some data
    ## - even quantization value
    ## - even number of elements

    $dsets = [
        { points => [  1 ..  8 ] },
        { points => [ 11 .. 18 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 6,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',
            '2010-01-01 00:03:00',

            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:07:00',
            '2010-01-01 00:08:00',
        ], 
        $dsets;

    is scalar @$xdata, 6, 'bartime_chart: group 2: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:03:00',
        '2010-01-01 00:04:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:08:00',
    ], 'bartime_chart: group 2: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 6, 'bartime_chart: group 2: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 6, 'bartime_chart: group 2: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  3,  4,  6,  8 ], 'bartime_chart: group 2: dataset 1';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 13, 14, 16, 18 ], 'bartime_chart: group 2: dataset 2';


    ## group 3
    ## - all quantized points has some data
    ## - odd quantization value
    ## - odd number of elements

    $dsets = [
        { points => [  1 ..  9 ] },
        { points => [ 11 .. 19 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 5,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',

            '2010-01-01 00:03:00',
            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:07:00',
            '2010-01-01 00:08:00',
            '2010-01-01 00:09:00',
        ], 
        $dsets;

    is scalar @$xdata, 5, 'bartime_chart: group 3: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:04:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:09:00',
    ], 'bartime_chart: group 3: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 5, 'bartime_chart: group 3: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 5, 'bartime_chart: group 3: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  4,  6,  9 ], 'bartime_chart: group 3: dataset 1';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 14, 16, 19 ], 'bartime_chart: group 3: dataset 2';

    ## group 4
    ## - all quantized points has some data
    ## - odd quantization value
    ## - even number of elements

    $dsets = [
        { points => [  1 ..  8 ] },
        { points => [ 11 .. 18 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 5,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',

            '2010-01-01 00:03:00',
            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:07:00',
            '2010-01-01 00:08:00',
        ], 
        $dsets;

    is scalar @$xdata, 5, 'bartime_chart: group 4: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:04:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:08:00',
    ], 'bartime_chart: group 4: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 5, 'bartime_chart: group 4: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 5, 'bartime_chart: group 4: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  4,  6,  8 ], 'bartime_chart: group 4: dataset 1';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 14, 16, 18 ], 'bartime_chart: group 4: dataset 2';

    ## group 5
    ## - not all quantized points has some data (there is some time between notes)
    ## - even quantization value
    ## - odd number of elements

    $dsets = [
        { points => [  1 ..  9 ] },
        { points => [ 11 .. 19 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 6,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',
            '2010-01-01 00:03:00',

            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:27:00',
            '2010-01-01 00:28:00',
            '2010-01-01 00:29:00',
        ], 
        $dsets;

    is scalar @$xdata, 6, 'bartime_chart: group 5: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:03:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:20:20',
        '2010-01-01 00:29:00',
    ], 'bartime_chart: group 5: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 6, 'bartime_chart: group 5: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 6, 'bartime_chart: group 5: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  3,  6,  6,  9 ], 'bartime_chart: group 5: dataset 0';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 13, 16, 16, 19 ], 'bartime_chart: group 5: dataset 1';

    ## group 6
    ## - not all quantized points has some data (there is some time between notes)
    ## - even quantization value
    ## - even number of elements

    $dsets = [
        { points => [  1 ..  8 ] },
        { points => [ 11 .. 18 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 6,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',
            '2010-01-01 00:03:00',

            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:27:00',
            '2010-01-01 00:28:00',
        ], 
        $dsets;

    is scalar @$xdata, 6, 'bartime_chart: group 6: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:03:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:19:40',
        '2010-01-01 00:28:00',
    ], 'bartime_chart: group 6: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 6, 'bartime_chart: group 6: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 6, 'bartime_chart: group 6: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  3,  6,  6,  8 ], 'bartime_chart: group 6: dataset 0';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 13, 16, 16, 18 ], 'bartime_chart: group 6: dataset 1';

    ## group 7
    ## - not all quantized points has some data (there is some time between notes)
    ## - odd quantization value
    ## - odd number of elements

    $dsets = [
        { points => [  1 ..  9 ] },
        { points => [ 11 .. 19 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 5,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',

            '2010-01-01 00:03:00',
            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:27:00',
            '2010-01-01 00:28:00',
            '2010-01-01 00:29:00',
        ], 
        $dsets;

    is scalar @$xdata, 5, 'bartime_chart: group 7: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:20:00',
        '2010-01-01 00:29:00',
    ], 'bartime_chart: group 7: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 5, 'bartime_chart: group 7: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 5, 'bartime_chart: group 7: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  6,  6,  9 ], 'bartime_chart: group 7: dataset 0';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 16, 16, 19 ], 'bartime_chart: group 7: dataset 1';

    ## group 8
    ## - not all quantized points has some data (there is some time between notes)
    ## - odd quantization value
    ## - even number of elements

    $dsets = [
        { points => [  1 ..  8 ] },
        { points => [ 11 .. 18 ] },
    ];
    $xdata = EBTST::Main::Gnuplot::_quantize 5,
        [
            '2010-01-01 00:01:00',
            '2010-01-01 00:02:00',

            '2010-01-01 00:03:00',
            '2010-01-01 00:04:00',
            '2010-01-01 00:05:00',
            '2010-01-01 00:06:00',
            '2010-01-01 00:27:00',
            '2010-01-01 00:28:00',
        ], 
        $dsets;

    is scalar @$xdata, 5, 'bartime_chart: group 8: number of xdata elems';
    is_deeply $xdata, [
        '2010-01-01 00:01:00',
        '2010-01-01 00:02:00',
        '2010-01-01 00:06:00',
        '2010-01-01 00:19:20',
        '2010-01-01 00:28:00',
    ], 'bartime_chart: group 8: xdata elements';
    is scalar @{ $dsets->[0]{'points'} }, 5, 'bartime_chart: group 8: number of dataset 0 elems';
    is scalar @{ $dsets->[1]{'points'} }, 5, 'bartime_chart: group 8: number of dataset 1 elems';
    is_deeply $dsets->[0]{'points'}, [  1,  2,  6,  6,  8 ], 'bartime_chart: group 8: dataset 0';
    is_deeply $dsets->[1]{'points'}, [ 11, 12, 16, 16, 18 ], 'bartime_chart: group 8: dataset 1';
}

line_chart;
bartime_chart;
done_testing 96;
