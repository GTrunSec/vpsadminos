require 'osctl/exportfs/cli/command'

module OsCtl::ExportFS::Cli
  class Server < Command
    def list
      puts sprintf('%-20s %-12s %-20s %s', 'SERVER', 'STATE', 'NETIF', 'ADDRESS')

      OsCtl::ExportFS::Operations::Server::List.run.each do |s|
        cfg = s.open_config

        puts sprintf(
          '%-20s %-12s %-20s %s',
          s.name,
          s.running? ? 'running' : 'stopped',
          cfg.netif,
          cfg.address || '-'
        )
      end
    end

    def create
      require_args!('name')
      OsCtl::ExportFS::Operations::Server::Create.run(
        args[0],
        options: server_options,
      )
    end

    def delete
      require_args!('name')
      OsCtl::ExportFS::Operations::Server::Delete.run(args[0])
    end

    def set
      require_args!('name')
      OsCtl::ExportFS::Operations::Server::Configure.run(
        OsCtl::ExportFS::Server.new(args[0]),
        server_options,
      )
    end

    def start
      require_args!('name')
      runsv = OsCtl::ExportFS::Operations::Server::Runsv.new(args[0])
      runsv.start
    end

    def stop
      require_args!('name')
      runsv = OsCtl::ExportFS::Operations::Server::Runsv.new(args[0])
      runsv.stop
    end

    def restart
      require_args!('name')
      runsv = OsCtl::ExportFS::Operations::Server::Runsv.new(args[0])
      runsv.restart
    end

    def spawn
      require_args!('name')
      OsCtl::ExportFS::Operations::Server::Spawn.run(args[0])
    end

    def attach
      require_args!('name')
      OsCtl::ExportFS::Operations::Server::Attach.run(args[0])
    end

    protected
    def server_options
      {
        address: opts['address'],
        netif: opts['netif'],
        nfsd: {
          port: opts['nfsd-port'],
          nproc: opts['nfsd-nproc'],
          tcp: opts['nfsd-tcp'],
          udp: opts['nfsd-udp'],
          versions: parse_nfs_versions(opts['nfs-versions']),
          syslog: opts['nfsd-syslog'],
        },
        mountd_port: opts['mountd-port'],
        lockd_port: opts['lockd-port'],
        statd_port: opts['statd-port'],
      }
    end

    def parse_nfs_versions(opt)
      return if opt.nil?

      ret = opt.split(',')
      choices = OsCtl::ExportFS::Config::Nfsd::VERSIONS

      ret.each do |v|
        unless choices.include?(v)
          fail "invalid NFS version '#{v}', possible values are: #{choices.join(', ')}"
        end
      end

      ret
    end
  end
end