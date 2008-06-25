# All the custom MTI methods are included in this module.
module MTI::ARMethods
  def self.included(base) #:nodoc:
    base.class_eval do
      extend ClassMethods
    
      # Include certain modules and callbacks only on MTI children
      if base.superclass == ActiveRecord::MTI
        extend ParentClassMethods
      else        
        extend ChildClassMethods
        include ChildInstanceMethods
        
        after_create :mti_create
        after_update :mti_update
        after_destroy :mti_destroy
      end
    end
  end

  # Class methods for all MTI related classes
  module ClassMethods
    
    # Overwrites AR::Base#descends_from_active_record?
    # 
    # True if this isn't a concrete subclass needing a STI / MTI type condition.
    def descends_from_active_record?
      if superclass.abstract_class?
        superclass.descends_from_active_record?
      else
        [ActiveRecord::Base, ActiveRecord::MTI].include?(superclass) || !columns_hash.include?(inheritance_column)
      end
    end
    
    protected
      # Overwrites AR::Base#class_of_active_record_descendant
      # 
      # Returns the base AR::MTI subclass that this class descends from. If A
      # extends AR::MTI, A.base_class will return A. If B descends from A
      # through some arbitrarily deep hierarchy, B.base_class will return A.
      def class_of_active_record_descendant(klass)
        klass.superclass == ActiveRecord::MTI ? klass : super(klass)
      end
  end

  # Class methods for inclusion in any MTI parent classes
  module ParentClassMethods
=begin
# Removed because it breaks inheritance
    # Forces loading of MTI subclasses. Necessary for proper function of finder methods
    # and possibly others
    # 
    # Example:
    # 
    #   class Person < ActiveRecord::MTI
    #     mti_subclasses :employee
    #   end
    #   class Employee < Person; end
    def mti_subclasses(*class_ids)
      class_ids.each{|class_id| require_dependency class_id.to_s }
    end
