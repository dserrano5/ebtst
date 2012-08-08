package EBT2::Constants;

use strict;
use warnings;
use Exporter;
use List::MoreUtils qw/zip/;

my ($h, @fields, $nfields);
BEGIN {
    @fields = qw/
        note_no value year serial date_entered dow recent city country zip
        short_code id times_entered moderated_hit lat long signature errors hit desc
    /;
    $nfields = @fields;
    $h = { zip @{[ map uc, @fields ]}, @{[ 0..$#fields ]} };
}
use constant $h;
use constant COL_NAMES => @fields;
use constant NCOLS => $nfields;

our @ISA = 'Exporter';
our @EXPORT_OK = (keys %$h, qw/COL_NAMES NCOLS/);
our %EXPORT_TAGS = (all => [ @EXPORT_OK ]);

1;
