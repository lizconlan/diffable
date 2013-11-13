ActiveRecord::Schema.define do
  create_table(:notdiff) do |t|
    t.string  :name
  end
  
  create_table(:hazdiffs) do |t|
    t.string  :name
    t.integer :price
  end
  
  create_table(:multidiffs) do |t|
    t.string  :name
    t.integer :price
  end
  
  create_table(:subrecs) do |t|
    t.integer :hazdiff_id
    t.string  :name
    t.string  :ident
  end
  
  create_table(:alt_subrecs) do |t|
    t.integer :hazdiff_id
    t.string  :name
    t.string  :ident
    t.string  :ignore_me
    t.string  :tracker
  end
  
  create_table(:subrec_no_diffs) do |t|
    t.integer :hazdiff_id
    t.string  :name
    t.string  :ident
  end
end