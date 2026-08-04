# Groups order rows that share the same artwork while keeping size/SKU quantities separate.
require 'digest/sha2'

module DesignGrouping
  module_function

  def key_for(item_data, order_scope: nil)
    explicit = item_data['design_group_key'] || item_data['artwork_id'] || item_data['cart_id']
    meta = item_data['meta_data']
    if meta.is_a?(Hash)
      explicit ||= meta.dig('lumise_data', 'cart_id')
      explicit ||= meta.dig('_wc_ai_customization', 'artwork_id')
    end

    raw = if explicit.present?
            "customizer:#{explicit}"
          else
            urls = [item_data['print_files'], item_data['cut_files'], item_data['image_urls']].flatten.compact.map(&:to_s).reject(&:empty?)
            urls.first.present? ? "asset:#{Digest::SHA256.hexdigest(urls.first)}" : nil
          end
    return nil if raw.blank?

    scope = order_scope.to_s.presence
    scope ? "#{scope}:#{raw}" : raw
  end

  def for_item(order_item)
    return order_item.design_group_key if order_item.respond_to?(:design_group_key) && order_item.design_group_key.present?

    data = order_item.json_data
    print_urls = order_item.assets.where("asset_type LIKE ?", 'print%').pluck(:original_url)
    key_for(data.merge('print_files' => print_urls), order_scope: order_item.order_id) ||
      fallback_asset_key(order_item)
  end

  def fallback_asset_key(order_item)
    url = order_item.assets.where.not(original_url: nil).order(:id).pluck(:original_url).first
    url.present? ? "#{order_item.order_id}:asset:#{Digest::SHA256.hexdigest(url.to_s)}" : "#{order_item.order_id}:item:#{order_item.id}"
  end

  def siblings_for(order_item)
    key = for_item(order_item)
    order_item.order.order_items.includes(:assets).select { |item| for_item(item) == key }
  end

  def label_for(order_item)
    key = for_item(order_item).to_s
    key.split(':').last.to_s[0, 12].upcase
  end

  # Copies the already-rendered result to equivalent assets in sibling size rows.
  # Originals remain recoverable through each asset's backup file.
  def propagate_asset!(source_asset, image_binary, recipe)
    targets = siblings_for(source_asset.order_item).flat_map do |item|
      item.assets.where(asset_type: source_asset.asset_type, original_url: source_asset.original_url)
    end.uniq(&:id)

    targets.each do |target|
      next if target.id == source_asset.id || target.local_path_full.to_s.empty?
      ImageEditService.ensure_original_backup!(target)
      Tempfile.create(['image-adjust-group-', '.png'], File.dirname(target.local_path_full)) do |temporary|
        temporary.binmode
        temporary.write(image_binary)
        temporary.flush
        temporary.fsync
        FileUtils.mv(temporary.path, target.local_path_full)
      end
      target.update!(image_edit_data: recipe.merge('shared_design_group' => true))
    end
    targets.reject { |target| target.id == source_asset.id }
  end

  def propagate_file!(source_asset, source_path)
    return [] unless source_path && File.file?(source_path)
    targets = siblings_for(source_asset.order_item).flat_map do |item|
      item.assets.where(asset_type: source_asset.asset_type, original_url: source_asset.original_url)
    end.uniq(&:id)
    targets.each do |target|
      next if target.id == source_asset.id || target.local_path_full.to_s.empty?
      ImageEditService.ensure_original_backup!(target)
      FileUtils.copy(source_path, target.local_path_full)
    end
    targets.reject { |target| target.id == source_asset.id }
  end
end
