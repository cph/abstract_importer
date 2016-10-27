require "abstract_importer/strategies/insert_strategy"
require "activerecord/insert_many"

module AbstractImporter
  module Strategies
    class UpsertStrategy < InsertStrategy

      def initialize(collection, options={})
        super
        @insert_options.merge!(on_conflict: { column: remap_ids? ? :legacy_id : :id, do: :update })
      end

      # We won't skip any records for already being imported
      def already_imported?(hash)
        false
      end

    end
  end
end
