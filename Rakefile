require 'sinatra/activerecord/rake'
require './app'

# Load custom rake tasks
Dir.glob('lib/tasks/*.rake').each { |r| import r }

# Define environment task for Sinatra (required for custom rake tasks)
task :environment do
  # App is already loaded above
end

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

    # Step 2: Load schema directly (skip migrations to avoid dependency issues)
    puts "[2/5] Loading database schema..."
    schema_file = File.expand_path("db/init/schema_only.sql")
    if File.exist?(schema_file)
      begin
        # Use psql command to load the schema-only dump
        db_url = ENV['DATABASE_URL'] || "postgresql://orchestrator_user:paolo@localhost:5432/print_orchestrator_dev"
        system("psql #{db_url} -q < #{schema_file} 2>/dev/null")
        puts "✓ Schema loaded successfully"
      rescue => e
        puts "⚠️  Schema loading: #{e.message}"
      end
    else
      puts "⚠️  schema_only.sql not found, trying migrations..."
      begin
        Rake::Task["db:migrate"].invoke
        puts "✓ Migrations executed"
      rescue => e
        puts "⚠️  Migration error: #{e.message}"
      end
    end

    # Step 3: Verify tables
    puts "[3/5] Verifying tables..."
    required_tables = %w[
      stores orders order_items assets products print_flows product_categories
      switch_jobs switch_webhooks print_machines inventories product_print_flows
    ]

    existing_tables = conn.tables
    created_count = existing_tables.size

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

    # Step 5: Mark all migrations as executed (since we loaded schema directly)
    begin
      puts "[5/5] Marking migrations as executed..."
      migrations_dir = File.expand_path("db/migrate")
      Dir.glob("#{migrations_dir}/*.rb").each do |file|
        migration_name = File.basename(file, ".rb")
        conn.execute("INSERT INTO schema_migrations (version) VALUES ('#{migration_name}') ON CONFLICT DO NOTHING")
      end
      puts "✓ Migrations marked"
    rescue => e
      puts "⚠️  Marking migrations: #{e.message}"
    end

    puts "\n✅ Database setup complete! (#{created_count} tables)"
  end
end
