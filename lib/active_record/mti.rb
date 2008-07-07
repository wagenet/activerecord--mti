# This class inherits from ActiveRecord::Base and all MTI classes
# should subsequently inherit from id to receive MTI support.
# Children of the parent should inherit it in normal fashion.
# 
# Example:
# 
#   class Person < ActiveRecord::MTI; end
#   class Employee < Person; end
class ActiveRecord::MTI < ActiveRecord::Base
  def self.inherited(subclass) #:nodoc:
    super
    subclass.send(:include, ::MTI::ARMethods)
  end
end