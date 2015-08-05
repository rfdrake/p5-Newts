use lib qw(lib);
use Test::More;


plan skip_all => 'No test server available' if (!defined($ENV{NEWTS_PORT}) || !defined($ENV{NEWTS_HOST}));

use EV;
use AnyEvent;
use Newts;

# we need to be able to do idempotent get/puts in the database or blow away
# the database, or mock the whole database if we want consistent tests
my $n = Newts->new( uri => "http://$ENV{NEWTS_HOST}:$ENV{NEWTS_PORT}/" );

my $r;

# test complicated PUT
$r = $n->put( data => [ { id => 'bb1-test-net', name => 'temperature1', type => 'GAUGE', values => [33, 35, 37, 39, 145 ] },
                        { id => 'bb11-test-net', name => 'temperature2', type => 'COUNTER', value => 35 },
                      ] );

# test non-arrayref put
$r = $n->put( data => { id => 'bb2-test2-net', name => 'temperature1', type => 'COUNTER', value => 35 } );

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
$r = $n->get( resource => 'bb1-test-net' );

# test GET with timestamps
$r = $n->get( resource => 'bb1-test-net', start => $start, end => $end );

# test GET with bogus values
$r = $n->get( resource => 'bb10-test-net' ); # doesn't exist

# test working measurement
$r = $n->measure( resource => 'bb1-test-net', report => 'temps' );
# test something that doesn't work
$r = $n->measure( resource => 'bb1-test-net', report => 'not a real report' );

# working search
$r = $n->search( query => 'americas' );

# non working search
$r = $n->search( query => 'the internet' );


# async examples

my $n2 = Newts->new( uri => "http://$ENV{NEWTS_HOST}:$ENV{NEWTS_PORT}/", async => 1 );

my $idx=0;
my $done_count=0;
# doesn't really work because all of them have the same timestamp when
# inserted, but the idea is to send a bunch of things.
for(1..10000) {
    $n2->put( data => { id => 'bb5-test-net', name => 'async_put', type => 'GAUGE', value => 3 } )->cb( sub { shift->recv; ++$done_count; });
    ++$idx;
}

my $wait = AE::cv;
my $timer = AnyEvent->timer(interval => 1, cb => sub {
    print "index = $idx, $done_count, ". AE::now. ' '. AE::time. "\n";
    $wait->send if ($done_count == 10000);
});

$wait->recv;

my $r = $n2->get( resource => 'bb5-test-net' )->recv;
use Data::Dumper; warn Dumper($r);
