require 'active_record'
require 'rspec'
require 'nulldb_rspec'

require "./lib/diffable"

class Hazdiff < ActiveRecord::Base
  include Diffable
end

class Notdiff < ActiveRecord::Base
end

class Multidiff < ActiveRecord::Base
  include Diffable
  has_many :subrecs
  has_many :alt_subrecs
  has_many :subrec_no_diffs
end

class Subrec < ActiveRecord::Base
  include Diffable
  set_unique_within_group :ident
  belongs_to :multidiff
end

class SubrecNoDiff < ActiveRecord::Base
  belongs_to :multidiff
end

class AltSubrec < ActiveRecord::Base
  include Diffable
  set_unique_within_group :ident
  set_excluded_from_copy :ignore_me
  set_conditional_fields :tracker
end

class Altdiff < Hazdiff
end

class AltdiffToo < Hazdiff
end

describe Diffable do
  before(:all) do  
    NullDB.configure {|ndb| ndb.project_root = './spec/'}
    ActiveRecord::Base.establish_connection :adapter => :nulldb
    ActiveRecord::Migration.verbose = false
  end
  
  def should_have_column(klass, col_name, col_type)
    col = klass.columns_hash[col_name.to_s]
    col.should_not be_nil
    col.type.should == col_type
  end
    
  context "sanity checks" do
    it "should remember columns defined in migrations" do
      should_have_column(Hazdiff, :name, :string)
    end
    
    it "should be defined" do
      Diffable::VERSION.is_a?(String)
      !Diffable::VERSION.empty?
    end
  end
  
  context "checking class compatibility" do
    it "should be able to compare 2 things of the same class" do
      hd1 = Hazdiff.new()
      hd2 = Hazdiff.new()
      lambda { hd1.diff(hd2) }.should_not raise_error
    end
    
    it "should not be able to compare 2 things with different base classes" do
      hd = Hazdiff.new
      md = Multidiff.new
      lambda { hd.diff(md) }.should raise_error
      lambda { md.diff(hd) }.should raise_error
    end
    
    it "should be able to compare 2 things with the same base class" do
      ad1 = Altdiff.new
      ad2 = AltdiffToo.new
      lambda { ad1.diff(ad2) }.should_not raise_error
    end
    
    it "should be able to compare base object with inherited object" do
      hd = Hazdiff.new
      ad = Altdiff.new
      lambda { hd.diff(ad) }.should_not raise_error
      lambda { ad.diff(hd) }.should_not raise_error
    end
  end
  
  context "an object not including Diffable" do
    it "should not inherit the instance methods" do
      object = Notdiff.new
      object.respond_to?(:diff).should be_false
      object.respond_to?(:get_attributes).should be_false
      object.respond_to?(:reflected_names).should be_false
      object.class.respond_to?(:diffable).should be_false
    end
  end
  
  context "a simple object including Diffable" do
    it "should inherit the expected instance methods" do
      object = Hazdiff.new(:name => "meep")
      object.respond_to?(:diff).should be_true
      object.respond_to?(:get_attributes).should be_true
      object.respond_to?(:reflected_names).should be_true
      object.class.respond_to?(:diffable).should be_true
    end
    
    describe "when asked for diff" do
      describe "and given an object with identical attribute values" do
        it "should return a blank hash" do
          obj1 = Hazdiff.new(:name => "test1", :price => 0)
          obj2 = Hazdiff.new(:name => "test1", :price => 0)
          obj1.diff(obj2).should eq({})
        end
      end
      
      describe "and given an object with different attribute values" do
        it "should return a hash of differences" do
          obj1 = Hazdiff.new(:name => "test1", :price => 0)
          obj2 = Hazdiff.new(:name => "test2", :price => 0)
          obj3 = Hazdiff.new(:name => "test2", :price => 1)
          obj1.diff(obj2).should eq({:name => "test2"})
          obj2.diff(obj1).should eq({:name => "test1"})
          obj1.diff(obj3).should eq({:name => "test2", :price => 1})
        end
      end
    end
  end
  
  context "an object including Diffable that has subobjects" do
    describe "when asked for diff" do
      describe "and the subobjects do not include Diffable" do
        it "should ignore the ineligible subobjects" do
          obj1 = Multidiff.new(:name => "test1")
          sub1 = SubrecNoDiff.new(:name => "sub1")
          
          obj2 = Multidiff.new(:name => "test1")
          sub2 = SubrecNoDiff.new(:name => "sub2")
          
          obj1.diff(obj2).should eq({})
        end
      end
      
      describe "and there are no difference between the subobjects" do
        it "should return a blank hash" do
          obj1 = Multidiff.new(:name => "test1")
          sub1 = Subrec.new(:name => "sub1")
          obj1.subrecs << sub1
          obj2 = Multidiff.new(:name => "test1")
          obj2.subrecs << sub1.dup
          
          obj1.diff(obj2).should eq({})
        end
      end
      
      describe "and there are 2 different sets of subobjects" do
        it "should return 1 deleted subobject and 1 new one" do
          obj1 = Multidiff.new(:name => "test1")
          sub1 = Subrec.new(:name => "sub1", :ident => "s1")
          obj1.subrecs << sub1
          
          obj2 = Multidiff.new(:name => "test1")
          sub2 = Subrec.new(:name => "sub2", :ident => "s2")
          obj2.subrecs << sub2
          
          obj1.diff(obj2).should eq({:subrecs=>[{:ident=>"s1", :change_type=>"new"}, {:name=>"sub2", :ident=>"s2", :change_type=>"deleted"}]})
        end
      end
      
      describe "and there are changes to the subobject" do
        it "should return the subobject changes" do
          obj1 = Multidiff.new(:name => "test1")
          sub1 = Subrec.new(:name => "sub1", :ident => "s1")
          obj1.subrecs << sub1
          
          obj2 = Multidiff.new(:name => "test1")
          sub2 = Subrec.new(:name => "sub01", :ident => "s1")
          obj2.subrecs << sub2
          
          obj1.diff(obj2).should eq({:subrecs=>[{:name=>"sub01", :ident=>"s1", :change_type=>"modified"}]})
        end
        
        it "should include conditional fields where there has been a change" do
          obj1 = Multidiff.new(:name => "test1")
          sub1 = AltSubrec.new(:name => "sub1", :ident => "s1", :tracker => "t")
          obj1.alt_subrecs << sub1
          
          obj2 = Multidiff.new(:name => "test1")
          sub2 = AltSubrec.new(:name => "sub01", :ident => "s1", :tracker => "t")
          obj2.alt_subrecs << sub2
          
          obj1.diff(obj2).should eq({:alt_subrecs=>[{:name=>"sub01", :ident=>"s1", :tracker => "t", :change_type=>"modified"}]})
        end
      end
      
      describe "and the subobject has been removed" do
        #diffs are retrospective, this is where things get a bit weird
        it "should return a new subobject" do
          obj1 = Multidiff.new(:name => "test1")
          sub1 = Subrec.new(:name => "sub1", :ident => "s1")
          obj1.subrecs << sub1
          
          obj2 = Multidiff.new(:name => "test1")
          
          obj1.diff(obj2).should eq({:subrecs=>[{:ident=>"s1", :change_type=>"new"}]})
        end
      end
      
      describe "and a subobject has been added" do
        #diffs are retrospective, this is where things get a bit weird
        it "should return a deleted subobject" do
          obj1 = Multidiff.new(:name => "test1")
          obj2 = Multidiff.new(:name => "test1")
          sub1 = Subrec.new(:name => "sub1", :ident => "s1")
          obj2.subrecs << sub1
          
          obj1.diff(obj2).should eq({:subrecs=>[{:ident=>"s1", :name => "sub1", :change_type=>"deleted"}]})
        end
        
        it "should not return excluded fields" do
          obj1 = Multidiff.new(:name => "test1")
          obj2 = Multidiff.new(:name => "test1")
          sub1 = AltSubrec.new(:name => "sub1", :ident => "s1", :tracker => "t", :ignore_me => "??")
          obj2.alt_subrecs << sub1
          
          obj1.diff(obj2).should eq({:alt_subrecs=>[{:name => "sub1", :ident=>"s1", :tracker => "t", :change_type=>"deleted"}]})
        end
      end
    end
  end
end

ActiveRecord::Base.configurations['test'] = {'adapter' => 'nulldb'}