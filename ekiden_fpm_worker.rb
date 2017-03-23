
class EkidenFpmWorker
  @queue = "fpm"

  def self.perform(deb_repo, package_name, package_version, source_format, prefix, package_key, deb_filename)
    puts :start_fpm_worker

    puts [deb_repo, package_name, package_version, source_format, prefix, package_key, deb_filename].inspect

    app = EkidenApp.new(ENV["REPO_BUCKET"], ENV["S3_ACCESS_KEY_ID"], ENV["S3_SECRET_ACCESS_KEY"])

    # s3 get that object save to temp file
    app.fetch_object(package_key) do |local_package_path|
      puts "downloaded #{package_key} to #{local_package_path}"

      Dir.mktmpdir do |temp_dir|
        deb_out = File.join(temp_dir, deb_filename)
        args = [
          "fpm",
          "-t", "deb",
          "-n", package_name,
          "-v", package_version,
          "-s", source_format,
          "--prefix", prefix,
          "-p", deb_out,
          local_package_path,
        ]

        created_deb = system(*args)

        if created_deb
          deb_package = app.object_for_package_key(deb_filename)
          deb_package.write(:data => File.open(deb_out))

          EkidenDebS3Worker.make_add_work(deb_repo, deb_package.key)
        end
      end
    end

    puts :done_fpm_worker

    true
  rescue Resque::TermException, SignalException => signal

  end
end
