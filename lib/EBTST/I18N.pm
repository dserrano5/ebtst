package EBTST::I18N;

use Mojo::Base -base;
use base 'Locale::Maketext';
use File::Spec;

sub setup_lex {
    my ($lang, $lex) = @_;

    warn "*** loading lexicon '$lang'\n";

    my $file = File::Spec->catfile ($ENV{'BASE_DIR'}, "$lang.txt");
    warn "*** file ($file)\n";
    if (!-r $file) {
        warn "*** file is not readable\n";
        return;
    }

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
}

1;
