#!/bin/env perl
# nbt, 2022-03-25

# get an indexed xml sitemap of all pm20 pages

use strict;
use warnings;
use autodie;
use utf8;

use Data::Dumper;
use List::MoreUtils qw/uniq/;
use Path::Tiny;
use Web::Sitemap;
use Web::Sitemap::Url_patched;

$Data::Dumper::Sortkeys = 1;

my $sm = Web::Sitemap->new(
  output_dir => '/pm20/web',

  ### Options ###

  temp_dir    => '/tmp',
  loc_prefix  => 'https://pm20.zbw.eu',
  index_name  => 'sitemap',
  file_prefix => 'sitemap.',

  # mark for grouping urls
  ##default_tag => 'my_tag',

  # add <mobile:mobile/> inside <url>, and appropriate namespace (Google
  # standard)
  ##mobile => 1,

  # add appropriate namespace (Google standard)
  ##images      => 1,

  # additional namespaces (scalar or array ref) for <urlset>
  ##namespace   => 'xmlns:some_namespace_name="..."',

  # location prefix for files-parts of the sitemap (default is loc_prefix value)
  ## file_loc_prefix  => 'http://my_domain.com',

  # specify data input charset
  charset => 'utf8',

  move_from_temp_action => sub {
    my ( $temp_file_name, $public_file_name ) = @_;
    File::Copy::move( $temp_file_name, $public_file_name );
    chmod 0664, $public_file_name;
  }

);

# not used - would only make sense with enhanced prio
my @main_url_list = (
  qw {
    /about.de.html
    /about.en.html
  }
);
##$sm->add( \@main_url_list, tag => 'main' );

# work through all sets used in make, get all HTML urls (from file system) and
# add them
foreach my $set (qw/ default category co pe sh wa pdf /) {
  print "$set ...\n";
  my $url_list_ref = get_urls($set);
  $sm->add( $url_list_ref, tag => $set );
}

# After calling finish() method will create an index file, which will link to files with URL's
$sm->finish;

# rough overview
print Dumper $sm;

###################

sub get_urls {
  my $set = shift or die "param missing";

  my @temp;
  if ( $set eq 'pdf' ) {
    ## get pdf from about-pm20 only (not doc)
    @temp = `cd /pm20/web ; find ./about-pm20 -name "*.pdf"`;
  } elsif ( grep ( /^$set$/, qw/ co pe sh wa / ) ) {
    ## use prepared list of folders with documents
    @temp = split( /\n/,
      path("/pm20/data/folderdata/${set}_for_sitemap.lst")->slurp );
  } else {
    ## get a list of .md files as used in make
    @temp = `/bin/sh /pm20/web/mk/find_md.sh $set`;
  }
  my $url_list_ref;
  ## for some strange reason, lines in ??_for_sitemap.lst are duplicate
  foreach my $line ( uniq @temp ) {
    chomp($line);
    $line = substr( $line, 1, );
    $line =~ s/(.+)?\.md$/$1\.html/;
    next unless $line =~ m/\.(html|pdf)$/;
    my $entry = {
      loc      => $line,
      priority => get_priority($line),
    };
    push( @$url_list_ref, $entry );
  }

  return $url_list_ref;
}

sub get_priority {
  my $url = shift or die "param missing";

  my $priority = '0.2';

  my @url_prios = (
    {
      pattern  => qr{^/about\...\.html$},
      priority => '1.0',
    },
    {
      pattern  => qr{^/about-pm20/legal},
      priority => '0.1',
    },
    {
      pattern  => qr{^/about-pm20/(?:hwwa|fs|wia|publication/testimonial)},
      priority => '0.9',
    },
    {
      pattern  => qr{^/(?:doc/holding|film/about)},
      priority => '0.9',
    },
    {
      pattern  => qr{^/category/(?:geo|subject|ware)/about},
      priority => '0.9',
    },
    {
      pattern  => qr{^/folder/(?:co|pe)/[0-9]},
      priority => '0.8',
    },
    {
      pattern  => qr{^/about-pm20/(?:about|links|publication)},
      priority => '0.7',
    },
    {
      pattern  => qr{^/category/},
      priority => '0.6',
    },
    {
      pattern  => qr{^/report},
      priority => '0.3',
    },
    {
      pattern  => qr{^/error},
      priority => '0.0',
    },
  );

  foreach my $url_prio (@url_prios) {
    my $pattern = $url_prio->{pattern};
    my $prio    = $url_prio->{priority};
    if ( $url =~ $pattern ) {
      $priority = $prio;
      last;
    }
  }
  return $priority;
}

