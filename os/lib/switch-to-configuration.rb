#!@ruby@/bin/ruby

class Configuration
  OUT = '@out@'
  ETC = '@etc@'
  SERVICE_DIR = '/etc/service'
  CURRENT_BIN = '/run/current-system/sw/bin'
  NEW_BIN = File.join(OUT, 'sw', 'bin')

  def self.switch
    new(dry_run: false).switch
  end

  def self.dry_run
    new(dry_run: true).dry_run
  end

  def initialize(dry_run: true)
    @opts = {dry_run: dry_run}
  end

  def dry_run
    puts 'probing runit services...'
    services = Services.new(opts)

    puts 'probing pools...'
    pools = Pools.new(opts)
    pools.export
    pools.rollback

    if pools.error.any?
      puts "unable to handle pools: #{pools.error.map(&:name).join(',')}"
    end

    puts 'would stop deprecated services...'
    services.stop.each(&:stop)

    puts 'would activate the configuration...'
    activate

    puts 'would reload changed services...'
    services.reload.each(&:reload)

    puts 'would restart changed services...'
    services.restart.each(&:restart)

    puts 'would start new services...'
    services.start.each(&:start)
  end

  def switch
    puts 'probing runit services...'
    services = Services.new(opts)

    puts 'probing pools...'
    pools = Pools.new(opts)
    pools.export
    pools.rollback

    if pools.error.any?
      puts "unable to handle pools: #{pools.error.map(&:name).join(',')}"
    end

    puts 'stopping deprecated services...'
    services.stop.each(&:stop)

    puts 'activating the configuration...'
    activate

    puts 'reloading changed services...'
    services.reload.each(&:reload)

    puts 'restarting changed services...'
    services.restart.each(&:restart)

    puts 'starting new services...'
    services.start.each(&:start)
  end

  def activate
    return if opts[:dry_run]
    system(File.join(OUT, 'activate'))
  end

  protected
  attr_reader :opts
end

class Services
  RELOADABLE = %w(lxcfs)
  Service = Struct.new(:name, :path, :opts) do
    def ==(other)
      path == other.path
    end

    %i(start stop restart).each do |m|
      define_method(m) do
        puts "> sv #{m} #{name}"

        unless opts[:dry_run]
          system(File.join(Configuration::CURRENT_BIN, 'sv'), m.to_s, name)
        end
      end
    end

    def reload
      m = reload_method
      puts "> sv #{m} #{name}"

      unless opts[:dry_run]
        system(File.join(Configuration::CURRENT_BIN, 'sv'), m, name)
      end
    end

    def reload_method
      case name
      when 'lxcfs'
        '1'
      else
        'reload'
      end
    end
  end

  def initialize(dry_run: true)
    @opts = {dry_run: dry_run}
    @old_services = read(Configuration::SERVICE_DIR)
    @new_services = read(File.join(Configuration::ETC, Configuration::SERVICE_DIR))
  end

  # Services that are new and should be started
  # @return [Array<Service>]
  def start
    (new_services.keys - old_services.keys).map { |s| new_services[s] }
  end

  # Services that have been removed and should be stopped
  # @return [Array<Service>]
  def stop
    (old_services.keys - new_services.keys).map { |s| old_services[s] }
  end

  # Services that have been changed and should be restarted
  # @return [Array<Service>]
  def restart
    (old_services.keys & new_services.keys).select do |s|
      old_services[s] != new_services[s] && !RELOADABLE.include?(s)
    end.map { |s| new_services[s] }
  end

  # Services that have been changed and should be reloaded
  # @return [Array<Service>]
  def reload
    (old_services.keys & new_services.keys).select do |s|
      old_services[s] != new_services[s] && RELOADABLE.include?(s)
    end.map { |s| new_services[s] }
  end

  protected
  attr_reader :old_services, :new_services, :opts

  # Read service directory
  # @return [Hash<String, Service>]
  def read(dir)
    ret = {}

    Dir.entries(dir).each do |f|
      next if %w(. ..).include?(f)

      path = File.join(dir, f)
      next unless Dir.exist?(path)

      ret[f] = Service.new(f, File.realpath(File.join(path, 'run')), opts)
    end

    ret
  end
end

class Pools
  Pool = Struct.new(:name, :state, :rollback_version)

  attr_reader :uptodate, :to_upgrade, :to_rollback, :error

  def initialize(dry_run: true)
    @opts = {dry_run: dry_run}

    @uptodate = []
    @to_upgrade = []
    @to_rollback = []
    @error = []

    @old_pools = check(Configuration::CURRENT_BIN)
    @new_pools = check(Configuration::NEW_BIN)

    resolve
  end

  # Rollback pools using the current OS version, as the activated OS version
  # is older
  def rollback
    to_rollback.each do |pool|
      puts "> rolling back pool #{pool.name}"
      next if opts[:dry_run]

      ret = system(
        File.join(Configuration::CURRENT_BIN, 'osup'),
        'rollback', pool.name, pool.rollback_version
      )

      unless ret
        fail "rollback of pool #{pool.name} failed, cannot proceed"
      end
    end
  end

  # Export pools from osctld before upgrade
  #
  # This will stop all containers from outdated pools. We're counting on the
  # fact that if there are new migrations, then osctld has to have changed
  # as well, so it is restarted by {Services}. After restart, osctld will run
  # `osup upgrade` on all imported pools.
  def export
    (to_rollback + to_upgrade).each do |pool|
      puts "> exporting pool #{pool.name} to upgrade"
      next if opts[:dry_run]

      # TODO: do not fail if the pool is not imported
      ret = system(
        File.join(Configuration::CURRENT_BIN, 'osctl'),
        'pool', 'export', '-f', pool.name
      )

      unless ret
        fail "export of pool #{pool.name} failed, cannot proceed"
      end
    end
  end

  protected
  attr_reader :opts, :old_pools, :new_pools

  def resolve
    new_pools.each do |name, pool|
      case pool.state
      when :ok
        uptodate << pool

      when :outdated
        to_upgrade << pool

      when :incompatible
        if old_pools[name] && old_pools[name].state == :ok
          to_rollback << pool

        else
          error << pool
        end
      end
    end
  end

  def check(swbin)
    ret = {}

    IO.popen("#{File.join(swbin, 'osup')} check") do |io|
      io.each_line do |line|
        name, state, version = line.strip.split
        ret[name] = Pool.new(name, state.to_sym, version)
      end
    end

    ret

  rescue Errno::ENOENT
    # osup isn't available in the to-be-replaced OS version
    {}
  end
end

case ARGV[0]
when 'switch', 'boot', 'test'
  Configuration.switch

when 'dry-activate'
  Configuration.dry_run

else
  warn "Usage: #{$0} switch|dry-activate"
  exit(false)
end
