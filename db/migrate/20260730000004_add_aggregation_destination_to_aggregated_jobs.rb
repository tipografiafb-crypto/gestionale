class AddAggregationDestinationToAggregatedJobs < ActiveRecord::Migration[7.2]
  def up
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

    # Preserve the legacy behaviour for existing groups: aggregation used the
    # prepress webhook associated with their PrintFlow.
    execute <<~SQL
      UPDATE aggregated_jobs
      SET aggregation_executor = 'webhook',
          aggregation_webhook_id = print_flows.preprint_webhook_id
      FROM print_flows
      WHERE print_flows.id = aggregated_jobs.print_flow_id
        AND print_flows.preprint_webhook_id IS NOT NULL
    SQL

    # "aggregation" is no longer a PrintFlow custom event. New groups store
    # their selected destination directly.
    execute "DELETE FROM print_flow_event_routes WHERE event_key = 'aggregation'"
  end

  def down
    remove_reference :aggregated_jobs,
                     :aggregation_automation_flow,
                     foreign_key: {to_table: :automation_flows}
    remove_reference :aggregated_jobs,
                     :aggregation_webhook,
                     foreign_key: {to_table: :switch_webhooks}
    remove_column :aggregated_jobs, :aggregation_executor
  end
end
