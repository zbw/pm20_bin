# 14.11.2025

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Vocab';

use_ok($class) or die "Could not load $class\n";

my $name = 'geo';

my $vocab = $class->new($name);

is($vocab->vocab_name, $name, "name returned correctly");


done_testing;
