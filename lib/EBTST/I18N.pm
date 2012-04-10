package EBTST::I18N;

use Mojo::Base -base;
#use File::Spec;
#use FindBin;

has setup_lex => sub { sub {
    my ($lang, $lex) = @_;

    warn "*** loading lexicon '$lang'\n";

    my $file = File::Spec->catfile ($FindBin::Bin, '..', "$lang.txt");     ## linux ($Bin ends in 'script/')
    -r $file or $file = File::Spec->catfile ($FindBin::Bin, "$lang.txt");  ## windows ($Bin points to the dir of the .exe file)
    warn "*** file ($file)\n";
    if (!-r $file) {
        warn "*** file is not readable\n";
        return;
    }
    #warn "*** file is readable\n";

    open my $fd, '<:encoding(UTF-8)', $file or die "open: '$file': $!";
    local $_;
    while (<$fd>) {
        ## works with both linux and windows versions of $file
        s/[\x0d\x0a]*$//;

        next unless length;
        next if /^\s*#/;
        warn "*** incorrect line '$_'\n" and next unless /=/;

        my ($orig, $xlated) = split /\s*=\s*/, $_, 2;
        $lex->{$orig} = $xlated;
    }
    close $fd;

    warn "*** lexicon '$lang' loaded\n";
};};

1;
