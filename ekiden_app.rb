
class EkidenApp
  def initialize(repo_bucket = nil, aws_access_key_id = nil, aws_secret_access_key = nil, aws_region = "us-west-2")
    @repo_bucket = repo_bucket
    @s3_access_key_id = aws_access_key_id
    @s3_secret_access_key = aws_secret_access_key
    @s3_region = aws_region

    self.instance_variables.each do |required_instance|
      has_instance = instance_eval(required_instance.to_s)
      raise "#{required_instance} missing from ENV... ensure #{required_instance.upcase.to_s.gsub('@', '')} is correct" unless has_instance
    end

    @connection = Fog::Storage.new(
      provider: 'AWS',
      aws_access_key_id: @s3_access_key_id,
      aws_secret_access_key: @s3_secret_access_key,
      region: @s3_region
    )

    AWS.config({
      :access_key_id => @s3_access_key_id,
      :secret_access_key => @s3_secret_access_key,
      :logger => Class.new {
        def method_missing(*args)
          # puts args.inspect
        end
      }.new
    })

    @s3 = AWS::S3.new
    @bucket = @s3.buckets[(@repo_bucket)]
  end

  def index
    lambda { |env|
      files_in_repo = list_bucket
      bucket = @bucket

      mab = Markaby::Builder.new
      mab.html5 do
        head { title "repo" }
        body do
          h1 "package repo 1.0"
          h2 "files"
          ul do
            files_in_repo.each do |file|
              li do
                h3 file
                if file.end_with?("binary-amd64/Packages")
                  pre do
                    bucket.objects[file].read.split("\n").each do |line|
                      if line.start_with?("Package: ")
                        form(:action => "/delete", :method => "POST", :enctype => "multipart/form-data") do
                          input :type => "hidden", :name => "_method", :value => "DELETE"
                          input :type => "hidden", :name => "deb_repo", :value => file.split("/")[0]
                          input :type => "hidden", :name => "package", :value => line.split(": ")[1]
                          h3 line
                          input :type => "submit", :value => "X"
                        end
                      else
                        span line
                      end
                      br
                    end
                  end
                end
              end
            end
          end
          div do
            form(:action => "/incoming", :method => "POST", :enctype => "multipart/form-data") do
              input :type => "text", :name => "deb_repo"
              input :type => "file", :name => "package"
              input :type => "submit"
            end
          end
        end
      end

      res = StringIO.new(mab.to_s)
      headers = {}

      [200, headers, res]
    }
  end

  def get_packages(deb_repo)
    object = @bucket.objects[File.join(deb_repo, "dists/stable/main/binary-amd64/Packages")]
    package_prefix = "Package: "
    version_prefix = "Version: "
    filter_prefix = package_prefix #TODO: parameterized filtering? "#{package_prefix}#{app}-"
    packages = (object.read || "").split("\n").reject { |line|
      line == nil || line.length == 0 || (!line.starts_with?(package_prefix) && !line.starts_with?(version_prefix))
    }.each_slice(2).map { |meta_lines|
      meta_lines.map { |meta_line|
        meta_line.split(": ")[1]
      }
    }.to_h
  end

  def list_packages
    lambda { |env|
      req = Rack::Request.new(env)
      headers = {"Content-Type" => "application/json"}

      deb_repo = req.params["deb_repo"]
      specific_deb = req.params["specific_deb"]
      retry_attempts = req.params["retry_attempts"] || 60

      return_status = nil

      retry_attempts.to_i.times do |i|
        if specific_deb
          found = get_packages(deb_repo)[specific_deb]
          return_status = [found ? 200 : 500, headers, StringIO.new(found ? specific_deb : "")]

          break if found
        else
          return_status = [200, headers, StringIO.new(JSON.dump({ deb_repo => get_packages(deb_repo) }))]

          break
        end
      end

      return return_status
    }
  end

  def object_for_package_key(package_key)
    @bucket.objects[File.join("packages", package_key)]
  end

  def create_deb
    lambda { |env|
      headers = {"Content-Type" => "text/plain"}

      return client_fault "you may only POST here" unless env["REQUEST_METHOD"] == "POST"

      return_status = [200, headers, StringIO.new("OK")]

      req = Rack::Request.new(env)

      deb_repo = req.params["deb_repo"]
      package = req.params["package"] #NOTE: this is file upload

      raise ArgumentError.new("you must specify :deb_repo and :package") unless deb_repo && package

      if package && package.is_a?(Hash) && package[:filename] && package[:filename].end_with?(".deb")
        package_name = package[:filename]

        package_object = self.object_for_package_key(package_name)

        if package && package.is_a?(Hash) && package[:tempfile]
          package_object.write(:data => package[:tempfile])

          return_status = [201, headers, StringIO.new("UPLOADED")]
        end

        EkidenDebS3Worker.make_add_work(deb_repo, package_object.key)
      else
        package_name = req.params["package_name"]
        package_version = req.params["package_version"]
        source_format = req.params["source_format"]
        prefix = req.params["prefix"]

        deb_filename = "#{package_name}-#{package_version}.deb"

        package_key = File.basename(env["REQUEST_URI"])

        raise "missing params" unless deb_repo && package_name && package_version && source_format && prefix && package_key && deb_filename

        package_object = self.object_for_package_key(package_key)

        if package && package.is_a?(Hash) && package[:tempfile]
          package_object.write(:data => package[:tempfile])

          return_status = [201, headers, StringIO.new("CREATED")]
        end

        Resque.enqueue(EkidenFpmWorker, deb_repo, package_name, package_version, source_format, prefix, package_object.key, deb_filename)
      end

      return return_status
    }
  end

  def delete_package
    lambda { |env|
      req = Rack::Request.new(env)

      return client_fault "you may only DELETE here" unless (env["REQUEST_METHOD"] == "DELETE" || req["_method"] == "DELETE")

      deb_repo = req.params["deb_repo"]
      package = req.params["package"] #NOTE: this is file upload

      EkidenDebS3Worker.reset_work(deb_repo)
      EkidenDebS3Worker.make_delete_work(deb_repo, package)

      headers = {
        "Content-Type" => "text/plain",
        "Location" => "/"
      }
      return_status = [301, headers, StringIO.new("DELETED")]

      return return_status
    }
  end

  def create_package
    lambda { |env|
      headers = {"Content-Type" => "text/plain"}

      return client_fault "you may only POST here" unless env["REQUEST_METHOD"] == "POST"

      filename = File.basename(env["REQUEST_URI"])
      raise "not a deb" unless ((filename.end_with?(".deb")) && (filename != ".deb"))

      object = self.object_for_package_key(filename)

      req = Rack::Request.new(env)

      #TODO: more validation
      deb_repo = req.params["deb_repo"]
      deb_url = req.params["deb_url"]
      deb_package = req.params["deb_package"]
      deb_io = nil

      unless object.exists?

        if deb_url
          begin
            deb_uri = URI.parse(deb_url)
          rescue URI::InvalidURIError => error
            return client_fault(error.to_s)
          end

          begin
            fetched = Net::HTTP.get(deb_uri)
            deb_io = StringIO.new(fetched)
          rescue SocketError => error
            return client_fault(error.to_s)
          end
        elsif deb_package
          deb_io = deb_package[:tempfile]
        end

        written_to_s3 = object.write(:data => deb_io)

        object = written_to_s3

        return_status = [201, headers, StringIO.new("CREATED")]
      else
        return_status = [200, headers, StringIO.new("OK")]
      end

      EkidenDebS3Worker.make_add_work(deb_repo, object.key)

      return return_status
    }
  end

  def reschedule_work
    lambda { |env|
      headers = {"Content-Type" => "text/plain"}

      return client_fault "you may only POST here" unless env["REQUEST_METHOD"] == "POST"

      req = Rack::Request.new(env)

      uri = env["REQUEST_URI"]

      package_key = nil
      deb_repo = nil

      case uri.count("/")
        when 3 # /reschedule/<repo>/<key>
          package_key = File.basename(uri)
          deb_repo = File.basename(File.dirname(uri))

        when 2 # /reschedule/<repo>
          deb_repo = File.basename(uri)
      end

      reset_work = req.params["reset_work"] && (req.params["reset_work"] == "true")

      work_on_package_key = nil

      if package_key && object = object_for_package_key(package_key)
        work_on_package_key = object.key
      end

      if reset_work
        EkidenDebS3Worker.reset_work(deb_repo)
      end

      EkidenDebS3Worker.make_add_work(deb_repo, work_on_package_key)

      return [200, headers, StringIO.new("OK")]
    }
  end

  def list_bucket(path = "")
    @connection.directories.get(@repo_bucket, prefix: path).files.map do |file|
      file.key
    end
  end

  def client_fault(msg)
    [422, {}, StringIO.new(msg)]
  end

  def fetch_object(object_key)
    s3_object = @bucket.objects[object_key]
    if s3_object && s3_object.exists?
      Dir.mktmpdir('ekiden') do |temp_dir|
        temp_object = File.new(File.join(temp_dir, File.basename(object_key)), 'w+')
        temp_object.write(s3_object.read)
        temp_object.close
        yield temp_object.path
      end
    end
  end
end
