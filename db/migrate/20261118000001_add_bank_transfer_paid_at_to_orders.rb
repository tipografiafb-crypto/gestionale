class AddBankTransferPaidAtToOrders < ActiveRecord::Migration[7.1]
  def up
    add_column :orders, :bank_transfer_paid_at, :datetime, if_not_exists: true
  end

  def down
    remove_column :orders, :bank_transfer_paid_at, if_exists: true
  end
end
