use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME          => 'Email::MIME::XPath',
  AUTHOR        => 'Hans Dieter Pearcey <hdp@cpan.org>',
  VERSION_FROM  => 'lib/Email/MIME/XPath.pm',
  ABSTRACT_FROM => 'lib/Email/MIME/XPath.pm',
  PL_FILES      => {},
  PREREQ_PM     => {
    'Test::More'       => 0,
  },
  dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
  clean => { FILES    => 'Email-MIME-XPath-*' },
);
