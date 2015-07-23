use lib qw(lib);
use Test::More;
plan skip_all => 'No test server available';

$ENV{PERL_ANYEVENT_STRICT}=1;
$ENV{PERL_ANYEVENT_VERBOSE}=1;

use AnyEvent;
use AnyEvent::Strict;
use Newts;

# we need to be able to do idempotent get/puts in the database or blow away
# the database, or mock the whole database if we want consistent tests
my $n = Newts->new();

my $r;

# test complicated PUT
$r = $n->put( { id => 'bb1-test-net', name => 'temperature1', type => 'GAUGE', values => [33, 35, 37, 39, 145 ] },
         { id => 'bb11-test-net', name => 'temperature2', type => 'COUNTER', value => 35 } );

# test broken PUT (invalid timestamp)
#$r = $n->put( { id => 'bb2-test-net', name => 'cows', type => 'GAUGE', timestamp => 13, value => 3 } );
#use Data::Dumper; warn Dumper($r);
# test broken PUT (improper type)
#$r = $n->put( { id => 'bb2-test-net', name => 'cows', type => 'CAGE', value => 3 } );
#use Data::Dumper; warn Dumper($r);
# test broken PUT (improper fields: this may not even pass our perl stuff)
#$r = $n->put( { id => 'bb2-test-net', metric => 'cows', type => 'GAUGE', value => 3 } );
#use Data::Dumper; warn Dumper($r);
# test broken PUT (missing type field)
#$r = $n->put( { id => 'bb2-test-net', name => 'cows', value => 3 } );
#use Data::Dumper; warn Dumper($r);
# test broken PUT (missing name field)
#$r = $n->put( { id => 'bb2-test-net', type => 'GAUGE', value => 3 } );
#use Data::Dumper; warn Dumper($r);
# test broken PUT montage  ( all of the above plus 1 valid one )
# if put fails then it seems to not continue with the next ones, or it may be
# that JSON can't encode them.
# $r = $n->put(
#          { id => 'bb2-test-net', name => 'cows', type => 'GAUGE', timestamp => 13, value => 3 },
#          { id => 'bb2-test-net', name => 'cows', type => 'CAGE', value => 3 },
#          { id => 'bb2-test-net', metric => 'cows', type => 'GAUGE', value => 3 },
#          { id => 'bb2-test-net', name => 'cows', value => 3 },
#          { id => 'bb2-test-net', type => 'GAUGE', value => 3 },
#          { id => 'bb3-test-net', type => 'GAUGE', name => 'valid', value => 14 }
#        );
# use Data::Dumper; warn Dumper($r);

# test basic GET
$r = $n->get( 'bb1-test-net' );

# test GET with timestamps
$r = $n->get( 'bb1-test-net', $start, $end );

# test GET with bogus values
$r = $n->get( 'bb10-test-net' ); # doesn't exist

# test working measurement
$r = $n->measure( 'localhost:chassis:temps', 'temps' );
# test something that doesn't work
$r = $n->measure( 'bb1-test-net', 'not a real report' );

# working search
$r = $n->search( 'americas' );

# non working search
$r = $n->search( 'the internet' );


# async examples

my $cv = AE::cv;

my $n2 = Newts->new( async => 1, cv => $cv );

for(1..100) {
    $n2->put( { id => 'bb5-test-net', name => 'async_put', type => 'GAUGE', timestamp => 13, value => 3 } )->cb(sub { $_[0]->recv; });
}

$r = $n2->get('bb5-test-net')->cb(sub { $_[0]->recv; });

$cv->recv;
use Data::Dumper; warn Dumper($r);

