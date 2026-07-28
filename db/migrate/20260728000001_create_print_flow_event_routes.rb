class CreatePrintFlowEventRoutes < ActiveRecord::Migration[7.1]
  def change
    create_table :print_flow_event_routes do |t|
      t.references :print_flow, null: false, foreign_key: true
      t.references :automation_flow, null: false, foreign_key: true
      t.string :event_key, null: false
      t.string :label
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :print_flow_event_routes,
              %i[print_flow_id event_key],
              unique: true,
              name: 'index_print_flow_event_routes_on_flow_and_event'
  end
end
