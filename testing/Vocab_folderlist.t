# 27.11.2025

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;
use ZBW::PM20x::Folder;

my $class = 'ZBW::PM20x::Vocab';

use_ok($class) or die "Could not load $class\n";

my ( $ware_id, $geo_id, $subject_id, @warefolders );
my $ware_vocab = $class->new('ware');
my $geo_vocab  = $class->new('geo');
#my $subject_vocab = $class->new('subject');

# Achat
ok( @warefolders = $ware_vocab->folderlist( 'de', '141944', $geo_vocab ),
  'foldersections (Achat)' );

#diag Dumper $warefolders[0];
#diag Dumper \@warefolders;

done_testing;

1;
