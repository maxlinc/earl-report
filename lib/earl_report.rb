# EARL reporting
require 'linkeddata'
require 'sparql'
require 'haml'

##
# EARL reporting class.
# Instantiate a new class using one or more input graphs
class EarlReport
  attr_reader :graph

  MANIFEST_QUERY = %(
    PREFIX dc: <http://purl.org/dc/terms/>
    PREFIX mf: <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

    SELECT ?lh ?uri ?title ?description ?testAction ?testResult
    WHERE {
      ?uri mf:name ?title; mf:action ?testAction.
      OPTIONAL { ?uri rdfs:comment ?description. }
      OPTIONAL { ?uri mf:result ?testResult. }
      OPTIONAL { [ mf:entries ?lh] . ?lh rdf:first ?uri . }
    }
  ).freeze

  TEST_SUBJECT_QUERY = %(
    PREFIX doap: <http://usefulinc.com/ns/doap#>
    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
    
    SELECT DISTINCT ?uri ?name ?doapDesc ?homepage ?language ?developer ?devName ?devType ?devHomepage
    WHERE {
      ?uri a doap:Project; doap:name ?name .
      OPTIONAL { ?uri doap:developer ?developer .}
      OPTIONAL { ?uri doap:homepage ?homepage . }
      OPTIONAL { ?uri doap:description ?doapDesc . }
      OPTIONAL { ?uri doap:programming-language ?language . }
      OPTIONAL { ?developer foaf:name ?devName .}
      OPTIONAL { ?developer a ?devType . }
      OPTIONAL { ?developer foaf:homepage ?devHomepage . }
    }
  ).freeze

  DOAP_QUERY = %(
    PREFIX earl: <http://www.w3.org/ns/earl#>
    PREFIX doap: <http://usefulinc.com/ns/doap#>
    
    SELECT DISTINCT ?subject ?name
    WHERE {
      [ a earl:Assertion; earl:subject ?subject ] .
      OPTIONAL {
        ?subject a doap:Project; doap:name ?name
      }
    }
  ).freeze

  ASSERTION_QUERY = %(
    PREFIX earl: <http://www.w3.org/ns/earl#>
    
    SELECT ?by ?mode ?outcome ?subject ?test
    WHERE {
      [ a earl:Assertion;
        earl:assertedBy ?by;
        earl:mode ?mode;
        earl:result [earl:outcome ?outcome];
        earl:subject ?subject;
        earl:test ?test ] .
    }
    ORDER BY ?subject
  ).freeze

  TEST_CONTEXT = {
    "@vocab" =>   "http://www.w3.org/ns/earl#",
    "foaf:homepage" => {"@type" => "@id"},
    dc:           "http://purl.org/dc/terms/",
    doap:         "http://usefulinc.com/ns/doap#",
    earl:         "http://www.w3.org/ns/earl#",
    mf:           "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
    foaf:         "http://xmlns.com/foaf/0.1/",
    rdfs:         "http://www.w3.org/2000/01/rdf-schema#",
    assertedBy:   {"@type" => "@id"},
    assertions:   {"@type" => "@id", "@container" => "@list"},
    bibRef:       {"@id" => "dc:bibliographicCitation"},
    description:  {"@id" => "dc:description"},
    developer:    {"@id" => "doap:developer", "@type" => "@id", "@container" => "@set"},
    doapDesc:     {"@id" => "doap:description"},
    homepage:     {"@id" => "doap:homepage", "@type" => "@id"},
    label:        {"@id" => "rdfs:label"},
    language:     {"@id" => "doap:programming-language"},
    mode:         {"@type" => "@id"},
    name:         {"@id" => "doap:name"},
    outcome:      {"@type" => "@id"},
    subject:      {"@type" => "@id"},
    test:         {"@type" => "@id"},
    testAction:   {"@id" => "mf:action", "@type" => "@id"},
    testResult:   {"@id" => "mf:result", "@type" => "@id"},
    tests:        {"@type" => "@id", "@container" => "@list"},
    testSubjects: {"@type" => "@id", "@container" => "@list"},
    title:        {"@id" => "dc:title"}
  }.freeze

  # Convenience vocabularies
  class EARL < RDF::Vocabulary("http://www.w3.org/ns/earl#"); end
  class MF < RDF::Vocabulary("http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#"); end

  ##
  # Load test assertions and look for referenced software and developer information
  # @param [Array<String>] *files Assertions
  # @param [Hash{Symbol => Object}] options
  # @option options [Boolean] :verbose (true)
  # @option options [String] :base Base IRI for loading Manifest
  # @option options [String] :bibRef
  #   ReSpec bibliography reference for specification being tested
  # @option options [String] :json Result of previous JSON-LD generation
  # @option options [String] :manifest Test manifest
  # @option options [String] :name Name of specification
  # @option options [String] :query
  #   Query, or file containing query for extracting information from Test manifest
  def initialize(*files)
    @options = files.last.is_a?(Hash) ? files.pop.dup : {}
    @options[:query] ||= MANIFEST_QUERY
    raise "Test Manifest must be specified with :manifest option" unless @options[:manifest] || @options[:json]
    @files = files
    @prefixes = {}
    if @options[:json]
      @json_hash = ::JSON.parse(File.read(files.first))
      return
    end

    # Load manifest, possibly with base URI
    status "read #{@options[:manifest]}"
    man_opts = {}
    man_opts[:base_uri] = RDF::URI(@options[:base]) if @options[:base]
    @graph = RDF::Graph.load(@options[:manifest], man_opts)
    status "  loaded #{@graph.count} triples"

    # Read test assertion files
    files.flatten.each do |file|
      status "read #{file}"
      file_graph = RDF::Graph.load(file)
      status "  loaded #{file_graph.count} triples"
      @graph << file_graph
    end

    # Find or load DOAP descriptions for all subjects
    SPARQL.execute(DOAP_QUERY, @graph).each do |solution|
      subject = solution[:subject]

      # Load DOAP definitions
      unless solution[:name] # not loaded
        status "read doap description for #{subject}"
        begin
          doap_graph = RDF::Graph.load(subject)
          status "  loaded #{doap_graph.count} triples"
          @graph << doap_graph.to_a
        rescue
          status "  failed"
        end
      end
    end

    # Load developers referenced from Test Subjects
    SPARQL.execute(TEST_SUBJECT_QUERY, @graph).each do |solution|
      # Load DOAP definitions
      if solution[:developer] && !solution[:devName] # not loaded
        status "read description for #{solution[:developer].inspect}"
        begin
          foaf_graph = RDF::Graph.load(solution[:developer])
          status "  loaded #{foaf_graph.count} triples"
          @graph << foaf_graph.to_a
        rescue
          status "  failed"
        end
      end
    end
  end
    
  ##
  # Dump the collesced output graph
  #
  # If no `io` option is provided, the output is returned as a string
  #
  # @param [Hash{Symbol => Object}] options
  # @option options [Symbol] format (:html)
  # @option options[IO] :io
  #   Optional `IO` to output results
  # @return [String] serialized graph, if `io` is nil
  def generate(options = {})
    options = {:format => :html}.merge(options)

    io = options[:io]

    status("generate: #{options[:format]}")
    ##
    # Retrieve Hashed information in JSON-LD format
    case options[:format]
    when :jsonld, :json
      json = json_hash.to_json(JSON::LD::JSON_STATE)
      io.write(json) if io
      json
    when :turtle, :ttl
      if io
        earl_turtle(options)
      else
        io = StringIO.new
        earl_turtle(options.merge(:io => io))
        io.rewind
        io.read
      end
    when :html
      template = options[:template] ||
        File.read(File.expand_path('../earl_report/views/earl_report.html.haml', __FILE__))

      # Generate HTML report
      html = Haml::Engine.new(template, :format => :xhtml).render(self, :tests => json_hash)
      io.write(html) if io
      html
    else
      if io
        RDF::Writer.for(options[:format]).new(io) {|w| w << graph}
      else
        graph.dump(options[:format])
      end
    end
  end

  private
  
  ##
  # Return hashed EARL report in JSON-LD form
  # @return [Hash]
  def json_hash
    @json_hash ||= begin
      # Customized JSON-LD output
      {
        "@context" => TEST_CONTEXT,
        "@id"          => "",
        "@type"        => %w(earl:Software doap:Project),
        "assertions"   => @files,
        'name'         => @options[:name],
        'bibRef'       => @options[:bibRef],
        'testSubjects' => json_test_subject_info,
        'tests'        => json_result_info
      }
    end
  end

  ##
  # Return array of test subject information
  # @return [Array]
  def json_test_subject_info
    # Get the set of subjects
    @subject_info ||= begin
      ts_info = {}
      SPARQL.execute(TEST_SUBJECT_QUERY, @graph).each do |solution|
        status "solution #{solution.to_hash.inspect}"
        info = ts_info[solution[:uri].to_s] ||= {}
        %w(name doapDesc homepage language).each do |prop|
          info[prop] = solution[prop.to_sym].to_s if solution[prop.to_sym]
        end
        if solution[:devName]
          dev_type = solution[:devType].to_s =~ /Organization/ ? "foaf:Organization" : "foaf:Person"
          dev = {'@type' => dev_type}
          dev['@id'] = solution[:developer].to_s if solution[:developer].uri?
          dev['foaf:name'] = solution[:devName].to_s if solution[:devName]
          dev['foaf:homepage'] = solution[:devHomepage].to_s if solution[:devHomepage]
          (info['developer'] ||= []) << dev
        end
        info['developer'] = info['developer'].uniq
      end

      # Map ids and values to array entries
      ts_info.keys.sort.map do |id|
        info = ts_info[id]
        subject = Hash.ordered
        subject["@id"] = id
        subject["@type"] = %w(earl:TestSubject doap:Project)
        %w(name developer doapDesc homepage language).each do |prop|
          subject[prop] = info[prop] if info[prop]
        end
        subject
      end
    end
  end

  ##
  # Return result information for each test.
  # This counts on hash maintaining insertion order
  #
  # @return [Array]
  def json_result_info
    test_cases = {}
    subjects = json_test_subject_info.map {|s| s['@id']}

    # Hash test cases by URI
    solutions = SPARQL.execute(@options[:query], @graph)
      .to_a
      .inject({}) {|memo, soln| memo[soln[:uri]] = soln; memo}

    # If test cases are in a list, maintain order
    solution_list = if first_soln = solutions.values.detect {|s| s[:lh]}
      RDF::List.new(first_soln[:lh], @graph)
    else
      solutions.keys  # Any order will do
    end

    # Collect each TestCase
    solution_list.each do |uri|
      solution = solutions[uri]
      tc_hash = {
        '@id' => uri.to_s,
        '@type' => %w(earl:TestCriterion earl:TestCase),
        'title' => solution[:title].to_s,
        'testAction' => solution[:testAction].to_s,
        'assertions' => []
      }
      tc_hash['description'] = solution[:description].to_s if solution[:description]
      tc_hash['testResult'] = solution[:testResult].to_s if solution[:testResult]
      
      # Pre-initialize results for each subject to untested
      subjects.each do |siri|
        tc_hash['assertions'] << {
          '@type' => 'earl:Assertion',
          'test'    => uri.to_s,
          'subject' => siri,
          'result' => {
            '@type' => 'earl:TestResult',
            'outcome' => 'earl:untested'
          }
        }
      end

      test_cases[uri.to_s] = tc_hash
    end

    raise "No test cases found" if test_cases.empty?

    status "Test cases:\n  #{test_cases.keys.join("\n  ")}"
    # Iterate through assertions and add to appropriate test case
    SPARQL.execute(ASSERTION_QUERY, @graph).each do |solution|
      tc = test_cases[solution[:test].to_s]
      STDERR.puts "No test case found for #{solution[:test]}: #{tc.inspect}" unless tc
      subject = solution[:subject].to_s
      result_index = subjects.index(subject)
      ta_hash = tc['assertions'][result_index]
      ta_hash['assertedBy'] = solution[:by].to_s
      ta_hash['mode'] = "earl:#{solution[:mode].to_s.split('#').last || 'automatic'}"
      ta_hash['result']['outcome'] = "earl:#{solution[:outcome].to_s.split('#').last}"
    end

    test_cases.values
  end

  ##
  # Output consoloated EARL report as Turtle
  # @param [IO, StringIO] io
  # @return [String]
  def earl_turtle(options)
    io = options[:io]
    # Write preamble
    {
      :dc       => RDF::DC,
      :doap     => RDF::DOAP,
      :earl     => EARL,
      :foaf     => RDF::FOAF,
      :mf       => MF,
      :owl      => RDF::OWL,
      :rdf      => RDF,
      :rdfs     => RDF::RDFS,
      :xhv      => RDF::XHV,
      :xsd      => RDF::XSD
    }.each do |prefix, vocab|
      io.puts("@prefix #{prefix}: <#{vocab.to_uri}> .")
    end
    io.puts

    # Write earl:Software for the report
    io.puts %{<#{json_hash['@id']}> a earl:Software, doap:Project;}
    io.puts %{  doap:homepage <#{json_hash['homepage']}>;}
    io.puts %{  doap:name "#{json_hash['name']}";}
    io.puts %{  dc:bibliographicCitation "#{json_hash['bibRef']}";}
    io.puts %{  earl:assertions\n}
    io.puts %{    } + json_hash['assertions'].map {|a| as_resource(a)}.join(",\n    ") + ';'
    io.puts %{  earl:testSubjects (\n}
    io.puts %{    } + json_hash['testSubjects'].map {|a| as_resource(a['@id'])}.join("\n    ") + ');'
    io.puts %{  earl:tests (\n}
    io.puts %{    } + json_hash['tests'].map {|a| as_resource(a['@id'])}.join("\n    ") + ') .'

    # Test Cases
    # also collect each assertion definition
    test_cases = {}
    assertions = []

    # Write out each earl:TestSubject
    io.puts %(#\n# Subject Definitions\n#)
    json_hash['testSubjects'].each do |ts_desc|
      io.write(test_subject_turtle(ts_desc))
    end
    
    # Write out each earl:TestCase
    io.puts %(#\n# Test Case Definitions\n#)
    json_hash['tests'].each do |test_case|
      io.write(tc_turtle(test_case))
    end
  end
  
  ##
  # Write out Test Subject definition for each earl:TestSubject
  # @param [Hash] desc
  # @return [String]
  def test_subject_turtle(desc)
    res = %(<#{desc['@id']}> a #{desc['@type'].join(', ')};\n)
    res += %(  doap:name "#{desc['name']}";\n)
    res += %(  doap:description """#{desc['doapDesc']}""";\n)     if desc['doapDesc']
    res += %(  doap:programming-language "#{desc['language']}";\n) if desc['language']
    res += %( .\n\n)

    [desc['developer']].flatten.each do |developer|
      if developer['@id']
        res += %(<#{desc['@id']}> doap:developer <#{developer['@id']}> .\n\n)
        res += %(<#{developer['@id']}> a #{[developer['@type']].flatten.join(', ')};\n)
        res += %(  foaf:homepage <#{developer['foaf:homepage']}>;\n) if developer['foaf:homepage']
        res += %(  foaf:name "#{developer['foaf:name']}" .\n\n)
      else
        res += %(<#{desc['@id']}> doap:developer\n)
        res += %(   [ a #{developer['@type'] || "foaf:Person"};\n)
        res += %(     foaf:homepage <#{developer['foaf:homepage']}>;\n) if developer['foaf:homepage']
        res += %(     foaf:name "#{developer['foaf:name']}" ] .\n\n)
      end
    end
    res + "\n"
  end
  
  ##
  # Write out each Test Case definition
  # @prarm[Hash] desc
  # @return [String]
  def tc_turtle(desc)
    res = %{#{as_resource desc['@id']} a #{[desc['@type']].flatten.join(', ')};\n}
    res += %{  dc:title "#{desc['title']}";\n}
    res += %{  dc:description """#{desc['description']}""";\n} if desc.has_key?('description')
    res += %{  mf:result #{as_resource desc['testResult']};\n} if desc.has_key?('testResult')
    res += %{  mf:action #{as_resource desc['testAction']};\n}
    res += %{  earl:assertions (\n}
    desc['assertions'].each do |as_desc|
      res += as_turtle(as_desc)
    end
    res += %{  ) .\n\n}
  end

  ##
  # Write out each Assertion definition
  # @prarm[Hash] desc
  # @return [String]
  def as_turtle(desc)
    res =  %(    [ a earl:Assertion;\n)
    res += %(      earl:assertedBy #{as_resource desc['assertedBy']};\n) if desc['assertedBy']
    res += %(      earl:test #{as_resource desc['test']};\n)
    res += %(      earl:subject #{as_resource desc['subject']};\n)
    res += %(      earl:mode #{desc['mode']};\n) if desc['mode']
    res += %(      earl:result [ a earl:TestResult; earl:outcome #{desc['result']['outcome']} ]]\n)
  end
  
  def as_resource(resource)
    resource[0,2] == '_:' ? resource : "<#{resource}>"
  end

  def status(message)
    puts message if @options[:verbose]
  end
end
