require "abstract_importer/strategies/base"

module AbstractImporter
  module Strategies
    class InsertStrategy < Base

      def initialize(collection, options={})
        super
        @batch = []
        @batch_size = options.fetch(:batch_size, 250)
        @bulk_operation = options[:on_duplicate] == :update ? :upsert_all : :insert_all
        @insert_options = options.slice(:unique_by)
        @insert_options.merge!(returning: [:legacy_id, :id]) if remap_ids?
      end


      def process_record(hash)
        summary.total += 1

        if already_imported?(hash)
          summary.already_imported += 1
          reporter.record_skipped hash
          return
        end

        remap_foreign_keys!(hash)

        if redundant_record?(hash)
          summary.redundant += 1
          reporter.record_skipped hash
          return
        end

        add_to_batch prepare_attributes(hash)

      rescue ::AbstractImporter::Skip
        summary.skipped += 1
        reporter.record_skipped hash
      end


      def flush
        invoke_callback(:before_batch, @batch)

        insert_batch(@batch)

        summary.created += @batch.length
        reporter.batch_inserted(@batch.length)

        @batch = []
      end


      def insert_batch(batch)
        return if batch.empty?

        scope = collection.scope
        if scope.respond_to?(:proxy_association) && scope.proxy_association.reflection.through_reflection?
          scope = scope.klass
        end

        scope = invoke_callback(:prepare_scope, scope) || scope

        result = scope.public_send(@bulk_operation, batch, **@insert_options)
        add_batch_to_id_map(result) if remap_ids?
      end


      def add_to_batch(attributes)
        @batch << attributes
        legacy_id, id = attributes.values_at(:legacy_id, :id)
        id_map.merge! collection.table_name, legacy_id => id if id && legacy_id
        flush if @batch.length >= @batch_size
      end


      def add_batch_to_id_map(result)
        map = cast_result(result, collection.table_name).each_with_object({}) do |attrs, map|
          map[attrs.fetch("legacy_id")] = attrs.fetch("id")
        end
        id_map.merge! collection.table_name, map
      end


      def cast_result(result, table_name)
        types_by_column = result.columns.each_with_object({}) do |column_name, types|
          connection = collection.scope.connection
          column = collection.scope.columns.find { |column| column.name == column_name }

          types[column_name] = connection.respond_to?(:lookup_cast_type_from_column) ?
            connection.lookup_cast_type_from_column(column) :
            connection.lookup_cast_type(column.sql_type)
        end

        result.to_a.map { |row|
          Hash[row.map { |column_name, value|
            [ column_name, types_by_column[column_name].deserialize(value) ]
          }]
        }
      end


    end
  end
end
