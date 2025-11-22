# @feature orders
# @domain data-models
# ProductPrintFlow model - Join table for many-to-many relationship between products and print flows

class ProductPrintFlow < ActiveRecord::Base
  belongs_to :product
  belongs_to :print_flow
end