=end
    
    # Overwrites ActiveRecord::Base#find with two helps:
    # 1. Optionally limit the results by subclass
    # Example:
    # 
    #   Person.find(:first, :subclass => :employee)
    #   # Equivalent to
    #   Employee.find(:first)
    # 
    # 2. If it finds a subclass, reload to get additional variables
    def find(*args)
      if self.superclass == ActiveRecord::MTI
        options = args.extract_options!
        if options[:subclass]
          # TODO: Make this a real exception
          subclass = options.delete(:subclass).to_s.classify.constantize
          args << options
          return subclass.find(*args)
        end
        args << options
      end

      # Reload with proper class if necessary
      found = super(*args)
      found = found.class.find(*args) if found.is_a?(ActiveRecord::Base) && found.class.base_class == self
      found
    end
  end

  # Class methods for inclusion in any MTI subclasses
  module ChildClassMethods
    # Guesses the child table name (in forced lower-case) based on the name of 
    # the current class. The rules used to do the guess are handled by the Inflector class
    # in Active Support, which knows almost all common English inflections. You can add new 
    # inflections in config/initializers/inflections.rb.
    # 
    #   class Person < ActiveRecord::MTI; end;
    #   class Employee < Person; end;
    #   file                  class               mti_table_name
    #   employee.rb           Employee            employees
    # 
    # You can also overwrite this class method to allow for unguessable
    # links, such as a Mouse class with a link to a "mice" table. Example:
    #
    #   class Animal < ActiveRecord::MTI; end
    #   class Mouse < Animal
    #     set_mti_table_name "mice"
    #   end
    def mti_table_name
      name = undecorated_table_name(self.name)
      set_mti_table_name(name)
      name
    end
  
    # Defines the MTI primary key field based on the name of the class in 
    # the inheritance hierarchy descending directly from ActiveRecord::MTI.
    # 
    # You can also overwrite this class method to allow for custom links.
    # 
    # Example:
    # 
    #   class ApplicationPerson < ActiveRecord::MTI; end
    #   class Employee < ApplicationPerson
    #     set_mti_primary_key "person_id"
    #   end
    def mti_primary_key
      key = Inflector.foreign_key(base_class.name)
      set_mti_primary_key(key)
      key
    end
  
    # Sets the MTI table name to use to the given value, or (if the value
    # is nil or false) to the value returned by the given block.
    #
    # Example:
    #
    #   class Task < ActiveRecord::MTI; end
    #   class Project < Task
    #     set_mti_table_name "project"
    #   end
    def set_mti_table_name(value = nil, &block)
      define_attr_method :mti_table_name, value, &block
    end
    alias :mti_table_name= :set_mti_table_name

    # Sets the MTI primary key to use to the given value, or (if the value
    # is nil or false) to the value returned by the given block.
    #
    # Example:
    #
    #   class ApplicationPerson < ActiveRecord::MTI; end
    #   class Employee < ApplicationPerson
    #     set_mti_primary_key "person_id"
    #   end
    def set_mti_primary_key(value = nil, &block)
      define_attr_method :mti_primary_key, value, &block
    end
    alias :mti_primary_key= :set_mti_primary_key
  
    # Returns an array of column objects for the table associated with this MTI subclass.
    def mti_columns
      unless @mti_columns
        @mti_columns = connection.columns(mti_table_name, "#{name} Columns")
        @mti_columns.each {|column| column.primary = column.name == mti_primary_key}
      end
      @mti_columns
    end

    # Returns a hash of column objects for the table associated with this MTI subclass.
    def mti_columns_hash
      @mti_columns_hash ||= mti_columns.inject({}) { |hash, column| hash[column.name] = column; hash }
    end
    
    # Returns an array of column names as strings associated with this MTI subclass.
    def mti_column_names
      @mti_column_names ||= mti_columns.map { |column| column.name }
    end
  
    # Overwrites ActiveRecord::AttributeMethods#define_attribute_methods
    # 
    # generates all the attribute related methods for columns in the database, including
    # MTI table columns
    # accessors, mutators and query methods
    def define_attribute_methods
      return if generated_methods?
      columns_hash.merge(mti_columns_hash).each do |name, column| # Only this line is changed
        unless instance_method_already_implemented?(name)
          if self.serialized_attributes[name]
            define_read_method_for_serialized_attribute(name)
          else
            define_read_method(name.to_sym, name, column)
          end
        end

        unless instance_method_already_implemented?("#{name}=")
          define_write_method(name.to_sym)
        end

        unless instance_method_already_implemented?("#{name}?")
          define_question_method(name)
        end
      end
    end

    # A quoted version of the mti_table_name for use in SQL queries
    def quoted_mti_table_name
      self.connection.quote_table_name(mti_table_name)
    end
    
    def construct_mti_from(alias_table_name = table_name)
      "(SELECT * FROM %s INNER JOIN %s ON %s.%s = %s.%s) AS %s" % [
          quoted_table_name,
          quoted_mti_table_name,
          quoted_mti_table_name,
            connection.quote_column_name(mti_primary_key),
          quoted_table_name,
            connection.quote_column_name(primary_key),
          connection.quote_table_name(alias_table_name)
        ]
    end
    
    private
      def mti_replace_sql_from(sql)
        sql.gsub(/FROM (#{table_name}|#{connection.quote_table_name(table_name)})/,
                 "FROM #{construct_mti_from}")
      end
    
      def construct_finder_sql(*args)
        mti_replace_sql_from(super(*args))
      end
    
      def construct_calculation_sql(*args)
        mti_replace_sql_from(super(*args))
      end
      
      def construct_finder_sql_with_included_associations(*args)
        mti_replace_sql_from(super(*args))        
      end
  end

  # Instance methods for inclusion in MTI subclasses
  module ChildInstanceMethods
    # Overwrites ActiveRecord::Base#initialize to accept MTI subclass attributes as well. Behaves
    # identically to its parent in all other ways
    def initialize(attributes = nil)
      @attributes = attributes_from_column_definition
      @attributes.merge!(attributes_from_mti_column_definition) # Only this line was added
      @attributes_cache = {}
      @new_record = true
      ensure_proper_type
      self.attributes = attributes unless attributes.nil?
      self.class.send(:scope, :create).each { |att,value| self.send("#{att}=", value) } if self.class.send(:scoped?, :create)
      result = yield self if block_given?
      callback(:after_initialize) if respond_to_without_attributes?(:after_initialize)
      result
    end

    # Initializes the attributes array with keys matching the columns from the mti subclass table 
    # and the values matching the corresponding default value of that column, so
    # that a new instance, or one populated from a passed-in Hash, still has all the attributes
    # that instances loaded from the database would.
    def attributes_from_mti_column_definition
      self.class.mti_columns.inject({}) do |attributes, column|
        attributes[column.name] = column.default unless column.name == self.class.primary_key
        attributes
      end
    end

    # Returns a copy of the attributes hash where all the values have been safely quoted for use in
    # an SQL statement. Support columns from the MTI subclass table.
    def mti_attributes_with_quotes(include_primary_key = true, include_readonly_attributes = true)
      quoted = attributes.inject({}) do |quoted, (name, value)|
        if column = mti_column_for_attribute(name)
          quoted[name] = quote_value(value, column) unless !include_primary_key && column.primary
        end
        quoted
      end
      include_readonly_attributes ? quoted : remove_readonly_attributes(quoted)
    end

    # Returns the column object for the named attribute in the MTI subclass table
    def mti_column_for_attribute(name)
      self.class.mti_columns_hash[name.to_s]
    end

    # An after_create callback that creates the corresponding MTI subclass table entry
    def mti_create
      self.send("#{self.class.mti_primary_key}=", self.id)

      quoted_attributes = mti_attributes_with_quotes

      statement = if quoted_attributes.empty?
        connection.empty_insert_statement(self.class.quoted_mti_table_name)
      else
        "INSERT INTO #{self.class.quoted_mti_table_name} " +
        "(#{quoted_column_names(mti_attributes_with_quotes).join(', ')}) " +
        "VALUES(#{quoted_attributes.values.join(', ')})"
      end

      connection.insert(statement, "#{self.class.name} Create",
        self.class.mti_primary_key, self.id, self.class.sequence_name)
    end

    # An after_update callback that updates the corresponding MTI subclass table entry
    def mti_update
      quoted_attributes = mti_attributes_with_quotes(false, false)
      return 0 if quoted_attributes.empty?
      connection.update(
        "UPDATE #{self.class.quoted_mti_table_name} " +
        "SET #{quoted_comma_pair_list(connection, quoted_attributes)} " +
        "WHERE #{connection.quote_column_name(self.class.mti_primary_key)} = #{quote_value(id)}",
        "#{self.class.name} Update"
      )
    end

    # An after_delete callback that deletes the corresponding MTI subclass table entry
    def mti_destroy
      unless new_record?
        connection.delete <<-end_sql, "#{self.class.name} Destroy"
          DELETE FROM #{self.class.quoted_mti_table_name}
          WHERE #{connection.quote_column_name(self.class.mti_primary_key)} = #{quoted_id}
        end_sql
      end
    end
  end
end