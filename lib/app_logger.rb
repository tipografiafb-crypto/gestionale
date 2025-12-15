# Simple logger utility
class AppLogger
  def self.info(category, message, details = nil)
    log_to_db('info', category, message, details)
    puts "[INFO] [#{category}] #{message}"
  end

  def self.warn(category, message, details = nil)
    log_to_db('warn', category, message, details)
    puts "[WARN] [#{category}] #{message}"
  end

  def self.error(category, message, details = nil)
    log_to_db('error', category, message, details)
    puts "[ERROR] [#{category}] #{message}"
  end

  def self.debug(category, message, details = nil)
    log_to_db('debug', category, message, details)
    puts "[DEBUG] [#{category}] #{message}"
  end

  private

  def self.log_to_db(level, category, message, details)
    begin
      Log.create(
        level: level,
        category: category,
        message: message,
        details: details
      )
    rescue => e
      puts "[LOGGER ERROR] Could not save log to DB: #{e.message}"
    end
  end
end
