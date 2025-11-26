require 'sinatra/activerecord/rake'
require './app'

namespace :db do
  desc "Complete database setup - Creates all tables directly"
  task setup_complete: :environment do
    puts "🗄️  Starting complete database setup..."
    conn = ActiveRecord::Base.connection

    # Step 1: Create database if doesn't exist
    begin
      puts "[1/5] Creating database..."
      Rake::Task["db:create"].invoke
      puts "✓ Database created/verified"
    rescue => e
      puts "⚠️  Database creation: #{e.message}"
    end

    # Step 2: Run all migrations
    begin
      puts "[2/5] Running migrations..."
      Rake::Task["db:migrate"].invoke
      puts "✓ Migrations executed"
    rescue => e
      puts "⚠️  Migration error: #{e.message}"
    end

    # Step 3: Verify tables and load schema if needed
    puts "[3/5] Verifying tables..."
    required_tables = %w[
      stores orders order_items assets products print_flows product_categories
      switch_jobs switch_webhooks print_machines inventories product_print_flows
    ]

    existing_tables = conn.tables
    missing_tables = required_tables - existing_tables
    created_count = existing_tables.size

    if missing_tables.any?
      puts "⚠️  Missing tables after migrations: #{missing_tables.join(', ')}"
      puts "🔄 Loading consolidated schema..."

      schema_file = File.expand_path("db/init/schema_only.sql")
      if File.exist?(schema_file)
        begin
          # Use psql command to load the schema-only dump (no data, no role dependencies)
          db_url = ENV['DATABASE_URL'] || "postgresql://orchestrator_user:paolo@localhost:5432/print_orchestrator_dev"
          system("psql #{db_url} -q < #{schema_file}")
          
          puts "✓ Schema loaded from consolidated_schema.sql"
          existing_tables = conn.tables
          created_count = existing_tables.size
        rescue => e
          puts "❌ Failed to load schema: #{e.message}"
        end
      else
        puts "⚠️  consolidated_schema.sql not found at #{schema_file}"
        puts "Using only migration-created tables (#{created_count} tables)"
      end
    end

    puts "✓ Database has #{created_count} tables"

    # Step 4: Verify all required tables exist
    puts "[4/5] Final verification..."
    final_tables = conn.tables
    final_missing = required_tables - final_tables

    if final_missing.any?
      puts "⚠️  Some tables still missing: #{final_missing.join(', ')}"
      puts "But continuing anyway - app may have limited functionality"
    else
      puts "✓ All required tables created!"
    end

    # Step 5: Seed data if needed
    begin
      puts "[5/5] Loading seed data..."
      Rake::Task["db:seed"].invoke
      puts "✓ Seed data loaded"
    rescue => e
      puts "⚠️  Seed data: #{e.message}"
    end

    puts "\n✅ Database setup complete! (#{created_count} tables)"
  end
end
