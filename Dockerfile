FROM debian:9.5

RUN apt-get update && apt-get -y install \
  sudo git make gnuplot \
  liblocal-lib-perl cpanminus \
  libchart-gnuplot-perl libconfig-general-perl libdatetime-perl libdbd-csv-perl libdbi-perl libmojolicious-perl libmojolicious-plugin-i18n-perl libtext-csv-perl

RUN useradd --home-dir /home/ebtst --create-home --shell /bin/bash --user-group --groups sudo ebtst
RUN echo 'ebtst:ebtst' |chpasswd

USER ebtst
WORKDIR /home/ebtst

## for local::lib
ENV PATH "/home/ebtst/perl5/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV PERL5LIB "/home/ebtst/perl5/lib/perl5"
ENV PERL_LOCAL_LIB_ROOT "/home/ebtst/perl5"
ENV PERL_MB_OPT "--install_base \"/home/ebtst/perl5\""
ENV PERL_MM_OPT "INSTALL_BASE=/home/ebtst/perl5"

RUN cpanm Date::DayOfWeek Mojolicious::Plugin::Session
RUN git clone https://github.com/dserrano5/ebtst
RUN mkdir ebtst/log .ebt && touch .ebt/mojo-users && cp -a ebtst/sample-config/* .ebt
RUN sed -i -e 's_/home/user_/home/ebtst_; s_localhost:3030_*:3030_; s%^#base_href = .*%base_href = http://localhost:3030/%' .ebt/ebtst.cfg 
RUN touch .ebt/ebtst-key && chmod 600 .ebt/ebtst-key && echo $RANDOM$RANDOM$RANDOM >.ebt/ebtst-key

EXPOSE 3030
ENTRYPOINT hypnotoad --foreground /home/ebtst/ebtst/script/ebtst.pl
