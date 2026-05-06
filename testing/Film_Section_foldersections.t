# 07.11.2025

# verify that lists of sections for company folders are generated

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Film::Section';

use_ok($class) or die "Could not load $class\n";
can_ok($class, "foldersections");

my $collection = 'co';
my $folder_nk  = "041389" . "";

my @list;
ok(@list = $class->foldersections("$collection/$folder_nk", 2), "foldersections");
#diag Dumper @list;

done_testing;
