# @feature backup
# Backup system for database and files
require 'fileutils'
require 'open3'
require 'tempfile'
require 'zlib'

class BackupManager
  BACKUP_EXTENSIONS = %w[.tar .zip].freeze

  def self.perform_backup(config = nil)
    config ||= BackupConfig.current
    return { success: false, error: 'Configurazione backup non trovata' } unless config&.remote_ip.present?

    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    backup_dir = File.join(Dir.pwd, 'tmp', 'backups')
    FileUtils.mkdir_p(backup_dir)

    db_file = File.join(backup_dir, "database_#{timestamp}.sql")
    storage_tar = File.join(backup_dir, "storage_#{timestamp}.tar.gz")
    backup_file = File.join(backup_dir, "backup_#{timestamp}.tar")

    begin
      db_url = ENV['DATABASE_URL'] || 'postgresql://localhost/print_orchestrator_development'
      run_command!('pg_dump', db_url, out: db_file)
      raise 'Il dump del database è vuoto' unless File.size?(db_file)

      storage_path = File.join(Dir.pwd, 'storage')
      raise 'Cartella storage non trovata' unless Dir.exist?(storage_path)

      run_command!('tar', '-czf', storage_tar, '-C', Dir.pwd, 'storage')
      raise 'Archivio storage vuoto' unless File.size?(storage_tar)

      # The old implementation placed storage.tar.gz inside another ZIP using
      # rubyzip. Files over 4 GiB overflowed the ZIP32 offsets. A plain TAR
      # container supports large members and does not recompress the gzip file.
      run_command!(
        'tar', '-cf', backup_file,
        '-C', backup_dir,
        File.basename(db_file),
        File.basename(storage_tar)
      )
      validate_backup_container!(backup_file)

      validate_remote_config!(config)
      transfer_backup!(backup_file, config)

      result = {
        success: true,
        file: File.basename(backup_file),
        size: File.size(backup_file),
        remote_path: "#{config.remote_path}/#{File.basename(backup_file)}",
        message: "✓ Backup trasferito su server remoto (#{config.remote_ip})"
      }

      FileUtils.rm_f([db_file, storage_tar, backup_file])
      result
    rescue StandardError => e
      { success: false, error: e.message }
    end
  end

  def self.test_connection(ip, path)
    _output, error, status = Open3.capture3(
      'ssh',
      '-o', 'ConnectTimeout=5',
      "root@#{ip}",
      'test', '-d', path.to_s
    )
    status.success? ? { connected: true } : { connected: false, error: "Path not found or SSH failed: #{error}" }
  rescue StandardError => e
    { connected: false, error: e.message }
  end

  def self.list_backups
    backup_dir = File.join(Dir.pwd, 'tmp', 'backups')
    return [] unless Dir.exist?(backup_dir)

    backup_files = BACKUP_EXTENSIONS.flat_map do |extension|
      Dir.glob(File.join(backup_dir, "backup_*#{extension}"))
    end.sort.reverse

    backup_files.map do |file|
      {
        filename: File.basename(file),
        path: file,
        size: File.size(file),
        created_at: File.mtime(file)
      }
    end
  end

  def self.restore_backup(filename)
    backup_dir = File.join(Dir.pwd, 'tmp', 'backups')
    return { success: false, error: 'File non è un backup valido' } unless valid_backup_filename?(filename)

    safe_filename = filename.to_s
    backup_path = File.join(backup_dir, safe_filename)

    return { success: false, error: 'File non trovato' } unless File.file?(backup_path)

    do_restore(backup_path)
  end

  def self.restore_from_uploaded_file(uploaded_file)
    return { success: false, error: 'File non caricato' } unless uploaded_file && uploaded_file[:tempfile]

    filename = File.basename(uploaded_file[:filename].to_s)
    return { success: false, error: 'Sono consentiti backup .tar e .zip' } unless valid_backup_filename?(filename)

    do_restore(uploaded_file[:tempfile].path)
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def self.valid_backup_filename?(filename)
    value = filename.to_s
    value == File.basename(value) &&
      value.match?(/\Abackup_[A-Za-z0-9_-]+\.(?:tar|zip)\z/i)
  end

  class << self
    private

    def do_restore(backup_path)
      backup_dir = File.join(Dir.pwd, 'tmp', 'backups')
      extract_dir = File.join(backup_dir, "restore_#{Process.pid}_#{Time.now.to_i}")
      FileUtils.mkdir_p(extract_dir)

      extract_backup_container!(backup_path, extract_dir)

      db_file = Dir.glob(File.join(extract_dir, '**', 'database_*.sql')).first
      storage_tar = Dir.glob(File.join(extract_dir, '**', 'storage_*.tar.gz')).first
      raise 'Database mancante nel backup: ripristino annullato' unless db_file && File.size?(db_file)
      raise 'Storage mancante nel backup: ripristino annullato' unless storage_tar && File.size?(storage_tar)

      # Fully extract and validate storage before changing the live database.
      staged_root = File.join(extract_dir, 'staged')
      FileUtils.mkdir_p(staged_root)
      run_command!('tar', '-xzf', storage_tar, '-C', staged_root)
      staged_storage = File.join(staged_root, 'storage')
      raise 'La cartella storage non è valida: ripristino annullato' unless Dir.exist?(staged_storage)

      restore_database!(db_file)
      install_staged_storage!(staged_storage)

      { success: true, message: 'Backup ripristinato con successo' }
    rescue StandardError => e
      { success: false, error: e.message }
    ensure
      FileUtils.rm_rf(extract_dir) if extract_dir && Dir.exist?(extract_dir)
    end

    def extract_backup_container!(backup_path, extract_dir)
      signature = File.binread(backup_path, 4)

      unless signature == "PK\x03\x04".b
        run_command!('tar', '-xf', backup_path, '-C', extract_dir)
        return
      end

      _output, error, status = Open3.capture3('unzip', '-o', backup_path, '-d', extract_dir)
      return if status.success?

      FileUtils.rm_rf(extract_dir)
      FileUtils.mkdir_p(extract_dir)
      recover_legacy_zip!(backup_path, extract_dir)
    rescue StandardError => e
      detail = error && !error.strip.empty? ? " (#{error.strip})" : ''
      raise "Estrazione backup fallita: #{e.message}#{detail}"
    end

    # Backups created with rubyzip 2.x could contain complete data but invalid
    # ZIP32 sizes when storage.tar.gz exceeded 4 GiB. Inflate local entries to
    # their real end-of-stream and verify their CRC, ignoring the broken index.
    def recover_legacy_zip!(zip_path, extract_dir)
      extracted = []

      File.open(zip_path, 'rb') do |input|
        loop do
          header_start = input.pos
          header = input.read(30)
          break if header.nil? || header.bytesize < 30
          break unless header.unpack1('V') == 0x04034b50

          fields = header.unpack('VvvvvvVVVvv')
          flags = fields[2]
          method = fields[3]
          expected_crc = fields[6]
          name_length = fields[9]
          extra_length = fields[10]

          raise 'ZIP legacy con data descriptor non supportato' unless (flags & 0x08).zero?
          raise "Metodo ZIP legacy non supportato: #{method}" unless method == 8

          raw_name = input.read(name_length)
          input.seek(extra_length, IO::SEEK_CUR)
          safe_name = File.basename(raw_name.to_s)
          unless safe_name.match?(/\A(?:database_.+\.sql|storage_.+\.tar\.gz)\z/)
            raise "Voce non valida nel backup legacy: #{safe_name}"
          end

          data_start = input.pos
          destination = File.join(extract_dir, safe_name)
          inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
          crc = 0

          File.open(destination, 'wb') do |output|
            until inflater.finished?
              chunk = input.read(8 * 1024 * 1024)
              raise "Dati incompleti per #{safe_name}" if chunk.nil? || chunk.empty?

              inflated = inflater.inflate(chunk)
              output.write(inflated)
              crc = Zlib.crc32(inflated, crc)
            end
          end

          consumed = inflater.total_in
          inflater.close
          raise "CRC non valido per #{safe_name}" unless crc == expected_crc

          extracted << safe_name
          input.seek(data_start + consumed, IO::SEEK_SET)
          raise "Posizione ZIP legacy non valida dopo #{safe_name}" if input.pos <= header_start
        end
      end

      required = [
        extracted.any? { |name| name.match?(/\Adatabase_.+\.sql\z/) },
        extracted.any? { |name| name.match?(/\Astorage_.+\.tar\.gz\z/) }
      ]
      raise 'Backup ZIP legacy incompleto' unless required.all?
    end

    def restore_database!(db_file)
      db_url = ENV['DATABASE_URL'] || 'postgresql://localhost/print_orchestrator_development'
      clean_db_file = "#{db_file}.clean"

      File.open(clean_db_file, 'wb') do |clean|
        File.foreach(db_file) do |line|
          next if line.match?(/^\\(?:un)?restrict/)
          next if line.match?(/^ALTER TABLE .* OWNER TO/)
          next if line.match?(/^CREATE EXTENSION/)

          clean.write(line)
        end
      end
      raise 'Il dump SQL ripulito è vuoto' unless File.size?(clean_db_file)

      cleanup_sql = <<~SQL
        SELECT pg_terminate_backend(pid) FROM pg_stat_activity
        WHERE datname = current_database() AND pid <> pg_backend_pid();
        DROP SCHEMA IF EXISTS public CASCADE;
        CREATE SCHEMA public;
      SQL
      run_command!(
        'psql', db_url, '-v', 'ON_ERROR_STOP=1', '-c', cleanup_sql,
        out: File::NULL
      )

      File.open(clean_db_file, 'rb') do |input|
        run_command!(
          'psql', db_url, '-v', 'ON_ERROR_STOP=1',
          stdin: input,
          out: File::NULL
        )
      end
    ensure
      FileUtils.rm_f(clean_db_file) if clean_db_file
    end

    def install_staged_storage!(staged_storage)
      live_storage = File.join(Dir.pwd, 'storage')
      previous_storage = "#{live_storage}.before_restore_#{Time.now.to_i}"
      FileUtils.mv(live_storage, previous_storage) if Dir.exist?(live_storage)

      begin
        FileUtils.mv(staged_storage, live_storage)
        FileUtils.rm_rf(previous_storage)
      rescue StandardError
        FileUtils.rm_rf(live_storage)
        FileUtils.mv(previous_storage, live_storage) if Dir.exist?(previous_storage)
        raise
      end
    end

    def validate_backup_container!(backup_file)
      output, error, status = Open3.capture3('tar', '-tf', backup_file)
      raise "Verifica archivio fallita: #{error.strip}" unless status.success?

      entries = output.lines.map { |line| File.basename(line.strip) }
      unless entries.any? { |name| name.match?(/\Adatabase_.+\.sql\z/) } &&
             entries.any? { |name| name.match?(/\Astorage_.+\.tar\.gz\z/) }
        raise 'Il backup creato non contiene database e storage'
      end
    end

    def validate_remote_config!(config)
      required = [config.remote_ip, config.remote_path, config.ssh_username, config.ssh_password]
      raise 'Configurazione SSH incompleta (IP, percorso, username e password richiesti)' if required.any?(&:blank?)
    end

    def transfer_backup!(backup_file, config)
      ssh_port = config.ssh_port.presence || 22
      command = [
        'sshpass', '-p', config.ssh_password,
        'scp', '-P', ssh_port.to_s,
        '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=no',
        backup_file,
        "#{config.ssh_username}@#{config.remote_ip}:#{config.remote_path}/"
      ]
      _output, error, status = Open3.capture3(*command)
      raise "Trasferimento su server remoto fallito: #{error.strip}" unless status.success?
    end

    def run_command!(*command, out: nil, stdin: nil)
      Tempfile.create('backup-command-error') do |error_file|
        options = { err: error_file }
        options[:out] = out if out
        options[:in] = stdin if stdin

        success = system(*command, **options)
        error_file.rewind
        error = error_file.read
        raise "#{command.first} fallito: #{error.strip}" unless success
      end
    end
  end
end
