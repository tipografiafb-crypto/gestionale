# @feature automation
# @domain services

require 'fileutils'
require 'open3'
require 'pathname'
require 'securerandom'
require 'timeout'

class AutomationDestinationService
  Result = Struct.new(:success?, :message, :details, keyword_init: true)

  class << self
    def check(destination)
      destination.network_folder? ? check_network_folder(destination) : check_ipp_printer(destination)
    rescue StandardError => e
      Result.new(success?: false, message: e.message, details: {})
    end

    def deliver(destination:, source_path:, filename:, simulation: false)
      raise ArgumentError, 'La destinazione non è una hot folder' unless destination.network_folder?
      raise ArgumentError, 'La destinazione è disattivata' unless destination.active?

      target_dir = allowed_folder_path!(destination)
      target = File.join(target_dir, File.basename(filename))
      return {target: target, simulated: true} if simulation

      raise ArgumentError, "Hot folder non disponibile: #{target_dir}" unless File.directory?(target_dir)
      raise ArgumentError, "Hot folder non scrivibile: #{target_dir}" unless File.writable?(target_dir)

      temporary = "#{target}.partial-#{Process.pid}-#{SecureRandom.hex(4)}"
      FileUtils.cp(source_path, temporary)
      File.rename(temporary, target)
      {target: target, simulated: false}
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def print_label(destination:, source_path:, simulation: false)
      raise ArgumentError, 'La destinazione non è una stampante etichette' unless destination.ipp_printer?
      raise ArgumentError, 'La destinazione è disattivata' unless destination.active?

      config = destination.config
      queue = config['queue'].to_s.strip
      server = config['cups_server'].to_s.strip
      command = ['lp']
      command.concat(['-h', server]) unless server.empty?
      command.concat(['-d', queue, '-n', config.fetch('copies', 1).to_i.to_s])
      command.concat(['-o', 'fit-to-page']) if config.fetch('fit_to_page', true)
      command.concat(['-o', "media=#{config['media']}"]) if config['media'].present?
      command.concat(['-o', "CutMedia=#{config['cut_mode']}"]) if config['cut_mode'].present?
      command << source_path

      return {command: command, simulated: true, job_id: nil, output: 'Stampa simulata'} if simulation

      stdout, stderr, status = capture(*command)
      raise ArgumentError, "Invio alla stampante fallito: #{stderr.presence || stdout}" unless status.success?

      {
        command: command,
        simulated: false,
        job_id: stdout[/\b#{Regexp.escape(queue)}-\d+\b/],
        output: stdout.strip
      }
    rescue Errno::ENOENT
      raise ArgumentError, 'Comando lp non disponibile: installare cups-client sul server'
    end

    def discover_printers(cups_server)
      command = ['lpstat']
      server = cups_server.to_s.strip
      command.concat(['-h', server]) unless server.empty?
      command << '-p'
      stdout, stderr, status = capture(*command)
      raise ArgumentError, "Server CUPS non raggiungibile: #{stderr.presence || stdout}" unless status.success?

      stdout.lines.filter_map do |line|
        match = line.match(/\Aprinter\s+(\S+)\s+is\s+(.+)\z/i)
        next unless match

        {queue: match[1], status: match[2].strip}
      end
    rescue Errno::ENOENT
      raise ArgumentError, 'Comando lpstat non disponibile: installare cups-client nel container'
    end

    def allowed_folder_path!(destination)
      root = Pathname.new(
        ENV.fetch('AUTOMATION_DESTINATIONS_ROOT', '/destinations')
      ).expand_path
      target = Pathname.new(destination.config['container_path'].to_s).expand_path
      unless target == root || target.to_s.start_with?("#{root}/")
        raise ArgumentError, "Il percorso deve trovarsi sotto #{root}"
      end

      target.to_s
    end

    private

    def check_network_folder(destination)
      path = allowed_folder_path!(destination)
      if !File.exist?(path)
        Result.new(
          success?: false,
          message: 'Cartella non disponibile sul server',
          details: {path: path}
        )
      elsif !File.directory?(path)
        Result.new(success?: false, message: 'Il percorso non è una cartella', details: {path: path})
      elsif !File.writable?(path)
        Result.new(success?: false, message: 'Cartella raggiungibile ma non scrivibile', details: {path: path})
      else
        Result.new(
          success?: true,
          message: 'Hot folder raggiungibile e scrivibile',
          details: {path: path}
        )
      end
    end

    def check_ipp_printer(destination)
      config = destination.config
      command = ['lpstat']
      server = config['cups_server'].to_s.strip
      command.concat(['-h', server]) unless server.empty?
      command.concat(['-p', config['queue'].to_s])
      stdout, stderr, status = capture(*command)
      Result.new(
        success?: status.success?,
        message: status.success? ? stdout.strip : "Stampante non raggiungibile: #{stderr.presence || stdout}",
        details: {queue: config['queue'], cups_server: server}
      )
    rescue Errno::ENOENT
      Result.new(
        success?: false,
        message: 'Comando lpstat non disponibile: installare cups-client sul server',
        details: {}
      )
    end

    def capture(*command)
      Timeout.timeout(10) { Open3.capture3({'LC_ALL' => 'C'}, *command) }
    rescue Timeout::Error
      raise ArgumentError, 'Tempo scaduto durante la verifica della destinazione'
    end
  end
end
