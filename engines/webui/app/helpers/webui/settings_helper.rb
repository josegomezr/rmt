module Webui
  module SettingsHelper
    def rmt_scc_config
      {
        host_system: Settings.scc.host_system,
        sync_systems?: !!Settings.scc.sync_systems,
        login: Settings.scc.username,
        registration_host: Settings.scc.host,
      }
    end

    def rmt_registered?
      rmt_scc_config[:host_system].present?
    end

    def rmt_uuid
      location = SUSE::Connect::Api::UUID_FILE_LOCATION
      return File.read(location) if File.exist?(location)

      '⚠ no uuid'
    end
  end
end
