module MemoryRecord
  module Associations
    class SingularAssociation < Association #:nodoc:
      # Implements the reader method, e.g. foo.bar for Foo.has_one :bar
      def reader(force_reload = false)
        if !loaded? || stale_target?
          reload
        end

        target
      end

      # Implements the writer method, e.g. foo.bar= for Foo.belongs_to :bar
      def writer(record)
        replace(record)
      end

      def create(attributes = {}, &block)
        _create_record(attributes, &block)
      end

      def create!(attributes = {}, &block)
        _create_record(attributes, true, &block)
      end

      def build(attributes = {})
        record = build_record(attributes)
        yield(record) if block_given?
        set_new_record(record)
        record
      end

      private

        def create_scope
          scope.scope_for_create.stringify_keys.except(klass.primary_key)
        end

        def get_records
          scope.limit(1).records
        end

        def find_target
          if record = get_records.first
            set_inverse_instance record
          end
        end

        def replace(record)
          raise NotImplementedError, "Subclasses must implement a replace(record) method"
        end

        def set_new_record(record)
          replace(record)
        end

        def _create_record(attributes, raise_error = false)
          record = build_record(attributes)
          yield(record) if block_given?
          saved = record.save
          set_new_record(record)
          raise RecordInvalid.new(record) if !saved && raise_error
          record
        end
    end
  end
end
