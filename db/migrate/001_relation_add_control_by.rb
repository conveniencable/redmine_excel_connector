class RelationAddControlBy < ActiveRecord::Migration[4.2]
  def self.up
    add_column :issue_relations, :control_by_id, :integer, :default => nil , :null => true
  end

  def self.down
    remove_column :issue_relations, :control_by_id
  end
end
