# Diffable

Diffable provides a mixin that can be used to extend any ActiveRecord object to provide diff 
functionality. Calling the diff method compares the receiver against another 
object and returns a Hash of differences found (presented as a description of 
the changes between the second object and the receiver - as if trying to restore
the calling object from its replacement).

## Installation

Add this line to your application's Gemfile:

    gem 'diffable'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install diffable

## Usage

Require the gem in the source file that includes the relevant model code:

    require 'diffable'
    
Use the include statement to add Diffable support to each model that needs it:

    class ModelA < ActiveRecord::Base
      include Diffable
    end
    
You can then call the `diff` method on any instance of that model class:

    object1 = ModelA.new(:name => "test")
    object2 = ModelA.new(:name => "test2")
    difference = object1.diff(object2)

## Behaviour

There are 3 different types of change that can be returned by the diff method: 
modified, new and deleted. These are indicated using a `:change_type` 
key/value within the results Hash.

When an object is flagged as **modified**, its identifier and any of the altered 
fields are returned, e.g.:

    {:change_type => "modified", :id => 42, :name => "test1"}

When an object is flagged as **new**, only its identifier is returned. Sample output:

    {:change_type => "new", :id => 42}

When an object is flagged as **deleted**, all of its attributes are returned in 
the diff Hash. Sample output:

    {:change_type => "deleted", :id => 42, :name => "test", :desc => "db test"}

### Excluding fields

If there are any database fields that should not be returned as part of 
a **deleted** object's data, they can be excluded at the model level using 
`set_excluded_fields`:

    class ModelB < ActiveRecord::Base
      include Diffable
      set_excluded_fields :ignore_me
    end

### Conditional fields

If a field value should always be included as part of a modified object's 
data, this can be set at the model level using `set_conditional_fields`:

    class ModelC < ActiveRecord::Base
      include Diffable
      set_conditional_fields :metadata, :history
    end

### Using with related tables

If your model uses `has_many` or `has_one`, the changes to these dependent 
objects can also be captured by the diff method, provided that their model 
definitions also use the `include Diffable` statement (otherwise they will 
be ignored). However, you will also need to inform the model which field can 
be used to uniquely identify records within the set returned for a particular 
parent object using `set_unique_within_group`. This should be a generated 
field as `:id` is unlikely to be suitable.

    class ModelD < ActiveRecord::Base
      include Diffable
      has_many :catalogue_entries
    end
    
    class CatalogueEntries < ActiveRecord::Base
      include Diffable
      belongs_to :model_d
      set_unique_within_group :generated_identifier
      
      ...
      
    end

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
