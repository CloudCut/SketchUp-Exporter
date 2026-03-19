module CloudCut
  module Exporter
    module Updater

      # ── Configure these to match your GitHub repo ──
      GITHUB_OWNER = "CloudCut"
      GITHUB_REPO  = "SketchUp-Exporter"

      # Don't check more than once per hour
      CHECK_INTERVAL_SECONDS = 3600

      PREF_SECTION = "CloudCut_Exporter"

      def self.current_version
        EXTENSION.version
      end

      @checked_this_session = false

      # Called on first use of the extension each session.
      # Only checks once — subsequent calls are no-ops.
      def self.check_once
        return if @checked_this_session
        @checked_this_session = true
        check_for_update(silent: true)
      end

      # Entry point — called from the menu item.
      # Always hits the network and reports even if up-to-date.
      def self.check_for_update(silent: false)
        url = "https://api.github.com/repos/#{GITHUB_OWNER}/#{GITHUB_REPO}/releases/latest"

        request = Sketchup::Http::Request.new(url, Sketchup::Http::GET)
        request.headers = { "Accept" => "application/vnd.github.v3+json",
                            "User-Agent" => "CloudCut-Exporter/#{current_version}" }

        request.start do |_req, response|
          Sketchup.write_default(PREF_SECTION, "last_update_check", Time.now.to_i.to_s)

          if response.status_code != 200
            unless silent
              UI.messagebox("Could not check for updates.\nHTTP #{response.status_code}")
            end
            next
          end

          handle_response(response.body, silent)
        end
      rescue => e
        unless silent
          UI.messagebox("Update check failed: #{e.message}")
        end
      end

      # ── private helpers ────────────────────────────

      def self.handle_response(body, silent)
        data = JSON.parse(body)
        remote_version = data["tag_name"].to_s.sub(/\Av/i, "")
        download_url   = find_rbz_asset(data["assets"])

        if newer?(remote_version, current_version)
          prompt_update(remote_version, download_url, data["html_url"])
        elsif !silent
          UI.messagebox("You're up to date! (v#{current_version})")
        end
      rescue => e
        UI.messagebox("Error parsing update info: #{e.message}") unless silent
      end

      def self.prompt_update(remote_version, download_url, release_url)
        if download_url
          choice = UI.messagebox(
            "CNC Exporter v#{remote_version} is available (you have v#{current_version}).\n\n" \
            "Download and install now?",
            MB_YESNO
          )
          download_and_install(download_url) if choice == IDYES
        else
          choice = UI.messagebox(
            "CNC Exporter v#{remote_version} is available (you have v#{current_version}).\n\n" \
            "No .rbz found in the release assets.\n" \
            "Open the release page to download manually?",
            MB_YESNO
          )
          UI.openURL(release_url) if choice == IDYES
        end
      end

      def self.download_and_install(url)
        request = Sketchup::Http::Request.new(url, Sketchup::Http::GET)
        request.headers = { "Accept" => "application/octet-stream",
                            "User-Agent" => "CloudCut-Exporter/#{current_version}" }

        request.start do |_req, response|
          if response.status_code != 200
            UI.messagebox("Download failed (HTTP #{response.status_code}).")
            next
          end

          tmp_dir  = File.join(Sketchup.temp_dir, "cloudcut_exporter_update")
          Dir.mkdir(tmp_dir) unless File.directory?(tmp_dir)
          rbz_path = File.join(tmp_dir, "cloudcut_exporter.rbz")

          File.binwrite(rbz_path, response.body)

          Sketchup.install_from_archive(rbz_path)

          UI.messagebox(
            "CNC Exporter has been updated!\n\n" \
            "Please restart SketchUp for changes to take effect."
          )
        end
      rescue => e
        UI.messagebox("Update install failed: #{e.message}")
      end

      def self.find_rbz_asset(assets)
        return nil unless assets.is_a?(Array)
        asset = assets.find { |a| a["name"].to_s.end_with?(".rbz") }
        asset ? asset["browser_download_url"] : nil
      end

      # Simple semver comparison: "1.2.0" > "1.1.0"
      def self.newer?(remote, local)
        remote_parts = remote.split(".").map(&:to_i)
        local_parts  = local.split(".").map(&:to_i)
        # Pad to equal length
        max = [remote_parts.length, local_parts.length].max
        remote_parts.fill(0, remote_parts.length...max)
        local_parts.fill(0, local_parts.length...max)
        remote_parts.zip(local_parts).each do |r, l|
          return true  if r > l
          return false if r < l
        end
        false
      end

      def self.should_check?
        last = Sketchup.read_default(PREF_SECTION, "last_update_check", "0").to_i
        (Time.now.to_i - last) > CHECK_INTERVAL_SECONDS
      end

    end # module Updater
  end
end
