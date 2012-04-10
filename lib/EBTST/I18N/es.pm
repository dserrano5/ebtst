package EBTST::I18N::es;

use Mojo::Base 'EBTST::I18N';
use EBTST::I18N;

our %Lexicon;
EBTST::I18N->setup_lex-> ((split '::', __PACKAGE__)[-1], \%Lexicon);

1;
