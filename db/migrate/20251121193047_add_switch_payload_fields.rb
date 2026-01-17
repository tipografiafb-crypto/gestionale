class AddSwitchPayloadFields < ActiveRecord::Migration[7.2]
  def change
    # OrderItem - add fields for Switch payload mapping
    add_column :order_items, :scala, :string, default: "1:1"  # scale
    add_column :order_items, :materiale, :string  # material type
    add_column :order_items, :campi_custom, :json, default: {}  # custom fields
    add_column :order_items, :campi_webhook, :json, default: {}  # webhook metadata

    # PrintFlow - add switch operation tracking
    add_column :print_flows, :operation_id, :integer  # Switch operation ID
    add_column :print_flows, :opzioni_stampa, :json, default: {}  # print options

    # SwitchJob - add job operation tracking
    add_column :switch_jobs, :job_operation_id, :integer  # Switch job operation ID
  end
end
