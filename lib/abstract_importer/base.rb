require "benchmark"
require "active_support/core_ext/module/delegation"
require "abstract_importer/import_options"
require "abstract_importer/import_plan"
require "abstract_importer/reporters"
require "abstract_importer/collection"
require "abstract_importer/collection_importer"
require "abstract_importer/id_map"
require "abstract_importer/summary"


module AbstractImporter
  class IdNotMappedError < StandardError; end
  class Base

    class << self
      def import
        yield @import_plan = ImportPlan.new
      end

      def depends_on(*dependencies)
        @dependencies = dependencies
      end

      def dependencies
        read_inheritable_instance_variable(:@dependencies) || []
      end

      def import_plan
        read_inheritable_instance_variable(:@import_plan)
      end

    private

      def read_inheritable_instance_variable(ivar)
        klass = self
        until klass.instance_variable_defined?(ivar)
          klass = klass.superclass
          return if klass == AbstractImporter::Base
        end
        klass.instance_variable_get(ivar)
      end

    end



    def initialize(parent, source, options={})
      @parent       = parent
      @source       = source
      @options      = options

      io            = options.fetch(:io, $stderr)
      @reporter     = default_reporter(options, io)
      @dry_run      = options.fetch(:dry_run, false)

      id_map        = options.fetch(:id_map, true)
      @import_plan  = self.class.import_plan.to_h
      @atomic       = options.fetch(:atomic, false)
      @strategies   = options.fetch(:strategy, {})
      @generate_id  = options[:generate_id]
      @skip         = Array(options[:skip])
      @only         = Array(options[:only]) if options.key?(:only)
      @collections  = []

      @use_id_map, @id_map = id_map.is_a?(IdMap) ? [true, id_map] : [id_map, IdMap.new]

      verify_source!
      verify_parent!
      instantiate_collections!

      @collection_importers = []
      collections.each do |collection|
        next if skip? collection
        @collection_importers.push CollectionImporter.new(self, collection)
      end
    end

    attr_reader :source,
                :parent,
                :reporter,
                :id_map,
                :collections,
                :import_plan,
                :skip,
                :only,
                :collection_importers,
                :options,
                :generate_id

    def use_id_map_for?(collection)
      collection = find_collection(collection) if collection.is_a?(Symbol)
      return false unless collection
      @use_id_map && collection.has_legacy_id?
    end

    def atomic?
      @atomic
    end

    def dry_run?
      @dry_run
    end





    def perform!
      {}.tap do |results|
        reporter.start_all(self)

        setup_ms = benchmark do
          setup
        end
        reporter.finish_setup(self, setup_ms)

        ms = benchmark do
          with_transaction do
            collection_importers.each do |importer|
              results[importer.name] = importer.perform!
            end
          end
        end

        teardown_ms = benchmark do
          teardown
        end
        reporter.finish_teardown(self, teardown_ms)

        reporter.finish_all(self, setup_ms + ms + teardown_ms)
      end
    end

    def setup
      prepopulate_id_map!
    end

    def count_collection(collection)
      collection_name = collection.respond_to?(:name) ? collection.name : collection
      collection_counts[collection_name]
    end

    def collection_counts
      @collection_counts ||= Hash.new do |counts, collection_name|
        counts[collection_name] = if source.respond_to?(:"#{collection_name}_count")
          source.public_send(:"#{collection_name}_count")
        else
          source.public_send(collection_name).count
        end
      end
    end

    def teardown
    end

    def skip?(collection)
      collection_name = collection.respond_to?(:name) ? collection.name : collection
      return true if skip.member?(collection_name)
      return true if only && !only.member?(collection_name)
      false
    end

    def strategy_for(collection_importer)
      collection = collection_importer.collection
      strategy_name = @strategies.fetch collection.name, :default
      strategy_options = {}
      if strategy_name.is_a?(Hash)
        strategy_options = strategy_name
        strategy_name = strategy_name[:name]
      end
      strategy_klass = AbstractImporter::Strategies.const_get :"#{strategy_name.capitalize}Strategy"
      strategy_klass.new(collection_importer, strategy_options)
    end





    def describe_source
      source.to_s
    end

    def describe_destination
      parent.to_s
    end





    def remap_foreign_key?(plural, foreign_key)
      true
    end

    def map_foreign_key(legacy_id, plural, foreign_key, depends_on)
      return nil if legacy_id.nil?
      return legacy_id unless use_id_map_for?(depends_on)
      id_map.apply!(depends_on, legacy_id)
    rescue KeyError
      raise IdNotMappedError, "#{plural}.#{foreign_key} will be nil: a #{depends_on.to_s.singularize} with the legacy id #{legacy_id} was not mapped."
    end




  protected

    def scope_for(collection_name)
      parent.public_send(collection_name).unscope(:order)
    end

  private

    def has_scope_for?(collection_name)
      scope_for(collection_name)
      true
    rescue NoMethodError
      false
    end

    def verify_source!
      import_plan.keys.each do |collection|
        next if source.respond_to?(collection)

        raise "#{source.class} does not respond to `#{collection}`; " <<
              "but #{self.class} plans to import records with that name"
      end
    end

    def verify_parent!
      import_plan.keys.each do |collection|
        next if has_scope_for?(collection)

        raise "#{parent.class} does not have a collection named `#{collection}`; " <<
              "but #{self.class} plans to import records with that name"
      end

      self.class.dependencies.each do |collection|
        next if has_scope_for?(collection)

        raise "#{parent.class} does not have a collection named `#{collection}`; " <<
              "but #{self.class} declares it as a dependency"
      end
    end

    def instantiate_collections!
      @collections = import_plan.map do |name, block|
        options = ImportOptions.new
        instance_exec(options, &block) if block

        Collection.new(name, scope_for(name), options)
      end
    end

    def dependencies
      @dependencies ||= self.class.dependencies.map do |name|
        Collection.new(name, scope_for(name))
      end
    end

    def find_collection(name)
      collections.find { |collection| collection.name == name } ||
      dependencies.find { |collection| collection.name == name }
    end

    def prepopulate_id_map!
      (collections + dependencies).each do |collection|
        next unless use_id_map_for?(collection)
        prepopulate_id_map_for!(collection)
      end
    end

    def prepopulate_id_map_for!(collection)
      id_map.init collection.table_name, collection.scope
    end



    def with_transaction(&block)
      if atomic?
        ActiveRecord::Base.transaction(requires_new: true, &block)
      else
        block.call
      end
    end

    def default_reporter(options, io)
      reporter = options.fetch(:reporter, ENV["IMPORT_REPORTER"])
      return reporter if reporter.is_a?(AbstractImporter::Reporters::BaseReporter)

      case reporter.to_s.downcase
      when "none"        then Reporters::NullReporter.new(io)
      when "performance" then Reporters::PerformanceReporter.new(io)
      when "debug"       then Reporters::DebugReporter.new(io)
      when "dot"         then Reporters::DotReporter.new(io)
      else
        if ENV["RAILS_ENV"] == "production"
          Reporters::DebugReporter.new(io)
        else
          Reporters::DotReporter.new(io)
        end
      end
    end

    def benchmark
      Benchmark.realtime { yield } * 1_000
    end

  end
end
