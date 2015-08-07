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
  $newts->get( $id, $start, $end );
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
    my $json = JSON->new->allow_nonref->convert_blessed->utf8;
    $headers->push_header( 'Content-Type' => 'application/json; charset=utf-8',
                           'Accept' => 'application/json',
                           'Accept-Encoding' => 'gzip,deflate' );

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

# putting this here in case they decide to change to milliseconds
sub _default_time { time * 1000; }

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
        'value' => $opt->{value},
    };
    push(@$queries,$query);

    return $queries;
}

# this is the default callback we'll be using for almost any sub
sub _cvcb {
    my $self = shift;
    my $args = shift;
    my $cv = $args->{cv} || $self->{cv} || AE::cv;
    $args->{on_success} ||= $args->{on_response};

    my $cb = sub {
        my ($data, $headers) = @_;
        my $response;
        eval { $response = $self->json->decode($data); };
        if ($headers->{Status} >= 400) {
            if ($args->{on_error}) {
                $args->{on_error}->(@_);
            } else {
                $cv->croak("Error with HTTP Request: ". $headers->{Status} . ' '. $headers->{Reason} .' '.  $headers->{URL});
            }
        } else {
            if ($args->{on_success}) {
                $args->{on_success}->($response);
            } else {
                $cv->send($response);
            }
        }
    };

    ($cv, $cb);
}

=head2 put

    my $result = $newts->put( data => { 'id' => 'server_name', 'name' => 'ifInOctets', 'type' => 'COUNTER', value => 32.333 } );

Description: Persist new samples

Optional: attributes (associative array).  This can be in the main object or
under the resource where the id is stored.

Optional: timestamp (time in milliseconds).  This defaults to Perl time*1000.

Note: the "type" attribute is one of: COUNTER or GAUGE.

Success Response:    201 Created
Error Response:  400 Bad Request

=cut


sub put {
    my ($self, %args) = @_;
    my ($cv, $cb) = $self->_cvcb(\%args);
    my $uri = $self->uri . 'samples';

    my $query;
    if (ref($args{data}) eq 'ARRAY') {
        for(@{$args{data}}) {
            push(@$query, @{_build_query($_)});
        }
    } else {
        $query = _build_query($args{data});
    }

    http_request(
        POST    => $uri,
        headers => $self->headers,
        body    => $self->json->encode($query),
        $cb
    );

    if ($self->{async}) {
        return $cv;
    } else {
        return $cv->recv;
    }
}

=head2 get

    my $samples = $newts->get( resource => $id, start => $start, end => $end);

Description:   Query for raw (unaggregated) samples.

Start and end are both time in milliseconds, but can also be an ISO8601
timestamp.  Both start and end are optional.

Error Response:  (none)

=cut

sub get {
    my ($self, %args) = @_;
    my ($cv, $cb) = $self->_cvcb(\%args);
    my $uri = URI->new($self->uri . "samples/$args{resource}");
    my $query = {};
    $query->{start}=$args{start} if ($args{start});
    $args{end} ||= time if ($args{start});
    $query->{end}=$args{end} if ($args{end});

    $uri->query_form( $query );

    http_get( $uri->as_string, $cb );

    if ($self->{async}) {
        return $cv;
    } else {
        return $cv->recv;
    }
}

=head2 measure

    my $measurements = $newts->measure( resource => $id,
                                        report => $report,
                                        resolution => $resolution,
                                        start => $start,
                                        end => $end);

Description:     Query for aggregated measurements.

resource=[string]

    The required name of the device you are asking about.

report=[string]

    This is a precompiled aggregation report that is built through using
$newts->post_measurements, or via an external interface.  By default, at least
in the vagrant-newts test system, there is a test report called 'temps' that
is used for sensor data they imported from weather stations.

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
    If you specify a start time but not an end time then this defaults to perl's time()

Method returns an array of "row" arrays, each containing one or more
measurement representation objects. The inner, or "row" arrays contain results
with common timestamps; They represent the aggregate results for a group, at
some time interval.

Error Response:  (none)

=cut

sub measure {
    my ($self, %args) = @_;
    my ($cv, $cb) = $self->_cvcb(\%args);
    my $uri = URI->new($self->uri);
    $args{report} ||= 'temps';

    # I should convert this into an Exception
    if (!defined($args{resource})) {
        die "resource not defined.";
    }
    $uri->path("/measurements/$args{report}/$args{resource}");

    $args{resolution} ||= '15m';
    my $query = { 'resolution' => $args{resolution} };
    $query->{start}=$args{start} if ($args{start});
    $args{end} ||= time if ($args{start});
    $query->{end}=$args{end} if ($args{end});

    $uri->query_form( $query );

    http_get( $uri->as_string, $cb );

    if ($self->{async}) {
        return $cv;
    } else {
        return $cv->recv;
    }
}

=head2 create_report

    $newts->create_report(interval => $interval, datasources => [ $ds ], expressions => [ $expression ], exports => [ $export ] ]);

This sends a POST to /measurements.

Arguments:
  Report: name of the new report
  Interval in seconds, default '300s'.
  Datasource: Arrayref of Newts::Datasource objects
  Expressions: Arrayref of Newts::Expressions objects.
  Exports: Arrayref of strings.  These should be the labels for the datasource
and expressions you want the report to return.  For instance, if your dataset
was bytes and you created expressions to calculate Kbytes, then your output
could have only Kbytes.

You could also do a summary expression of two input datasources, like inOctets
+ outOctets, then export the summary.  See the 15-post-measure.t for an
example.

Depending on how the Newts object was setup, this will block until completed
or it will return a condvar to the calling program.

Returns: Returns the matching report output

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

See https://github.com/OpenNMS/newts/wiki/ReportDefinitions for more
information.

=cut

sub create_report {
    my ($self, %args) = @_;
    my $uri = URI->new($self->uri . "measurements/$args{report}");
    my ($cv, $cb) = $self->_cvcb(\%args);
    $args{interval} ||= '300s';
    $args{interval} =~ s/^(\d+)$/$1s/;

        warn $self->json->encode({
                        interval => $args{interval},
                        datasources => $args{datasources},
                        expressions => $args{expressions},
                        exports => $args{exports} });

    http_request(
        POST    => $uri->as_string,
        headers => $self->headers,
        body    => $self->json->encode({
                        interval => $args{interval},
                        datasources => $args{datasources},
                        expressions => $args{expressions},
                        exports => $args{exports} }),
        $cb
    );

    if ($self->{async}) {
        return $cv;
    } else {
        return $cv->recv;
    }

}


=head2 search

    my $result = $newts->search(query => 'query');

Description:     Search resources

Success Response:

Returns an array of search result objects. Each search result object contains
an attribute for the corresponding resource, and an array of the associated
metric names.

Error Response:  (none)

=cut

sub search {
    my ($self, %args) = @_;
    my $search = $args{query};
    my $uri = URI->new($self->uri .  "search/?q=$search");

    my ($cv, $cb) = $self->_cvcb(\%args);

    http_get( $uri->as_string, $cb );

    if ($self->{async}) {
        return $cv;
    } else {
        $cv->recv;
    }
}

1;

# I may convert these into Type::Tiny objects later so that we can put
# constraints on function types and things like that.  Right now free form
# text is probably ok because we're just puking it all into REST and letting
# the newts backend handle errors. :)

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

sub TO_JSON { return { %{ shift() } }; }

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
    return $self;
}

sub TO_JSON { return { %{ shift() } }; }

1;
