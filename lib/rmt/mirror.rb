require 'rmt/downloader'
require 'rmt/gpg'
require 'repomd_parser'
require 'time'

class RMT::Mirror
  class FileReference
    class << self
      def build_from_metadata(metadata, base_dir:, base_url:, cache_dir: nil)
        new(base_dir: base_dir, base_url: base_url, cache_dir: cache_dir, location: metadata.location)
          .tap do |file|
            file.arch = metadata.arch
            file.checksum = metadata.checksum
            file.checksum_type = metadata.checksum_type
            file.size = metadata.size
            file.type = metadata.type
          end
      end
    end

    attr_reader :cache_path, :local_path, :remote_path, :location
    attr_accessor :arch, :checksum, :checksum_type, :size, :type

    def initialize(base_dir:, base_url:, cache_dir: nil, location:)
      @cache_path = (cache_dir ? File.join(cache_dir, location) : nil)
      @local_path = File.join(base_dir, location.gsub(/\.\./, '__'))
      @remote_path = URI.join(base_url, location)
      @location = location
    end

    def cache_timestamp
      File.mtime(cache_path).utc.httpdate if cache_path && File.exist?(cache_path)
    end
  end

  class RMT::Mirror::Exception < RuntimeError
  end

  include RMT::Deduplicator
  include RMT::FileValidator

  def initialize(mirroring_base_dir: RMT::DEFAULT_MIRROR_DIR, logger:, mirror_src: false, airgap_mode: false)
    @mirroring_base_dir = mirroring_base_dir
    @logger = logger
    @mirror_src = mirror_src
    @airgap_mode = airgap_mode
    @deep_verify = false

    @downloader = RMT::Downloader.new(
      logger: @logger,
      track_files: !airgap_mode # don't save files for deduplication when in offline mode
    )
  end

  def mirror_suma_product_tree(repository_url:)
    # we have an inconsistency in how we mirror in offline mode
    # in normal mode we mirror in the following way:
    # base_dir/repo/...
    # however, in offline mode we mirror in the following way
    # base_dir/...
    # we need this extra step to ensure that we write to the public directory
    base_dir = @mirroring_base_dir
    base_dir = File.expand_path(File.join(@mirroring_base_dir, '/../')) if @mirroring_base_dir == RMT::DEFAULT_MIRROR_DIR

    @repository_dir = File.join(base_dir, '/suma/')
    mirroring_paths = {
      base_url: URI.join(repository_url),
      base_dir: @repository_dir,
      cache_dir: @repository_dir
    }

    @logger.info _('Mirroring SUSE Manager product tree to %{dir}') % { dir: @repository_dir }
    product_tree = FileReference.new(location: 'product_tree.json', **mirroring_paths)
    @downloader.download(product_tree)
  rescue RMT::Downloader::Exception => e
    raise RMT::Mirror::Exception.new(_('Could not mirror SUSE Manager product tree with error: %{error}') % { error: e.message })
  end

  def mirror(repository_url:, local_path:, auth_token: nil, repo_name: nil)
    @repository_dir = File.join(@mirroring_base_dir, local_path)
    @repository_url = repository_url

    @logger.info _('Mirroring repository %{repo} to %{dir}') % { repo: repo_name || repository_url, dir: @repository_dir }

    create_directories
    mirror_license
    # downloading license doesn't require an auth token
    @downloader.auth_token = auth_token
    primary_files, deltainfo_files = mirror_metadata
    mirror_data(primary_files, deltainfo_files)

    replace_directory(@temp_licenses_dir, @repository_dir.chomp('/') + '.license/') if Dir.exist?(@temp_licenses_dir)
    replace_directory(File.join(@temp_metadata_dir, 'repodata'), File.join(@repository_dir, 'repodata'))
  ensure
    remove_tmp_directories
  end

  protected

  attr_reader :airgap_mode, :deep_verify, :logger

  def create_directories
    begin
      FileUtils.mkpath(@repository_dir) unless Dir.exist?(@repository_dir)
    rescue StandardError => e
      raise RMT::Mirror::Exception.new(_('Could not create local directory %{dir} with error: %{error}') % { dir: @repository_dir, error: e.message })
    end

    begin
      @temp_licenses_dir = Dir.mktmpdir
      @temp_metadata_dir = Dir.mktmpdir
    rescue StandardError => e
      raise RMT::Mirror::Exception.new(_('Could not create a temporary directory: %{error}') % { error: e.message })
    end
  end

  def mirror_metadata
    mirroring_paths = {
      base_url: URI.join(@repository_url),
      base_dir: @temp_metadata_dir,
      cache_dir: @repository_dir
    }

    repomd_xml = FileReference.new(location: 'repodata/repomd.xml', **mirroring_paths)
    @downloader.download(repomd_xml)

    begin
      signature_file = FileReference.new(location: 'repodata/repomd.xml.asc', **mirroring_paths)
      key_file       = FileReference.new(location: 'repodata/repomd.xml.key', **mirroring_paths)
      @downloader.download(signature_file)
      @downloader.download(key_file)

      RMT::GPG.new(
        metadata_file: repomd_xml.local_path,
        key_file: key_file.local_path,
        signature_file: signature_file.local_path,
        logger: @logger
      ).verify_signature
    rescue RMT::Downloader::Exception => e
      if (e.http_code == 404)
        @logger.info(_('Repository metadata signatures are missing'))
      else
        raise(_('Failed to get repository metadata signatures with HTTP code %{http_code}') % { http_code: e.http_code })
      end
    end

    metadata_files = RepomdParser::RepomdXmlParser.new(repomd_xml.local_path).parse
      .map { |reference| FileReference.build_from_metadata(reference, **mirroring_paths) }
    primary_files = metadata_files.select { |reference| reference.type == :primary }
    deltainfo_files = metadata_files.select { |reference| reference.type == :deltainfo }

    @downloader.download_multi(metadata_files)

    [primary_files, deltainfo_files]
  rescue StandardError => e
    raise RMT::Mirror::Exception.new(_('Error while mirroring metadata: %{error}') % { error: e.message })
  end

  def mirror_license
    mirroring_paths = {
      base_url: @repository_url.chomp('/') + '.license/',
      base_dir: @temp_licenses_dir,
      cache_dir: @repository_dir.chomp('/') + '.license/'
    }

    begin
      directory_yast = FileReference.new(location: 'directory.yast', **mirroring_paths)
      @downloader.download(directory_yast)
    rescue RMT::Downloader::Exception
      FileUtils.remove_entry(@temp_licenses_dir) # the repository would have an empty licenses directory unless removed
      return
    end

    license_files = File.readlines(directory_yast.local_path)
      .map(&:strip).reject { |item| item == 'directory.yast' }
      .map { |location| FileReference.new(location: location, **mirroring_paths) }
    @downloader.download_multi(license_files)
  rescue StandardError => e
    raise RMT::Mirror::Exception.new(_('Error while mirroring license: %{error}') % { error: e.message })
  end

  def mirror_data(primary_files, deltainfo_files)
    package_repomd_references =
      parse_mirror_data_files(deltainfo_files, RepomdParser::DeltainfoXmlParser) +
      parse_mirror_data_files(primary_files, RepomdParser::PrimaryXmlParser)

    package_file_references = package_repomd_references.map do |reference|
      FileReference.build_from_metadata(reference,
                                        base_dir: @repository_dir,
                                        base_url: @repository_url)
    end

    failed_downloads = download_package_files(package_file_references)

    raise _('Failed to download %{failed_count} files') % { failed_count: failed_downloads.size } unless failed_downloads.empty?
  rescue StandardError => e
    raise RMT::Mirror::Exception.new(_('Error while mirroring data: %{error}') % { error: e.message })
  end

  def parse_mirror_data_files(references, xml_parser_class)
    references.map do |reference|
      xml_parser_class.new(File.join(@temp_metadata_dir, reference.location)).parse
    end.flatten
  end

  def download_package_files(file_references)
    files_to_download = file_references.select { |file| need_to_download?(file) }
    return [] if files_to_download.empty?

    @downloader.download_multi(files_to_download, ignore_errors: true)
  end

  def need_to_download?(file)
    return false if file.arch == 'src' && !@mirror_src
    return false if validate_local_file(file)
    return false if deduplicate(file)

    true
  end

  def replace_directory(source_dir, destination_dir)
    old_directory = File.join(File.dirname(destination_dir), '.old_' + File.basename(destination_dir))

    FileUtils.remove_entry(old_directory) if Dir.exist?(old_directory)
    FileUtils.mv(destination_dir, old_directory) if Dir.exist?(destination_dir)
    FileUtils.mv(source_dir, destination_dir)
    FileUtils.chmod(0o755, destination_dir)
  rescue StandardError => e
    raise RMT::Mirror::Exception.new(_('Error while moving directory %{src} to %{dest}: %{error}') % {
      src: source_dir,
      dest: destination_dir,
      error: e.message
    })
  end

  def remove_tmp_directories
    FileUtils.remove_entry(@temp_licenses_dir) if @temp_licenses_dir && Dir.exist?(@temp_licenses_dir)
    FileUtils.remove_entry(@temp_metadata_dir) if @temp_metadata_dir && Dir.exist?(@temp_metadata_dir)
  end
end
