# @feature invoices
# @domain data-models

require 'bigdecimal'
require 'time'

class InvoiceRequest < ActiveRecord::Base
  STATUSES = %w[not_issued issued data_requested].freeze
  STATUS_LABELS = {
    'not_issued' => 'Non emessa',
    'issued' => 'Emessa',
    'data_requested' => 'Richiesta dati'
  }.freeze

  belongs_to :order

  validates :order_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :with_status, ->(value) { where(status: value) if value.present? }
  scope :matching, lambda { |term|
    next all if term.blank?

    query = "%#{sanitize_sql_like(term.to_s.strip)}%"
    joins(order: :store).where(
      <<~SQL.squish,
        orders.external_order_code ILIKE :query OR
        stores.name ILIKE :query OR
        stores.code ILIKE :query OR
        COALESCE(invoice_requests.company_name, '') ILIKE :query OR
        COALESCE(invoice_requests.first_name, '') ILIKE :query OR
        COALESCE(invoice_requests.last_name, '') ILIKE :query OR
        COALESCE(invoice_requests.vat_number, '') ILIKE :query OR
        COALESCE(invoice_requests.tax_code, '') ILIKE :query OR
        COALESCE(invoice_requests.email, '') ILIKE :query
      SQL
      query: query
    )
  }

  def self.capture_from_payload!(order:, payload:)
    payload = payload.is_a?(Hash) ? payload.deep_stringify_keys : {}
    invoice = payload['invoice']
    return nil unless invoice.is_a?(Hash) && invoice['requested'] == true

    invoice = invoice.deep_stringify_keys
    address = invoice['address'].is_a?(Hash) ? invoice['address'].deep_stringify_keys : {}
    totals = payload['totals'].is_a?(Hash) ? payload['totals'].deep_stringify_keys : {}

    request = find_or_initialize_by(order: order)
    request.assign_attributes(
      schema_version: invoice['schema_version'].to_i.positive? ? invoice['schema_version'].to_i : 1,
      order_placed_at: parse_order_date(payload['order_date'] || payload['date_created']) || order.created_at,
      customer_type: invoice['customer_type'],
      company_name: invoice['company_name'],
      first_name: invoice['first_name'],
      last_name: invoice['last_name'],
      tax_country: invoice['tax_country'],
      vat_number: invoice['vat_number'],
      tax_code: invoice['tax_code'],
      recipient_code: invoice['recipient_code'],
      pec: invoice['pec'],
      email: invoice['email'] || invoice['billing_email'],
      phone: invoice['phone'] || invoice['billing_phone'],
      address_1: address['address_1'],
      address_2: address['address_2'],
      postcode: address['postcode'],
      city: address['city'],
      province: address['province'],
      country: address['country'],
      subtotal: decimal_value(totals['subtotal']),
      discount: decimal_value(totals['discount']),
      shipping: decimal_value(totals['shipping']),
      shipping_tax: decimal_value(totals['shipping_tax']),
      tax: decimal_value(totals['tax']),
      total: decimal_value(totals['total']),
      currency: totals['currency'].to_s.upcase.presence,
      line_items: normalized_line_items(payload['line_items'] || payload['items']),
      raw_payload: invoice
    )
    request.status ||= 'not_issued'
    request.status_changed_at ||= Time.current
    request.save!
    request
  end

  def status_label
    STATUS_LABELS.fetch(status, status.to_s.humanize)
  end

  def customer_display_name
    company_name.presence || [first_name, last_name].compact_blank.join(' ').presence || 'Cliente non indicato'
  end

  def customer_type_label
    {
      'company' => 'Azienda',
      'business' => 'Azienda',
      'private' => 'Privato',
      'individual' => 'Privato'
    }.fetch(customer_type.to_s.downcase, customer_type.presence || '—')
  end

  def full_address
    locality = [postcode, city, province.presence && "(#{province})"].compact_blank.join(' ')
    [address_1, address_2, locality, country].compact_blank.join(', ')
  end

  def missing_data
    missing = []
    missing << 'ragione sociale o nome' if company_name.blank? && first_name.blank? && last_name.blank?
    missing << 'partita IVA o codice fiscale' if vat_number.blank? && tax_code.blank?
    missing << 'indirizzo' if address_1.blank? || postcode.blank? || city.blank? || country.blank?
    missing << 'codice destinatario o PEC' if recipient_code.blank? && pec.blank?
    missing << 'email' if email.blank?
    missing
  end

  class << self
    private

    def parse_order_date(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      begin
        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end

    def decimal_value(value)
      return if value.nil? || value.to_s.strip.empty?

      BigDecimal(value.to_s).round(2)
    rescue ArgumentError
      nil
    end

    def decimal_string(value, scale)
      return nil if value.nil? || value.to_s.strip.empty?

      BigDecimal(value.to_s).round(scale).to_s('F')
    rescue ArgumentError
      nil
    end

    def normalized_line_items(items)
      Array(items).filter_map do |item|
        next unless item.is_a?(Hash)

        item = item.deep_stringify_keys
        {
          'product_id' => item['product_id'],
          'name' => item['name'] || item['product_name'],
          'sku' => item['sku'],
          'quantity' => item['quantity'].to_i,
          'unit_price' => decimal_string(item['unit_price'], 4),
          'line_total' => decimal_string(item['line_total'], 2),
          'line_tax' => decimal_string(item['line_tax'], 2)
        }.compact
      end
    end
  end
end
