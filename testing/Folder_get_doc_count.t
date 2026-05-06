# 2025-11-29

use strict;
use warnings;
use autodie;
use utf8::all;

use Data::Dumper;
use Test::More;

my $class = 'ZBW::PM20x::Folder';

use_ok($class);

my $folder;

# existing folder (Akim Ltd)
ok( $folder = $class->new( 'co', '047022' ), 'new ok' );
##diag Dumper $folder;
is( $folder->get_doc_count, 28, "document count" );

# non-existing folder (this is used in Vocab->folderlist!)
ok( $folder = $class->new( 'sh', '666666,777777' ), 'new ok' );
##diag Dumper $folder;
is( $folder->get_doc_count, undef, "undef document count" );

done_testing;

1;
