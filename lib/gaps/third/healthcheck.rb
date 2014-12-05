module Gaps::Third
  class Healthcheck
    include Chalk::Log

    def initialize(app)
      @app = app
      @fresh = true
    end

    # TODO: maybe enable logging if a verbose mode is specified
    def call(env)
      if env['PATH_INFO'] == '/healthcheck'
        healthcheck(env)
      else
        @app.call(env)
      end
    end

    def healthcheck(env)
      begin
        do_healthcheck
      rescue StandardError => e
        log.error("An error occurred while trying to process healthcheck", e)
        [500, {}, ["Error!\n"]]
      end
    end

    def hook_service_maintenance_dir
      configatron.healthcheck.service_maintenance_dir
    end

    def hook_name
      configatron.healthcheck.name
    end

    def hook_host_maintenance_dir
      configatron.healthcheck.host_maintenance_dir
    end

    def service_maintenance_file
      File.join(hook_service_maintenance_dir, hook_name)
    end

    def service_maintenance?
      hook_service_maintenance_dir && File.exists?(service_maintenance_file)
    end

    def host_maintenance_file
      File.join(hook_host_maintenance_dir, 'healthcheck.txt')
    end

    def host_maintenance?
      return unless hook_host_maintenance_dir

      begin
        # hack around the fact that root can always open a file
        if Process::Sys.geteuid == 0
          perms = File.stat(host_maintenance_file).mode.to_s(8)
          case perms[3..5]
          when '644'
            return false
          when '000'
            # maintenance mode!
            return true
          else
            log.error("unexpected perms on #{host_maintenance_file}: #{perms}")
            return false
          end
        else
          File.open(host_maintenance_file, 'r').close
          return false
        end
      rescue Errno::ENOENT
        # treat non-existent file as not maintenance
        log.error("error: host_maintenance_file does not exist: " +
                  host_maintenance_file.inspect)
        return false
      rescue Errno::EACCES
        # maintenance mode!
        return true
      end
    end

    def do_healthcheck
      if service_maintenance?
        [404, {}, ["Service is in maintenance mode.\n"]]
      elsif host_maintenance?
        [404, {}, ["Host is in maintenance mode.\n"]]
      else
        [200, {}, ["Service is up.\n"]]
      end
    end
  end
end
