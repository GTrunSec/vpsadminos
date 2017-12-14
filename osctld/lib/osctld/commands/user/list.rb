module OsCtld
  class Commands::User::List < Commands::Base
    handle :user_list

    def execute
      ret = []

      UserList.get.each do |u|
        next if opts[:names] && !opts[:names].include?(u.name)
        next if opts.has_key?(:registered) && u.registered? != opts[:registered]

        ret << {
          name: u.name,
          username: u.username,
          groupname: u.groupname,
          ugid: u.ugid,
          ugid_offset: u.offset,
          ugid_size: u.size,
          dataset: u.dataset,
          homedir: u.homedir,
          registered: u.registered?,
        }
      end

      ok(ret)
    end
  end
end
