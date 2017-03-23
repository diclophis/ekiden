
class EkidenDebS3Worker < Marvin
  @queue = "deb-s3"
  @tmp_gpg_key_io = Tempfile.new("gpg-private-key")
  @gpg_private_key = Base64.decode64(ENV["GPG_PRIVATE_KEY"] || "")
  @tmp_gpg_key_io.write(@gpg_private_key)
  @tmp_gpg_key_io.flush

  def self.make_work(integration_id, event = nil)
    self.base_make_work(self, integration_id, event)
  end

  def self.make_add_work(integration_id, package = nil)
    self.make_work(integration_id, {"package" => package, "action" => "add"}.to_json)
  end

  def self.make_delete_work(integration_id, package = nil)
    self.make_work(integration_id, {"package" => package, "action" => "delete"}.to_json)
  end

  def self.work_on(integration_id, event_json)
    log ["deb-s3-started", integration_id, event_json]

    work_completed = false
    app = EkidenApp.new(ENV["REPO_BUCKET"], ENV["S3_ACCESS_KEY_ID"], ENV["S3_SECRET_ACCESS_KEY"])

    event = JSON.parse(event_json)

    # Event is an hash of package and action
    deb_repo = integration_id
    package = event["package"]
    action = event["action"]

    case action
      when "add"
        # s3 get that object save to temp file
        app.fetch_object(package) do |local_deb_path|
          log ["deb-s3-arguments", deb_repo, package, @tmp_gpg_key_io.path, local_deb_path]
          args = [
            'sh', 'gpg-agent-wrapper.sh',
            @tmp_gpg_key_io.path,
            'deb-s3', 'upload',
            '--bucket', ENV["REPO_BUCKET"],
            '--prefix=' + deb_repo,
            '--access-key-id=' + ENV['S3_ACCESS_KEY_ID'],
            '--secret-access-key=' + ENV['S3_SECRET_ACCESS_KEY'],
            '-c', 'stable',
            '-m', 'main',
            '--use-ssl',
            '--visibility=private',
            '--encryption',
            '--sign=' + ENV['GPG_KEY_FINGERPRINT'],
            local_deb_path]

          # system invoke s3-deb upload script
          work_completed = system(*args)
        end

      when "delete"
        args = [
          "deb-s3", "delete", package, "--bucket=" + deb_repo, "--arch=amd64",
          '--bucket', ENV["REPO_BUCKET"],
          '--prefix=' + deb_repo,
          '--access-key-id=' + ENV['S3_ACCESS_KEY_ID'],
          '--secret-access-key=' + ENV['S3_SECRET_ACCESS_KEY'],
          '-c', 'stable',
          '-m', 'main',
          '--use-ssl'
        ]
        work_completed = system(*args)
    end

    log ["deb-s3-stopped", deb_repo, package, action, work_completed]

    #TODO: failure to remanifest should not fail the job, because it will make the system block on bad debs
    true
  end
end
