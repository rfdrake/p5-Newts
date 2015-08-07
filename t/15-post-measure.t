use lib qw(lib);
use Test::More;
use strict;
use warnings;
use Newts;
use Math::BigInt try => 'GMP';

plan skip_all => 'No test server available' if (!defined($ENV{NEWTS_PORT}) || !defined($ENV{NEWTS_HOST}));

my $n = Newts->new( uri => "http://$ENV{NEWTS_HOST}:$ENV{NEWTS_PORT}/" );

my $ds1 = Newts::Datasources->new( label => 'inOctets', source => 'IfInOctets', heartbeat => '600s', function => 'AVERAGE' );
my $ds2 = Newts::Datasources->new( label => 'outOctets', source => 'IfOutOctets', heartbeat => '600s', function => 'AVERAGE' );
my $e1 = Newts::Expressions->new( label => 'inKbytes', expression => 'inOctets / 8 / 1024' );
my $e2 = Newts::Expressions->new( label => 'outKbytes', expression => 'outOctets / 8 / 1024' );
my $e3 = Newts::Expressions->new( label => 'sumKbytes', expression => 'inKbytes + outKbytes' );

# add some values
my @data;
my $time = time;
for(1..30) {
    my $ts = $time-$_*300;
    my $val = $_* 3_000_000;
    push(@data, { id => 'bb1-report-test-net', name => 'ifInOctets', timestamp => $ts*1000, type => 'COUNTER', value => $val } );
    push(@data, { id => 'bb1-report-test-net', name => 'ifOutOctets', timestamp => $ts*1000, type => 'COUNTER', value => $val } );
}
$n->put( data => \@data );

my $r = $n->create_report( report => 'traffic', start => $time-(30*300)-300, end => $time+300,
                        interval => '300s',
                        datasources => [ $ds1, $ds2 ],
                        expressions => [ $e1, $e2, $e3 ],
                        exports => [ $e1->label, $e2->label, $e3->label ] );

use Data::Dumper; warn Dumper($r);
done_testing();
