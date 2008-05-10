# This module contains changes to AR HasManyAssociation necessary for MTI
module MTI::Associations
  module JoinBase
    def self.extend_object(base)
      base.class_eval do
        def column_names_with_alias
          unless @column_names_with_alias
            @column_names_with_alias = []
            temp_column_names = column_names
            temp_column_names += @active_record.mti_column_names if @active_record.respond_to? :mti_column_names
            ([primary_key] + (temp_column_names - [primary_key])).each_with_index do |column_name, i|
              @column_names_with_alias << [column_name, "#{ aliased_prefix }_r#{ i }"]
            end
          end
          return @column_names_with_alias
        end
      end
    end
  end
  
  module JoinAssociation
    def self.extend_object(base)
      base.class_eval do
        def association_join_with_mti(*args)
          join = association_join_without_mti(*args)
          
          if reflection.klass.respond_to?(:construct_mti_from)
            connection = reflection.active_record.connection

            join.gsub!("#{join_type} #{connection.quote_table_name(aliased_table_name)}",
                       "#{join_type} #{reflection.klass.construct_mti_from(aliased_table_name)}")
          end
          
          join
        end
        alias_method_chain :association_join, :mti
      end
    end
  end

  module HasManyThroughAssociation
    def self.extend_object(base)
      base.class_eval do
        # Correct the joins for MTI
        def construct_joins_with_mti(*args)
          joins = construct_joins_without_mti(*args)
          
          if @reflection.klass.respond_to?(:construct_mti_from)                 
            joins.gsub!("FROM #{@reflection.table_name}", "FROM #{@reflection.klass.construct_mti_from}")
          end
          
          joins
        end
        alias_method_chain :construct_joins, :mti
      end
    end
  end
end

ActiveRecord::Associations::ClassMethods::JoinDependency::JoinBase.send :extend, MTI::Associations::JoinBase
ActiveRecord::Associations::ClassMethods::JoinDependency::JoinAssociation.send :extend, MTI::Associations::JoinAssociation

# Is this necessary?
# ActiveRecord::Associations::HasManyThroughAssociation.send :extend, MTI::Associations::HasManyThroughAssociation