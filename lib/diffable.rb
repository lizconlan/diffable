require "diffable/version"

# :main: README.rdoc

##
# Diffable provides a mixin that can be used to extend any ActiveRecord object 
# to provide diff functionality. Calling the diff method compares the receiver 
# against another object and returns a Hash of differences found (presented as 
# a description of the changes between the second object and the receiver - as 
# if trying to restore the calling object from its replacement).

module Diffable
  def self.included base # :nodoc:
    base.send :include, InstanceMethods
    base.extend ClassMethods
  end
  
  module InstanceMethods
    ##
    # Produces a Hash containing the differences between the calling object
    # and the object passed in as a parameter
    def diff(other)
      check_class_compatibility(self, other)
      
      self_attribs = self.get_attributes(self.class.excluded_fields)
      other_attribs = other.get_attributes(other.class.excluded_fields)
      
      change = compare_objects(self_attribs, other_attribs, self, other)
      
      #the last bit - no change, no report; simples
      if other.class.conditional_fields
        other.class.conditional_fields.each do |key|
          change[key.to_sym] = eval("other.#{key}") unless change.empty?
        end
      end
      change
    end
    
    ##
    # Fetches the attributes of the calling object, exluding the +id+ field 
    # and any fields specified passed as an array of symbols via the +excluded+
    # parameter
    def get_attributes(excluded)
      attribs = attributes.dup
      attribs.delete_if { |key, value|
        (!excluded.nil? and excluded.include?(key)) or key == "id" }
    end
    
    ##
    # Uses reflection to fetch the eligible associated objects for the current 
    # object, excluding parent objects and child objects that do not include
    # the Diffable mixin
    def reflected_names(obj)
      classes = obj.reflections
      class_names = []
      classes.each do |key, cl|
        if eval(cl.class_name).respond_to?("diffable") \
           and cl.association_class != ActiveRecord::Associations::BelongsToAssociation
          class_names << key
        end
      end
      class_names
    end
    
    private
    
    def check_class_compatibility(current, other)
      current_super = current.class.superclass
      other_super = other.class.superclass
      if current_super == ActiveRecord::Base || other_super == ActiveRecord::Base
        if other.class != current.class && other.class != current_super && other_super != current.class
          raise "Unable to compare #{current.class} to #{other.class}"
        end
      else
        if current.class != other.class && other.class.superclass != current.class.superclass
          raise "Unable to compare #{current.class} to #{other.class}"
        end
      end
    end
    
    def find_in_array_by_ident(arr, value)
      arr.select { |x| eval(%Q|x.#{x.class.unique_within_group}|) == value }.first
    end
    
    def map_obj_idents(obj)
      obj.map { |x| x.attributes[x.class.unique_within_group] }
    end
    
    def ident_in_list?(ident, ident_list)
      return true if ident_list.include?(ident)
      false
    end
    
    def compare_current_subs(current_obj_idents, previous_obj_idents, current_subs, previous_subs)
      objects = []
      current_obj_idents.each do |idnt|
        current_sub = find_in_array_by_ident(current_subs, idnt)
        previous_sub = find_in_array_by_ident(previous_subs, idnt)
        
        if ident_in_list?(idnt, previous_obj_idents)
          #pre-existing thing, compare the differences...
          current_attribs = current_sub.get_attributes(current_sub.class.excluded_fields)
          previous_attribs = previous_sub.get_attributes(previous_sub.class.excluded_fields)
          
          obj = compare_objects(current_attribs, previous_attribs, current_sub, previous_sub, obj)
          
          #...and only store if something's changed
          unless obj.empty?
            obj[:change_type] = "modified"
            objects << obj
          end
        else
          #a new thing, just need to note its arrival
          unique_field = current_sub.class.unique_within_group
          objects << {unique_field.to_sym => eval("current_sub.#{unique_field}"), :change_type => "new"}
        end
      end
      objects
    end
    
    def preserve_deleted_by_ident(deleted_idents, previous_subs, previous_obj, sub)
      objects = []
      deleted_idents.each do |ident|
        previous_sub = find_in_array_by_ident(eval("previous_obj.#{sub}.to_a"), ident)
        obj = preserve_deleted_obj(previous_sub)
        objects << obj
      end
      objects
    end
    
    def compare_attributes(current, previous, current_obj, change={})
      previous.each do |key, value|
        change[key.to_sym] = value if value != current[key]
      end
      unless change.empty?
        if current_obj.class.unique_within_group
          unique_field = current_obj.class.unique_within_group
          change[unique_field.to_sym] = eval("current_obj.#{unique_field}")
        end
      end
      change
    end
    
    def analyze_subobjects(current_obj, previous_obj, change={})
      #need both - comparable objects need not have the same reflections
      current_subs = reflected_names(current_obj)
      previous_subs = reflected_names(previous_obj)
      
      #things that are available to the current object
      current_subs.each do |sub|
        objects = []
        current_objects = current_obj.association(sub).target
        previous_objects = previous_obj.respond_to?(sub) ? eval("previous_obj.#{sub}.to_a") : []
        current_obj_idents = map_obj_idents(current_objects)
        previous_obj_idents = map_obj_idents(previous_objects)
        
        #loop through the ids in the current block
        objects += compare_current_subs(current_obj_idents, previous_obj_idents, current_objects, previous_objects)
        
        #look for ids that only exist in the previous block
        objects += preserve_deleted_by_ident((previous_obj_idents - current_obj_idents), previous_subs, previous_obj, sub)
        
        #update time_blocks if any changes were found
        change[sub] = objects unless objects.empty?
      end
      
      #things that are only available to the previous object
      (previous_subs - current_subs).each do |sub|
        objects = []
        previous_obj_idents = map_obj_idents(previous_obj)
        objects += preserve_deleted_by_ident(previous_obj_idents, (previous_subs - current_subs), previous_obj, sub)
        change[sub] = objects unless objects.empty?
      end
      change
    end
    
    def preserve_deleted_obj(deleted, excluded_fields=self.class.excluded_fields)
      obj = {}
      #get attributes of object marked for deletion...
      attribs = deleted.get_attributes(deleted.class.excluded_fields)
      #...and copy them for preservation
      attribs.keys.each do |att|
        value = nil
        if deleted.respond_to?(att)
          value = eval("deleted.#{att}")
        end
        
        obj[att.to_sym] = value unless value.nil?
      end
      
      #look to see if our target object has sub-objects of its own
      previous_sub_keys = reflected_names(deleted)
      
      #preserve subs
      obj = preserve_deleted_subs(previous_sub_keys, deleted, obj)
      
      unless obj.empty?
        if deleted.class.conditional_fields
          deleted.class.conditional_fields.each do |key|
            obj[key.to_sym] = eval("deleted.#{key}") unless obj.empty?
          end
        end
        obj[:change_type] = "deleted"
      end
      obj
    end
    
    def compare_objects(current_attribs, other_attribs, current, other, change={})
      #compare the simple values
      change = compare_attributes(current_attribs, other_attribs, current)
      
      #analyse the subobjects
      change = analyze_subobjects(current, other, change)
      
      if other.class.conditional_fields
        other.class.conditional_fields.each do |key|
          change[key.to_sym] = eval("other.#{key}") unless change.empty?
        end
      end
      change
    end
    
    def preserve_deleted_subs(keys, deleted, change={})
      keys.each do |sub|
        subs = []
        previous_subs = deleted.respond_to?(sub) ? eval("deleted.#{sub}.to_a") : []
        previous_subs.each do |deleted_sub|  
          preserved = preserve_deleted_obj(deleted_sub)
          subs << preserved
        end
        change[sub] = subs unless subs.empty?
      end
      change
    end
  end
  
  module ClassMethods
    ##
    # Holds an array of excluded fields which will not be used
    # for comparison tests or when copying deleted values
    attr_reader :excluded_fields
    
    ##
    # String value corresponding to the field that uniquely identifies
    # a child record from among its siblings 
    # (should not be id unless id is being generated)
    attr_reader :unique_within_group
    
    ##
    # Holds an array of fields which will be added to a modified change Hash
    # (regardless of whether its value has changed or not) unless there are 
    # no other changes
    attr_reader :conditional_fields
    
    ##
    # A shortcut, used to quickly check whether a class implements Diffable
    attr_reader :diffable
    
    @diffable = true
    
    ##
    # Sets the class's conditional_fields values.
    #
    # If required, should be placed in the model definition code:
    #
    #    class ModelA < ActiveRecord::Base
    #      include Diffable
    #      set_conditional_fields :meta
    #    end
    def set_conditional_fields(*h)
      @conditional_fields = []
      h.each { |key| eval(%Q|@conditional_fields << "#{key.to_s}"|) }
    end
    
    ##
    # Sets the class's excluded_fields values.
    #
    # If required, should be placed in the model definition code:
    #
    #     class ModelB < ActiveRecord::Base
    #       include Diffable
    #       set_excluded_fields :ignore_me, :test
    #     end
    def set_excluded_fields(*h)
      @excluded_fields = []
      h.each { |key| eval(%Q|@excluded_fields << "#{key.to_s}"|) }
    end
    
    ##
    # Sets the class's unique_within_group value
    #
    # If required, should be placed in the model definition code:
    #
    #     class ModelC < ActiveRecord::Base
    #       include Diffable
    #       set_unique_within_set :generated_identifier
    #     end
    def set_unique_within_group(value)
      eval(%Q|@unique_within_group = "#{value.to_s}"|)
    end
  end
end
