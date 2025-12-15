class CreateLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :logs do |t|
      t.string :level
      t.string :category
      t.text :message
      t.text :details
      t.timestamps
    end
    
    add_index :logs, :level
    add_index :logs, :category
    add_index :logs, :created_at
  end
end
