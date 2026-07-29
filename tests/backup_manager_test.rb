require 'minitest/autorun'
require 'tmpdir'
require 'zlib'
require_relative '../lib/backup'

class BackupManagerTest < Minitest::Test
  def test_accepts_new_and_legacy_backup_names
    assert BackupManager.valid_backup_filename?('backup_20260729_020003.tar')
    assert BackupManager.valid_backup_filename?('backup_20260729_020003.zip')
    refute BackupManager.valid_backup_filename?('../backup_20260729_020003.tar')
    refute BackupManager.valid_backup_filename?('database.sql')
  end

  def test_validates_new_tar_container
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'database_20260729.sql'), 'SELECT 1;')
      File.write(File.join(directory, 'storage_20260729.tar.gz'), 'storage')
      archive = File.join(directory, 'backup_20260729.tar')

      system(
        'tar', '-cf', archive,
        '-C', directory,
        'database_20260729.sql',
        'storage_20260729.tar.gz'
      )

      BackupManager.send(:validate_backup_container!, archive)
    end
  end

  def test_recovers_legacy_zip_entries_with_wrong_32_bit_sizes
    Dir.mktmpdir do |directory|
      archive = File.join(directory, 'backup_legacy.zip')
      database = "CREATE TABLE example(id integer);\n"
      storage = "legacy-storage-data\n" * 100

      File.binwrite(
        archive,
        legacy_zip_entry('database_20260729.sql', database) +
          legacy_zip_entry('storage_20260729.tar.gz', storage)
      )

      extracted = File.join(directory, 'extracted')
      Dir.mkdir(extracted)
      BackupManager.send(:recover_legacy_zip!, archive, extracted)

      assert_equal database, File.binread(File.join(extracted, 'database_20260729.sql'))
      assert_equal storage, File.binread(File.join(extracted, 'storage_20260729.tar.gz'))
    end
  end

  def test_rejects_incomplete_backup_before_database_restore
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'database_20260729.sql'), 'SELECT 1;')
      archive = File.join(directory, 'backup_20260729.tar')
      system('tar', '-cf', archive, '-C', directory, 'database_20260729.sql')

      result = BackupManager.send(:do_restore, archive)

      refute result[:success]
      assert_match(/Storage mancante/, result[:error])
    end
  end

  def test_database_cleaner_pattern_handles_both_restrict_directives
    pattern = /^\\(?:un)?restrict/

    assert_match pattern, "\\restrict token\n"
    assert_match pattern, "\\unrestrict token\n"
    refute_match pattern, "SELECT 1;\n"
  end

  private

  def legacy_zip_entry(name, content)
    deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    compressed = deflater.deflate(content, Zlib::FINISH)
    deflater.close

    header = [
      0x04034b50,
      20,
      0,
      8,
      0,
      0,
      Zlib.crc32(content),
      1, # Simulates the truncated/overflowed ZIP32 compressed size.
      content.bytesize,
      name.bytesize,
      0
    ].pack('VvvvvvVVVvv')

    header + name + compressed
  end
end
