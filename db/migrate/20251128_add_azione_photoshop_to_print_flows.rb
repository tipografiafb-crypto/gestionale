class AddAzionePhotoshopToPrintFlows < ActiveRecord::Migration[7.2]
  def change
    add_column :print_flows, :azione_photoshop_enabled, :boolean, default: false
    add_column :print_flows, :azione_photoshop_options, :text, default: nil
    add_column :print_flows, :default_azione_photoshop, :string, default: nil
  end
end
