module AbstractImporter
  module Strategies
    class DefaultStrategy
      attr_reader :collection

      delegate :summary,
               :already_imported?,
               :remap_foreign_keys!,
               :redundant_record?,
               :invoke_callback,
               :dry_run?,
               :id_map,
               :scope,
               :reporter,
               to: :collection

      def initialize(collection)
        @collection = collection
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

        if create_record(hash)
          summary.created += 1
        else
          summary.invalid += 1
        end
      rescue ::AbstractImporter::Skip
        summary.skipped += 1
      end


      def create_record(hash)
        record = build_record(hash)

        return true if dry_run?

        invoke_callback(:before_create, record)

        # rescue_callback has one shot to fix things
        invoke_callback(:rescue, record) unless record.valid?

        if record.valid? && record.save
          invoke_callback(:after_create, hash, record)
          id_map << record

          reporter.record_created(record)
          true
        else

          reporter.record_failed(record, hash)
          false
        end
      end

      def build_record(hash)
        hash = invoke_callback(:before_build, hash) || hash

        legacy_id = hash.delete(:id)

        scope.build hash.merge(legacy_id: legacy_id)
      end

    end
  end
end
