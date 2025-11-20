class CreateSwitchJobs < ActiveRecord::Migration[7.1]
  def change
    create_table :switch_jobs do |t|
      t.references :order, null: false, foreign_key: true
      t.string :switch_job_id
      t.string :status, null: false, default: 'pending'
      t.string :result_preview_url
      t.text :log
      t.timestamps
    end
  end
end
