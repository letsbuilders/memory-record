module MemoryRecord
  class NoIdError < Exception
    def initialize(object)
      super "Cannot store object #{object} - missing id."
    end
  end
  class Store
    def initialize
      @internal_lock = Mutex.new
      @store = Hash.new
    end

    def synchronize
      @internal_lock.synchronize do
        yield
      end
    end

    def clean_store
      synchronize do
        @store = Hash.new
      end
    end

    def name
      nil
    end
  end

  class ObjectStore < Store
    attr_reader :clazz
    def initialize(clazz)
      @clazz = clazz
      @foreign_keys = Hash.new
      @index_list = Hash.new
      @name = clazz.to_s.underscore.gsub('/', '.')
      super()
    end

    def clean_store
      super
      synchronize do
        @foreign_keys.keys.each do |key|
          @foreign_keys[key] = Hash.new
        end
      end
    end

    # Store object
    # @return [Object]
    def store(object)
      id = object.send id_key
      raise NoIdError.new(object) unless id
      synchronize do
        if @store[id]
          @store[id] = object
          _update_fk_for object
        else
          @store[id] = object
          @foreign_keys.keys.each do |key|
            add_fk_index(key, object)
          end
        end
      end
    end

    def name
      @name
    end

    # @return [Object]
    def get(object_id)
      synchronize do
        @store[object_id]
      end
    end

    # @return [Array]
    def get_with_fk(key_name, key_id)
      synchronize do
        @foreign_keys[key_name][key_id] || []
      end
    end

    #@return [Hash]
    def get_fk_index(key_name)
      synchronize do
        @foreign_keys[key_name] || Hash.new
      end
    end

    # Add index for foreign key
    # @return [NilClass]
    def foreign_key(name)
      synchronize do
        @foreign_keys[name.to_sym] ||= Hash.new
      end
      reindex name.to_sym
      nil
    end

    def foreign_key?(name)
      synchronize do
        !!@foreign_keys[name.to_sym]
      end
    end

    # @return [Object, NilClass]
    def remove_object(object)
      synchronize do
        id = object.send id_key
        @index_list.delete id
        @foreign_keys.keys.each do |key|
          fk_id = object.send key
          if fk_id
            @foreign_keys[key][fk_id] ||= Array.new
            @foreign_keys[key][fk_id].delete object
          end
        end
        @store.delete object.send(id_key)
      end
    end

    alias_method :remove, :remove_object

    # @return [Array<Object>]
    def all
      synchronize do
        @store.values
      end
    end

    # @return [String]
    def to_s
      "Store for #{@clazz}. Stored objects: #{ @store.keys }"
    end

    def ids
      synchronize do
        @store.keys
      end
    end

    def update_fk_for(object)
      synchronize do
        _update_fk_for object
      end
    end

    private

    def reindex(foreign_key)
      synchronize do
        @store.values.each do |object|
          add_fk_index foreign_key, object
        end
      end
    end

    def add_fk_index(key, object)
      fk_id = object.send key
      id = object.send id_key
      if fk_id
        @foreign_keys[key][fk_id] ||= Array.new
        @foreign_keys[key][fk_id] << object
        @index_list[id] ||= Hash.new
        @index_list[id][key]=fk_id
      end
    end

    def _update_fk_for(object)
      id = object.send id_key
      if @index_list[id] && @index_list[id].any?
        @index_list[id].each do |fk, old_value|
          current_value = object.send fk
          unless current_value == old_value
            MemoryRecord.logger.debug "Updating fk #{fk} from #{old_value} to #{current_value}"
            @foreign_keys[fk][old_value] ||= Array.new
            @foreign_keys[fk][old_value].delete object
            @foreign_keys[fk][current_value] ||=Array.new
            @foreign_keys[fk][current_value] << object unless @foreign_keys[fk][current_value].include?(object)
          end
        end
      end
    end

    def id_key
       if @clazz.respond_to?(:id_key) && @clazz.id_key
        @clazz.id_key
      elsif @clazz.respond_to?(:primary_key) && @clazz.primary_key
        @clazz.primary_key
      else
        :id
      end || :id
    end
  end

  class MainStore < Store
    def store(object)
      synchronize do
        @store[object.class] ||= ObjectStore.new(object.class)
        @store[object.class].store(object)
      end
    end

    def get_object(clazz, id)
      synchronize do
        @store[clazz] ||= ObjectStore.new(clazz)
        @store[clazz].get(id)
      end
    end

    def get_store_for(clazz)
      synchronize do
        @store[clazz] ||= ObjectStore.new(clazz)
        @store[clazz]
      end
    end

    def remove(object)
      synchronize do
        @store[object.class] ||= ObjectStore.new(object.class)
        @store[object.class].remove(object)
      end
    end

    def to_s
      @store.values.map(&:to_s).join("\n")
    end
  end

  class CrossJoinStore < Store
    def self.derive_join_store_name(first_store, second_store) # :nodoc:
      [first_store.to_s, second_store.to_s].sort.join("\0").gsub(/^(.*_)(.+)\0\1(.+)/, '\1\2_\3').tr("\0", "_")
    end
  end
end
