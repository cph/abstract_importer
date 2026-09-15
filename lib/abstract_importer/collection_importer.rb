require 'benchmark'
require "abstract_importer/strategies"

module AbstractImporter
  class CollectionImporter

    def initialize(importer, collection)
      @importer = importer
      @collection = collection
      @strategy = importer.strategy_for(collection).new(self)
    end

    attr_reader :importer, :collection, :summary, :strategy

    delegate :name,
             :table_name,
             :model,
             :scope,
             :options,
             :association_attrs,
             :to => :collection

    delegate :dry_run?,
             :parent,
             :source,
             :reporter,
             :remap_foreign_key?,
             :id_map,
             :map_foreign_key,
             :to => :importer



    def perform!
      reporter.start_collection(self)
      prepare!

      invoke_callback(:before_all)
      summary.ms = 1000 * Benchmark.realtime {
        each_new_record do |attributes|
          strategy.process_record(attributes)
        end
      }
      strategy.flush
      invoke_callback(:after_all)

      reporter.finish_collection(self, summary)
      summary
    end



    def prepare!
      @summary = Summary.new
      @mappings = prepare_mappings!
    end

    def prepare_mappings!
      mappings = []
      model.reflect_on_all_associations.each do |association|

        # We only want the associations where this record
        # has foreign keys that refer to another
        next unless association.macro == :belongs_to

        # We support skipping some mappings entirely. I believe
        # this is largely to cut down on verbosity in the log
        # files and should be refactored to another place in time.
        foreign_key = association.foreign_key.to_sym
        next unless remap_foreign_key?(name, foreign_key)

        if association.options[:polymorphic]
          mappings << prepare_polymorphic_mapping!(association)
        else
          mappings << prepare_mapping!(association)
        end
      end
      mappings
    end

    def prepare_mapping!(association)
      depends_on = association.table_name.to_sym
      foreign_key = association.foreign_key.to_sym

      Proc.new do |attrs|
        if attrs.key?(foreign_key)
          attrs[foreign_key] = map_foreign_key(attrs[foreign_key], name, foreign_key, depends_on)
        else
          reporter.count_notice "#{name}.#{foreign_key} will not be mapped because it is not used"
        end
      end
    end

    def prepare_polymorphic_mapping!(association)
      foreign_key = association.foreign_key.to_sym
      foreign_type = association.foreign_key.gsub(/_id$/, "_type").to_sym

      Proc.new do |attrs|
        if attrs.key?(foreign_key) && attrs.key?(foreign_type)
          foreign_model = attrs[foreign_type]
          depends_on = foreign_model.constantize.table_name.to_sym if foreign_model
          attrs[foreign_key] = depends_on && map_foreign_key(attrs[foreign_key], name, foreign_key, depends_on)
        else
          reporter.count_notice "#{name}.#{foreign_key} will not be mapped because it is not used"
        end
      end
    end



    def each_new_record
      source.public_send(name).each do |attrs|
        yield attrs.dup
      end
    end



    def remap_foreign_keys!(hash)
      @mappings.each do |proc|
        proc.call(hash)
      end
    end

    def redundant_record?(hash)
      existing_record = invoke_callback(:finder, hash)
      if existing_record
        id_map.register(record: existing_record, legacy_id: hash[:id])
        true
      else
        false
      end
    end



    def invoke_callback(callback, *args)
      callback_name = :"#{callback}_callback"
      callback = options.public_send(callback_name)
      return unless callback
      callback = importer.method(callback) if callback.is_a?(Symbol)
      callback.call(*args)
    end

  end

  class Skip < StandardError; end

end
