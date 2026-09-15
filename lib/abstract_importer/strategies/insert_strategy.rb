require "abstract_importer/strategies/base"

module AbstractImporter
  module Strategies
    class InsertStrategy < Base

      def initialize(collection)
        super
        @batch = []
        @batch_size = 250
      end


      def process_record(hash)
        summary.total += 1

        if already_imported?(hash)
          summary.already_imported += 1
          return
        end

        remap_foreign_keys!(hash)

        if redundant_record?(hash)
          summary.redundant += 1
          return
        end

        @batch << prepare_attributes(hash)
        flush if @batch.length >= @batch_size

      rescue ::AbstractImporter::Skip
        summary.skipped += 1
      end


      def flush
        invoke_callback(:before_batch, @batch)

        begin
          tries = (tries || 0) + 1
          insert_batch(@batch)
        rescue
          raise if tries > 1
          invoke_callback(:rescue_batch, @batch)
          retry
        end

        ids = collection.scope.where(legacy_id: @batch.map { |hash| hash[:legacy_id] })
        id_map.merge! collection.table_name, ids

        summary.created += ids.length

        @batch = []
      end


      # Rails' insert_all replaces the activerecord-insert_many gem, whose
      # reliance on adapter internals (lookup_cast_type_from_column) does not
      # survive Rails 8.1. insert_all cannot be called on a has_many :through
      # scope, so fall back to the model in that case; and it raises on an
      # empty batch where insert_many returned [].
      def insert_batch(batch)
        return if batch.empty?

        scope = collection.scope
        if scope.respond_to?(:proxy_association) && scope.proxy_association.reflection.through_reflection?
          scope = scope.klass
        end

        scope.insert_all(batch)
      end


    end
  end
end
