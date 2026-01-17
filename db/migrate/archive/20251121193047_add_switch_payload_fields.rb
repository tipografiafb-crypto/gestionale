class AddSwitchPayloadFields < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:order_items, :scala)
      add_column :order_items, :scala, :string, default: "1:1"
    end
    unless column_exists?(:order_items, :materiale)
      add_column :order_items, :materiale, :string
    end
    unless column_exists?(:order_items, :campi_custom)
      add_column :order_items, :campi_custom, :json, default: {}
    end
    unless column_exists?(:order_items, :campi_webhook)
      add_column :order_items, :campi_webhook, :json, default: {}
    end
    unless column_exists?(:print_flows, :operation_id)
      add_column :print_flows, :operation_id, :integer
    end
    unless column_exists?(:print_flows, :opzioni_stampa)
      add_column :print_flows, :opzioni_stampa, :json, default: {}
    end
    
    if table_exists?(:switch_jobs)
      unless column_exists?(:switch_jobs, :job_operation_id)
        add_column :switch_jobs, :job_operation_id, :integer
      end
    end
  end
end
