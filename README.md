# earl-report
============

Ruby gem to consolidate multiple EARL report and generate a rollup conformance report.

## Description

Reads a test manifest in the
[standard RDF WG format](http://www.w3.org/2011/rdf-wg/wiki/Turtle_Test_Suite)
and generates a rollup report in RDFa+HTML.

## Test Specifications
The test manifest is presumed to be of the following form:

### Manifest Header

The manifest header looks like:

    <>  rdf:type mf:Manifest ;
        rdfs:comment "Turtle tests" ;
        mf:entries
        (
        ....
        ) .

where .... is a list of links to test descriptions, one per line.

### Test description

This is an example of a synatx test:

    <#turtle-syntax-file-01> rdf:type rdft:TestTurtlePositiveSyntax ;
       mf:name    "turtle-syntax-file-01" ;
       rdfs:comment "Further description of the test" ;
       mf:action  <turtle-syntax-file-01.ttl> ;
       mf:result  <turtle-eval-struct-01.nt> .

## Individual EARL reports

Results for individual implementations should be specified in Turtle form, but
may be specified in an any compatible RDF serialization (JSON-LD is presumed to
be a cached rollup report). The report is composed of `Assertion` declarations
in the following form:

    [ a earl:Assertion;
      earl:assertedBy <http://greggkellogg.net/foaf#me>;
      earl:subject <http://rubygems.org/gems/rdf-turtle>;
      earl:test <http://dvcs.w3.org/hg/rdf/raw-file/e80b58a1a711/rdf-turtle/tests-ttl/manifest.ttl#turtle-syntax-file-01>;
      earl:result [
        a earl:TestResult;
        earl:outcome earl:passed;
        dc:date "2012-11-17T15:19:11-05:00"^^xsd:dateTime];
      earl:mode earl:automatic ] .

Additionally, `earl:subject` is expected to reference a [DOAP]() description
of the reported software, in the following form:

    <http://rubygems.org/gems/rdf-turtle> a doap:Project, earl:TestSubject, earl:Software ;
      doap:name          "RDF::Turtle" ;
      doap:developer     <http://greggkellogg.net/foaf#me> ;
      doap:homepage      <http://ruby-rdf.github.com/rdf-turtle> ;
      doap:description   "RDF::Turtle is an Turtle reader/writer for the RDF.rb library suite."@en ;
      doap:programming-language "Ruby" .

The [DOAP]() description may be included in the [EARL]() report. If not found,
the IRI identified by `earl:subject` will be dereferenced and is presumed to
provide a [DOAP]() specification of the test subject.

The `doap:developer` is expected to reference a [FOAF]() profile for the agent
(user or organization) responsible for the test subject. It is expected to be
of the following form:

    <http://greggkellogg.net/foaf#me> foaf:name "Gregg Kellogg" .

If not found, the IRI identified by `doap:developer`
will be dereferenced and is presumed to provide a [FOAF]() profile of the developer.

## Usage

The `earl` command may be used to directly create a report from zero or more input files, which are themselves [EARL][] report.

    gem install earl-report
    
    earl \
      --output FILE     # Location for generated report
      --tempate [FILE]  # Location of report template file; returns default if not specified
      --bibRef          # The default ReSpec-formatted bibliographic reference for the report
      --name            # The name of the software being reported upon
      manifest          # one or more test manifests used to define test descriptions
      report*           # one or more EARL report in most RDF formats

## Report generation template

The report template is in ReSpec form using [Haml]() to generate individual elements.

## License

This software is licensed using [Unlicense](http://unlicense.org) and is freely available without encumbrance.

[DOAP]: https://github.com/edumbill/doap/wiki
[EARL]: http://www.w3.org/TR/EARL10-Schema/
[FOAF]: http://xmlns.com/foaf/spec/
[Haml]: http://haml.info/
