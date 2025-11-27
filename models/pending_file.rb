# @feature switch
# @domain data-models
# PendingFile - Tracks files received from Switch before order is imported
class PendingFile < ActiveRecord::Base
  belongs_to :order_item, optional: true

  validates :external_order_code, :external_id_riga, :filename, :file_path, presence: true
  
  # Link this pending file to an OrderItem after order is imported
  def link_to_order_item(order_item)
    update(
      order_item_id: order_item.id,
      status: 'linked'
    )
  end
end
