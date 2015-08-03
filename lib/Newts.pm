package Newts;

use strict;
use warnings;

use AnyEvent::HTTP;
use JSON;
use URI;
use HTTP::Headers;
use Math::BigInt try => 'GMP';
use v5.10;

=head1 NAME

Newts - a library implementing the REST interface for the Newts time-series database

=head1 SYNOPSIS

Getting information about a Newts server:

  use Newts;

  my $newts = Newts->new();
  $newts->put({ id => $id, name => $name, type => $type, value => $value, timestamp => $timestamp });
  $newts->get($id, $start, $end);
  $newts->measure();
  $newts->search($query);

=head1 VERSION

0.0.1

=cut

our $VERSION = '0.0.1';

=head1 AUTHOR

Robert Drake, C<< <rdrake at cpan.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Robert Drake, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 DESCRIPTION

Newts is a time-series data store based on Cassandra.  It's designed for high
throughput by minimizing aggregation, which reduces the number of reads needed
during a database insert.  The Cassandra backend also allows horizontal
scaling to improve throughput and redundancy and storage.

=head1 Convenience Methods

=head2 uri

    my $uri = $self->uri;

Getter for URI

=cut

sub uri { $_[0]->{uri} }

=head2 headers

    my $headers = $self->headers;

Custom HTTP headers defined by us in new()

=cut

sub headers { $_[0]->{headers} }

=head2 json

    my $json = $self->json;

JSON object reference

=cut

sub json { $_[0]->{json} }


# putting this here in case they decide to change to milliseconds
sub _default_time { time * 1000; }

=head1 Methods


=head2 new

    my $newt = Newts->new( uri => 'http://127.0.0.1:8080', async => 1 );

Creates a new object.  You may optionally specify the URI to the Newts server.
By default, it connects to L<http://127.0.0.1:8080>.

Most users will probably want to use synchronous programming, but if you're
using AnyEvent or Coro, or something like it you can specify async => 1
which will make all the methods non-blocking.  They will return a condvar
and you can manage them however you wish.

=cut

sub new {
    my $class = shift;
    my $input = @_;
    my $headers = HTTP::Headers->new;
    my $json = JSON->new->allow_nonref->allow_blessed->convert_blessed->utf8;
    $headers->push_header( 'Content-Type' => 'application/json; charset=utf-8', 'Accept-Encoding' => 'gzip,deflate' );

    my $self = bless {
        uri => 'http://127.0.0.1:8080/',
        headers => $headers,
        json => $json,
        async => 0,
        @_,
    }, $class;
    $self->{uri} = URI->new($self->{uri});

    return $self;
}

=head2 put

    my $result = $newts->put( { 'id' => 'server_name', 'name' => 'ifInOctets', 'type' => 'COUNTER', value => 32.333 } );
    my $result = $newts->put( { 'id' => 'server_name', 'name' => 'ifInOctets', 'type' => 'COUNTER', values => [ 32.333, 33 ] } );

Description: Persist new samples

Optional: attributes (associative array).  This can be in the main object or
under the resource where the id is stored.

Optional: timestamp (time in milliseconds).  This defaults to Perl time*1000.

Note: the "type" attribute is one of: COUNTER or GAUGE.

Success Response:    201 Created
Error Response:  400 Bad Request

=cut


sub _build_query {
    my $opt = shift;
    my $queries;

    $opt->{id} ||= $opt->{resource}{id};
    $opt->{timestamp} ||= _default_time;
    my $query = {
        'resource' => {
            'id' => $opt->{id},
        },
        'timestamp' => $opt->{timestamp},
        'name' => $opt->{name},
        'type' => $opt->{type},
        'attributes' => $opt->{attributes},
    };
    if ($opt->{values}) {
        foreach my $value (@{$opt->{values}}) {
            $query->{value}=$value;
            push(@$queries,$query);
        }
    } else {
        $query->{value}=$opt->{value};
        push(@$queries,$query);
    }

    return $queries;
}

sub put {
    my $self = shift;
    my $uri = $self->uri . 'samples';

    my $cv = AE::cv;

    my $query;
    for(@_) {
        push(@$query, @{_build_query($_)});
    }

    http_request(
        POST    => $uri,
        headers => $self->headers,
        body    => $self->json->encode($query),
        sub {
            my ($data, $headers) = @_;
            my $response;
            eval { $response = $self->json->decode($data); };
            if ($headers->{Status} >= 400) {
                $cv->croak("Error with HTTP Request: ". $headers->{Status} . ' '. $headers->{Reason} .' '.  $headers->{URL});
            } else {
                $cv->send($response);
            }
        }
    );

    if ($self->{async}) {
        return $cv;
    } else {
        return $cv->recv;
    }
}

=head2 get

    my $samples = $newts->get($id,$start,$end);

Description:   Query for raw (unaggregated) samples.

Start and end are both time in milliseconds, but can also be an ISO8601
timestamp.  Both start and end are optional.

Error Response:  (none)

=cut

sub get {
    my $self = shift;
    my ($resource, $start, $end) = (@_);
    $end ||= time;
    my $uri = URI->new($self->uri . "samples/$resource");
    my $query = {};
    $query->{start}=$start if ($start);
    $query->{end}=$end if ($end);

    $uri->query_form( $query );

    my $cv = AE::cv;

    http_get( $uri->as_string,
        sub {
            my ($data, $headers) = @_;
            my $response;
            eval { $response = $self->json->decode($data); };
            $cv->send($response);
        }
    );

    if ($self->{async}) {
        return $cv;
    } else {
        return $cv->recv;
    }
}

