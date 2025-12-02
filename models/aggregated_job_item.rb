# @feature aggregation
# @domain data-models
# AggregatedJobItem model - Individual items within an aggregated job
class AggregatedJobItem < ActiveRecord::Base
  belongs_to :aggregated_job
  belongs_to :order_item
  
  validates :aggregated_job_id, :order_item_id, presence: true
  validates :order_item_id, uniqueness: { scope: :aggregated_job_id }
end
