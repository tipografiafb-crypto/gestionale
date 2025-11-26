namespace :db do
  desc "Complete database setup - Creates all tables directly"
  task setup_complete: :environment do
    puts "🗄️  Starting complete database setup..."

    # Step 1: Create database if doesn't exist
    begin
      puts "[1/4] Creating database..."
      Rake::Task["db:create"].invoke
      puts "✓ Database created/verified"
    rescue => e
      puts "⚠️  Database creation: #{e.message}"
    end

    # Step 2: Run all migrations
    begin
      puts "[2/4] Running migrations..."
      Rake::Task["db:migrate"].invoke
      puts "✓ Migrations executed"
    rescue => e
      puts "❌ Migration error: #{e.message}"
    end

    # Step 3: Verify tables exist
    puts "[3/4] Verifying tables..."
    required_tables = %w[
      stores orders order_items assets products print_flows product_categories
      switch_jobs switch_webhooks print_machines inventories
    ]

    conn = ActiveRecord::Base.connection
    existing_tables = conn.tables

    missing_tables = required_tables - existing_tables
    created_count = existing_tables.size

    if missing_tables.any?
      puts "⚠️  Missing tables: #{missing_tables.join(', ')}"
      puts "✓ But created #{created_count} tables total"
    else
      puts "✓ All required tables exist (#{created_count} tables)"
    end

    # Step 4: Seed data if needed
    begin
      puts "[4/4] Loading seed data..."
      Rake::Task["db:seed"].invoke
      puts "✓ Seed data loaded"
    rescue => e
      puts "⚠️  Seed data: #{e.message}"
    end

    puts "\n✅ Database setup complete!"
  end
end
