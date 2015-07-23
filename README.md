# p5-Newts - Perl non-blocking Newts client

This is a Perl module for accessing the [Newts] time-series database.

* ![BUILD](https://travis-ci.org/rfdrake/p5-Newts.svg)

# Limitations

* Asynchronous support is a hot mess.  I've got an idea of what I'm trying to do, but I'm not pulling it off.  I may ask for help somewhere.

* Datasources for generating reports need to be built in Java.  An example might be something like this

    ```
    import static org.opennms.newts.api.query.StandardAggregationFunctions.*;
    import org.opennms.newts.api.query.*;
    ...

    CalculationFunction scaleToKbytes = new CalculationFunction() {
        public double apply(double ds) {
            return ds / 8 / 1024;
        }
    }

    ResultDescriptor report = new ResultDescriptor(300)
        .datasource("in",  "ifInOctets",  Duration.seconds(600), AVERAGE)
        .datasource("out", "ifOutOctets", Duration.seconds(600), AVERAGE)
        .calculate("inKbytes",  scaleToKbytes, "in")
        .calculate("outKbytes", scaleToKbytes, "out")
        .expression("sumKbytes", "inKbytes + outKbytes")
        .export("inKbytes", "outKbytes", "sumKbytes");
    ```

Because I imagine that needs to be JIT compiled, or in some other way turned
into a complicated object, this may never be available to build on the fly via
REST.  Even if it were, it might just be a wrapper that let you pass a Groovy
script into the report generator, but I'm sure there are security issues with
that.

Anyway, this only affects building new types of reports, or looking at things
in a different way, defining new aggregation periods.  If you define
everything you need ahead of time then you can handle your other access via
REST.


[Newts]: http://newts.io
