module MemoryRecord
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
  end

  class ObjectStore < Store
    def initialize(clazz)
      @clazz = clazz
      @foreign_keys = Hash.new
      super
    end

    # Store object
    # @return [Object]
    def store(object)
      id = object.send id_key
      synchronize do
        @store[id] = object
        @foreign_keys.keys.each do |key|
          add_fk_index(key, object)
        end
      end
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

    def foreign_key(name)
      synchronize do
        @foreign_keys[name.to_sym] ||= Hash.new
      end
      reindex name.to_sym
    end

    def remove_object(object)
      synchronize do
        @foreign_keys.keys.each do |key|
          fk_id = object.send key
          if fk_id
            @foreign_keys[key][fk_id] ||= Array.new
            @foreign_keys[key][fk_id].delete object
          end
        end
      end
    end

    alias_method :remove, :remove_object

    def all
      synchronize do
        @store.values
      end
    end

    def to_s
      "Store for #{@clazz}. Stored objects: #{ @store.keys }"
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
      if fk_id
        @foreign_keys[key][fk_id] ||= Array.new
        @foreign_keys[key][fk_id] << object
      end
    end

    def id_key
      if @clazz.respond_to?(:id_key) && @clazz.id_key
        @clazz.id_key.to_sym
      elsif @clazz.respond_to?(:primary_key) && @clazz.primary_key
        @clazz.primary_key.to_sym
      else
        :id
      end
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
  end
end
