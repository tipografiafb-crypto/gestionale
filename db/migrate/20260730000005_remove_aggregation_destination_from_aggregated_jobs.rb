class RemoveAggregationDestinationFromAggregatedJobs < ActiveRecord::Migration[7.2]
  def up
    remove_reference :aggregated_jobs,
                     :aggregation_automation_flow,
                     foreign_key: {to_table: :automation_flows}
    remove_reference :aggregated_jobs,
                     :aggregation_webhook,
                     foreign_key: {to_table: :switch_webhooks}
    remove_column :aggregated_jobs, :aggregation_executor
  end

  def down
    add_column :aggregated_jobs,
               :aggregation_executor,
               :string,
               null: false,
               default: 'none'
    add_reference :aggregated_jobs,
                  :aggregation_webhook,
                  foreign_key: {to_table: :switch_webhooks}
    add_reference :aggregated_jobs,
                  :aggregation_automation_flow,
                  foreign_key: {to_table: :automation_flows}
  end
end