=head2 measure

    my $measurements = $newts->measure($id,$report,$resolution,$start,end);

Description:     Query for aggregated measurements.

report=[string]

Currently you will need to use another language to define your report.
According to the wiki they use a Fluent interface to build the report
definition https://github.com/OpenNMS/newts/wiki/ReportDefinitions

Once the report is defined in your database, you can run measurements against
it by referencing it via REST here.  By default a report called "temps" is
defined.

resolution=[period]

    The resolution of measurements returned, specified as an integer value,
followed by a resolution unit specifier character. Valid unit specifiers are
s, m, h, d, and w.

    Examples: 15m, 1d, 1w (for 15 minutes, 1 day, and 1 week respectively).

Defaults to 15m.

Optional:

start=[timespec]
    Query start time, specified as seconds since the Unix epoch, or an ISO 8601 timestamp.
end=[timespec]
    Query end time, specified as seconds since the Unix epoch, or an ISO 8601 timestamp.


Method returns an array of "row" arrays, each containing one or more
measurement representation objects. The inner, or "row" arrays contain results
with common timestamps; They represent the aggregate results for a group, at
some time interval.

Error Response:  (none)

=cut

sub measure {
    my $self = shift;
    my ($id, $report, $res, $start, $end) = (@_);
    $res ||= '15m';
    my $uri = URI->new($self->uri);
    $uri->path("/measurements/$report/$id");
    my $query = { 'resolution' => $res };
    $query->{start}=$start if ($start);
    $query->{end}=$end if ($end);

    $uri->query_form( $query );

    my $cv = AE::cv;

    http_get( $uri->as_string,
        sub {
            my ($data, $headers) = @_;
            my $response;
            eval { $response = $self->json->decode($data); };
            $cv->send($response);
        }
    );

    if ($self->{async}) {
        return $cv;
    } else {
        return $cv->recv;
    }
}

=head2 post_measurements

    $newts->post_measurements($interval, [ $datasource ], [ $expression ], [ $export ]);

This sends a POST to /measurements.

Arguments:
  Interval in seconds, default '300s'.
  Datasource: Arrayref of Newts::Datasource objects
  Expressions: Arrayref of Newts::Expressions objects
  Exports: Arrayref of strings.  These should be the labels for the datasource and expressions used

Depending on how the Newts object was setup, this will block until completed
or it will return a condvar to the calling program.

Here is an example of a raw JSON post sent through curl, in case that is needed for
troubleshooting:

    curl -X POST  -H "Accept: application/json" -H "Content-Type:
    application/json" -u admin:admin  -d @newts.json
    'http://127.0.0.1:18080/measurements/localhost:chassis:temps?start=1998-07-09T12:05:00-0500&end=1998-07-09T13:15:00-0500'

    And newts.json contains:
    {
        "interval": "300s",
        "datasources": [
            {
                "label": "ds1",
                "source": "inlet",
                "function": "AVERAGE",
                "heartbeat": "600s"
            }
        ],
        "expressions": [
            {
                "label": "ds1-2x",
                "expression": "2 * ds1"
            }
        ],
        "exports": [
            "ds1",
            "ds1-2x"
        ]
    }

=cut

sub post_measurements {
    my $self = shift;
    my $uri = $self->uri . 'measurements';
    my $cv = AE::cv;

    my $interval = shift;
    $interval ||= '300s';
    $interval =~ s/^(\d+)$/$1s/;
    my $datasources = shift;
    my $expressions = shift;
    my $exports = shift;

    http_request(
        POST    => $uri,
        headers => $self->headers,
        body    => $self->json->encode($interval, $datasources, $expressions, $exports),
        sub {
            my ($data, $headers) = @_;
            my $response;
            eval { $response = $self->json->decode($data); };
            if ($headers->{Status} >= 400) {
                $cv->croak("Error with HTTP Request: ". $headers->{Status} . ' '. $headers->{Reason} .' '.  $headers->{URL});
            } else {
                $cv->send($response);
            }
        }
    );

    if ($self->{async}) {
        return $cv;
    } else {
        return $cv->recv;
    }

}


=head2 search

    my $result = $newts->search('query');

Description:     Search resources

Success Response:

Returns an array of search result objects. Each search result object contains
an attribute for the corresponding resource, and an array of the associated
metric names.

Error Response:  (none)

=cut

sub search {
    my $self = shift;
    my ($search) = (@_);
    my $uri = $self->uri .  "/search/?q=$search";

    my $cv = AE::cv;

    http_get( $uri,
        sub {
            my ($data, $headers) = @_;
            my $response;
            eval { $response = $self->json->decode($data); };
            $cv->send($response);
        }
    );

    if ($self->{async}) {
        return $cv;
    } else {
        $cv->recv;
    }
}

1;

package Newts::Expressions;

sub new {
    my $class = shift;
    my $h = {
            'label' => '',
            'expression' => '',
            @_,
    };
    my $self = bless $h, $class;
}

1;

package Newts::Datasources;

sub new {
    my $class = shift;
    my $h = {
            'label' => '',
            'source' => '',
            'function' => 'AVERAGE',
            'heartbeat' => '600s',
            @_,
    };
    my $self = bless $h, $class;

    $self->{heartbeat} =~ s/^(\d+)$/$1s/;
}

1;
