#!/bin/bash
# Patch script to add WooCommerce JSON mapping to orders_api.rb
# Run this on Ubuntu if customer_note is not being imported

echo "🔧 Patching routes/orders_api.rb with WooCommerce JSON mapping..."

# Check if the mapping already exists
if grep -q "Map WooCommerce format" routes/orders_api.rb; then
  echo "✅ Mapping already exists! No changes needed."
  exit 0
fi

# Create backup
cp routes/orders_api.rb routes/orders_api.rb.backup
echo "✓ Created backup: routes/orders_api.rb.backup"

# Create the patch
cat > /tmp/woocommerce_patch.txt << 'PATCH'
      # Map WooCommerce format to internal format
      # Handle both direct API format and WooCommerce JSON format
      if data['site_name'] && !data['store_id']
        # Extract store code from site_name (e.g., "TPH DE" → "TPH_DE")
        data['store_id'] = data['site_name'].upcase.gsub(' ', '_')
      end
      
      if data['line_items'] && !data['items']
        data['items'] = data['line_items']
      end
      
      if (data['id'] || data['number']) && !data['external_order_code']
        data['external_order_code'] = data['id'] || data['number']
      end
      
PATCH

# Find the line to insert after (data = JSON.parse...)
LINE_NUM=$(grep -n "data = JSON.parse(request.body.read)" routes/orders_api.rb | head -1 | cut -d: -f1)

if [ -z "$LINE_NUM" ]; then
  echo "❌ Could not find insertion point in routes/orders_api.rb"
  exit 1
fi

# Insert the patch after that line
head -n $LINE_NUM routes/orders_api.rb > /tmp/orders_api_new.rb
echo "" >> /tmp/orders_api_new.rb
cat /tmp/woocommerce_patch.txt >> /tmp/orders_api_new.rb
tail -n +$((LINE_NUM + 1)) routes/orders_api.rb >> /tmp/orders_api_new.rb

# Replace original
mv /tmp/orders_api_new.rb routes/orders_api.rb

echo "✅ Patch applied successfully!"
echo ""
echo "Now restart your server:"
echo "  pkill -f puma"
echo "  bundle exec puma -b tcp://0.0.0.0:5000 -p 5000 config.ru &"
echo ""
echo "Then test importing an order with customer_note!"
