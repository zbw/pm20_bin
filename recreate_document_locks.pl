#!/bin/env perl
# nbt, 27.8.2019

# evaluate the access status of a pm20 document and create or rewrite an
# .htaccess file, when access is to be denied, otherwise remove any existing
# .htaccess file

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Log::Log4perl::Level;
use Path::Iterator::Rule;
use Path::Tiny;
use Readonly;
use YAML::Tiny;
use ZBW::Logutil;

# logging
my $log = ZBW::Logutil->get_logger('./log_conf/document_locks.logconf');
$log->level($INFO);

Readonly my $COPYRIGHT_TERM   => 70;
Readonly my $HTACCESS_CONTENT => <<'EOF';
Require env PM20_INTERNAL
<RequireAll>
  Require method HEAD
  Require env PM20_DFGVIEWER
</RequireAll>
EOF

# these flags overide everything else!
Readonly my $ACCESS_LOCKED_FN => 'access_locked.txt';
Readonly my $ACCESS_FREE_FN   => 'access_free.txt';

# document-specific metadata, especially authors' death_year and publication_date
# (overide codes from file name)
Readonly my $META_FN => 'meta.yaml';

# root directory for documents or param ALL is required
if ( not @ARGV ) {
  print "Usage: $0 {root_dir_absolute}|ALL\n";
  exit 1;
}
if ( $ARGV[0] eq 'ALL' ) {
  &recreate_all;
} else {
  my $docroot = path( $ARGV[0] );
  if ( !$docroot->is_dir ) {
    die "docroot '$docroot' is not a directory\n";
  }
  &recreate_path($docroot);
}

#########################

sub recreate_all {
  my $folder_root = path('/pm20/folder');

  # cover folders and documents in all collections
  $log->info("Start ALL");
  foreach my $collection (qw/ co pe sh wa /) {
    my $docroot = $folder_root->child($collection);
    &recreate_path($docroot);
  }
  $log->info("End ALL");
}

sub recreate_path {
  my $docroot = shift or die "param missing";

  $log->info("Start run $docroot");

  # recursivly visit all subdirectories, which include a PIC subdirectory
  my $rule = Path::Iterator::Rule->new;
  $rule->and( sub { -d "$_/PIC" } );
  my %options = ();
  my $next    = $rule->iter( ($docroot), \%options );
  while ( defined( my $file = $next->() ) ) {
    my $path        = path($file);
    my $free_status = is_free($path);
    $log->debug("free_status $free_status $path");

    # remove existing .htaccess file
    my $htaccess              = $path->child('.htaccess');
    my $pre_existing_htaccess = 0;
    if ( $htaccess->is_file ) {
      $pre_existing_htaccess = 1;
      $htaccess->remove;
    }
    if ( $free_status eq 0 ) {
      $htaccess->spew($HTACCESS_CONTENT);
    }

    # logging
    if ( $free_status and $pre_existing_htaccess ) {
      $log->info("unblocked $path");
    }
    if ( !$free_status and !$pre_existing_htaccess ) {
      $log->info("blocked $path");
    }
  }

  $log->info("End run $docroot");
}

sub is_free {
  my $path = shift;

  my $free_status = 0;

  # text files can be used to override permissions
  # and should contain the reason for blocking or unblocking a document,
  # user (abbrev) and date
  # - access_locked.txt overrides all
  # - access_free.txt overrides restricions in file name

  if ( $path->child($ACCESS_LOCKED_FN)->is_file ) {
    $free_status = 0;
  } elsif ( $path->child($ACCESS_FREE_FN)->is_file ) {
    $free_status = 1;
  } elsif ( $path->child($META_FN)->is_file and evaluate_meta_free($path) ) {
    ## when the document meta file evaluates to 'access free' according to
    ## copyright term
    $free_status = 1;
  } else {
    ## extract code from the first page of the document, hi res version
    my @files = sort $path->child('PIC')->children(qr/_A.JPG/);
    if ( scalar(@files) gt 0 ) {
      $files[0]->basename =~ m/.{39}(.{3})/;
      my $code = $1;
      ($free_status) = evaluate_code( $code, $path );
    } else {
      $log->warn( "empty path " . $path->child('PIC') );
    }
  }
  return $free_status;
}

sub evaluate_code {
  my $code = shift or die "param missing";
  my $path = shift or die "param missing";

  my $free_status = 0;

  if ( $code eq "000" ) {
    $free_status = 1;
  } elsif ( $code eq "BEC" ) {
    $free_status = 1;
  } elsif ( $code eq "JEU" ) {
    $free_status = 0;
  } elsif ( $code =~ m/.(XX|xx)/ ) {
    $free_status = 0;
  } elsif ( $code =~ m/.(\d\d)/ ) {
    my $yy = $1;

    # set proper free year for moving wall
    # (2005 was the last year from which articles were added)
    my $year;
    if ( $yy > 5 ) {
      $year = 1900 + $yy;
    } else {
      $year = 2000 + $yy;
    }
    $free_status = compute_current_status($year);
  } else {
    $log->warn("Strange code $code in $path");
  }
  return $free_status;
}

sub evaluate_meta_free {
  my $path = shift or die "param missing";

  # check yaml file for death year only
  my $free_status = 0;
  my $meta_ref    = YAML::Tiny->read( $path->child($META_FN) );
  if ( $meta_ref->[0]->{death_year} ) {
    $free_status = compute_current_status( $meta_ref->[0]->{death_year} );
  }

  return $free_status;
}

sub compute_current_status {
  my $year = shift or die "param missing";

  # compute status from year (moving wall)
  my $current_year = 1900 + (localtime)[5];
  my $free_status;
  if ( $current_year > $year + $COPYRIGHT_TERM ) {
    $free_status = 1;
  } else {
    $free_status = 0;
  }
  return $free_status;
}
