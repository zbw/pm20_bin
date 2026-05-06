# 07.11.2025

# verify that lists of sections for company folders are generated

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Folder';

use_ok($class) or die "Could not load $class\n";

my $collection = 'co';
my $folder_nk  = "041389" . "";

ok( my $folder = $class->new( $collection, $folder_nk ), "new folder" );
ok( $folder->get_filmsectionlist(2), "get filmsectionlist" );

done_testing;
