use lib qw(lib);
use Test::More;


plan skip_all => 'No test server available' if (!defined($ENV{NEWTS_PORT}) || !defined($ENV{NEWTS_HOST}));

use strict;
use warnings;
use EV;
use AnyEvent;
use Newts;
use Math::BigInt try => 'GMP';


my $ts = '1438819568000';
my $start = int(($ts-86400)/1000);
my $end = int(($ts+86400)/1000);

my $n = Newts->new( uri => "http://$ENV{NEWTS_HOST}:$ENV{NEWTS_PORT}/" );

my $r;

# test complicated PUT
$n->put( data => [ { id => 'bb1-test-net', name => 'temperature1', timestamp => $ts, type => 'GAUGE', value => 145 },
                   { id => 'bb1-test-net', name => 'temperature2', timestamp => $ts, type => 'COUNTER', value => 35 },
                 ] );

# test basic GET (for complicated PUT)
$r = $n->get( resource => 'bb1-test-net' );
my $t1_get_expected = [
      [
        {
          'type' => 'COUNTER',
          'name' => 'temperature2',
          'timestamp' => '1438819568000',
          'value' => 35
        },
        {
          'type' => 'GAUGE',
          'name' => 'temperature1',
          'timestamp' => '1438819568000',
          'value' => '145'
        }
      ]
    ];

is_deeply($r,$t1_get_expected,'Does value out == value in for bb1-test-net?');


# test non-array put/get
$n->put( data => { id => 'bb2-test-net', name => 'temperature1', timestamp => $ts, type => 'COUNTER', value => 35 } );
$r = $n->get( resource => 'bb2-test-net' );
is_deeply($r, [[
            {
              'name' => 'temperature1',
              'value' => 35,
              'timestamp' => '1438819568000',
              'type' => 'COUNTER'
            }
          ]], 'Non-array put');


# needed so we can suppress $cv->croak on errors
my $cv = AE::cv;
# test broken PUT (invalid timestamp)
$n->put( data => { id => 'bb3-test-net', name => 'cows', type => 'GAUGE', timestamp => 13, value => 3 },
         cv => $cv, on_error => sub { $cv->send} );
$r = $n->get( resource => 'bb3-test-net' );
is_deeply($r, [], 'invalid timestamp does not generate an entry');

# test broken PUT (improper type)
$n->put( data => { id => 'bb4-test-net', name => 'cows', type => 'CAGE', value => 3 },
                   cv => $cv, on_error => sub { $cv->send } );
$r = $n->get( resource => 'bb4-test-net' );
is_deeply($r, [], 'improper type (CAGE) should not generate an entry');

# test broken PUT (improper fields: this may not even pass our perl validation stuff)
$n->put( data => { id => 'bb5-test-net', metric => 'cows', type => 'GAUGE', value => 3 },
         cv => $cv, on_error => sub { $cv->send } );
$r = $n->get( resource => 'bb5-test-net' );
is_deeply($r, [], 'improper fields (metric instead of name) should not generate an entry');

# test broken PUT (missing type field)
$n->put( data => { id => 'bb6-test-net', name => 'cows', value => 3 },
         cv => $cv, on_error => sub { $cv->send } );
$r = $n->get( resource => 'bb5-test-net' );
is_deeply($r, [], 'missing field (type) should not generate an entry');

# test broken PUT (missing name field)
$n->put( data => { id => 'bb7-test-net', type => 'GAUGE', value => 3 },
         cv => $cv, on_error => sub { $cv->send } );
$r = $n->get( resource => 'bb7-test-net' );
is_deeply($r, [], 'missing field (name) should not generate an entry');

# test broken PUT montage  ( all of the above plus 1 valid one )
# if put fails then it seems to not continue with the next ones, or it may be
# that JSON can't encode them so the whole thing goes out as invalid.
$n->put( data => [
          { id => 'bb8-test-net', name => 'cows', type => 'GAUGE', timestamp => 13, value => 3 },
          { id => 'bb9-test-net', name => 'cows', type => 'CAGE', value => 3 },
          { id => 'bb10-test-net', metric => 'cows', type => 'GAUGE', value => 3 },
          { id => 'bb11-test-net', name => 'cows', value => 3 },
          { id => 'bb12-test-net', type => 'GAUGE', value => 3 },
          { id => 'bb13-test-net', type => 'GAUGE', name => 'valid', value => 14 },
        ], cv => $cv, on_error => sub { $cv->send } );

for(8..13) {
    $r = $n->get( resource => "bb$_-test-net" );
    is_deeply($r, [], "broken PUT montage ($_) generates no entries");
}


# test GET with timestamps
$r = $n->get( resource => 'bb1-test-net', start => $start, end => $end );
is_deeply($r, $t1_get_expected, 'get with timestamps');

# test GET with bogus values
$r = $n->get( resource => 'does-not-exist-test-net' ); # doesn't exist
is_deeply($r, [], 'GET with bogus resource');

# test working report
$r = $n->measure( resource => 'bb1-test-net', report => 'temps' );
is(scalar @{$r}, 98, 'measurement with working stuff');

# test an invalid report
$r = $n->measure( resource => 'bb1-test-net', report => 'not a real report' );
is_deeply($r, undef, 'measurement with invalid report fails');

# working search
$r = $n->search( query => 'americas' );
is_deeply($r, [
          {
            'metrics' => [
                           'inlet'
                         ],
            'resource' => {
                            'attributes' => {
                                              'location' => 'americas'
                                            },
                            'id' => 'localhost:chassis:temps'
                          }
          }
        ], 'working query');

# non working search
$r = $n->search( query => 'the internet' );
is_deeply($r, [], 'query with non-existant values');

done_testing();
exit;

# async examples

my $n2 = Newts->new( uri => "http://$ENV{NEWTS_HOST}:$ENV{NEWTS_PORT}/", async => 1 );

my $idx=0;
my $done_count=0;
# doesn't really work because all of them have the same timestamp when
# inserted, but the idea is to send a bunch of things.
for(1..10000) {
    $n2->put( data => { id => 'bb1-async-test-net', name => 'async_put', type => 'GAUGE', value => 3 } )->cb( sub { shift->recv; ++$done_count; });
    ++$idx;
}

my $wait = AE::cv;
my $timer = AnyEvent->timer(interval => 1, cb => sub {
    print "index = $idx, $done_count, ". AE::now. ' '. AE::time. "\n";
    $wait->send if ($done_count == 10000);
});

$wait->recv;

my $r = $n2->get( resource => 'bb1-async-test-net' )->recv;
use Data::Dumper; warn Dumper($r);
