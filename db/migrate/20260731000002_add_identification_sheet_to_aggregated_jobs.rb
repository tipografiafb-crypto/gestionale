class AddIdentificationSheetToAggregatedJobs < ActiveRecord::Migration[7.2]
  def change
    add_column :aggregated_jobs, :identification_sheet_file_url, :text
    add_column :aggregated_jobs, :identification_sheet_filename, :string
    add_column :aggregated_jobs, :identification_sheet_at, :timestamp
  end
end
