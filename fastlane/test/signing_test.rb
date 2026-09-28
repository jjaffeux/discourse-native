require "minitest/autorun"
require "minitest/mock"
require "fastlane"
require "gym"
require "gym/generators/package_command_generator_xcode7"

# Load the real lane, but never build, upload, or invoke shell commands in tests.
class SigningFastfile < Fastlane::FastFile
  def opt_out_usage; end
  def default_platform(_platform); end
  def sh(*_arguments); end
  def latest_testflight_build_number(**_options) = 134
  def upload_to_testflight(**_options); end

  def build_app(**_options)
    raise "build_app must be stubbed"
  end
end

Fastlane.load_actions
SIGNING_FASTFILE = SigningFastfile.new(File.expand_path("../Fastfile", __dir__))

class SigningTest < Minitest::Test
  def setup
    @temporary_root = Dir.mktmpdir("signing-test-")
    @directory = File.join(@temporary_root, "signing test files")
    Dir.mkdir(@directory)
    @api_key_path = File.join(@directory, "api-key.json")
    @private_key = OpenSSL::PKey::EC.generate("prime256v1").private_to_pem
    @key = {
      key_id: "TESTKEY123",
      issuer_id: "00000000-0000-0000-0000-000000000001",
      key: @private_key
    }
    write_api_key
  end

  def teardown
    FileUtils.remove_entry(@temporary_root)
  end

  def test_beta_authenticates_both_platforms_during_archive_and_export
    builds = []
    key_paths = []
    build = lambda do |**options|
      builds << options
      key_paths << verify_signing_arguments(options)
      "#{options.fetch(:output_name)}.#{builds.length == 1 ? 'ipa' : 'pkg'}"
    end

    SIGNING_FASTFILE.stub(:build_app, build) do
      SIGNING_FASTFILE.stub(:prune_testflight_artifacts, nil) do
        SIGNING_FASTFILE.stub(:prune_full_profile_build_cache, nil) do
          Dir.stub(:tmpdir, @directory) do
            SIGNING_FASTFILE.runner.lanes.fetch(nil).fetch(:beta).call(
              version: "1.1.0",
              api_key_path: @api_key_path,
              uses_non_exempt_encryption: false,
              skip_checks: true,
              allow_dirty: true,
              wait_for_processing: false
            )
          end
        end
      end
    end

    assert_equal 2, builds.length
    assert_match %r{/ios/Runner.xcworkspace\z}, builds[0].fetch(:workspace)
    assert_match %r{/macos/Runner.xcworkspace\z}, builds[1].fetch(:workspace)
    key_paths.each { |path| refute_path_exists path }
  end

  def test_removes_the_private_key_when_building_fails
    key_path = nil
    build = lambda do |**options|
      args = Shellwords.split(options.fetch(:xcargs))
      key_path = args.fetch(args.index("-authenticationKeyPath") + 1)
      assert_path_exists key_path
      raise "Export failed"
    end

    error = assert_raises(RuntimeError) do
      SIGNING_FASTFILE.stub(:build_app, build) do
        SIGNING_FASTFILE.build_testflight_app(api_key_path: @api_key_path)
      end
    end

    assert_equal "Export failed", error.message
    refute_path_exists key_path
  end

  def test_decodes_base64_keys_supported_by_fastlane
    @key[:key] = Base64.strict_encode64(@private_key)
    @key[:is_key_content_base64] = true
    write_api_key
    build = lambda do |**options|
      args = Shellwords.split(options.fetch(:xcargs))
      path = args.fetch(args.index("-authenticationKeyPath") + 1)
      assert_equal @private_key, File.read(path)
      "Discourse.ipa"
    end

    SIGNING_FASTFILE.stub(:build_app, build) do
      assert_equal "Discourse.ipa",
        SIGNING_FASTFILE.build_testflight_app(api_key_path: @api_key_path)
    end
  end

  def test_rejects_individual_keys_before_invoking_xcode
    @key.delete(:issuer_id)
    write_api_key

    error = assert_raises(FastlaneCore::Interface::FastlaneError) do
      SIGNING_FASTFILE.build_testflight_app(api_key_path: @api_key_path)
    end
    assert_match "team API key", error.message
  end

  private

  def write_api_key
    File.write(@api_key_path, JSON.generate(@key))
  end

  def verify_signing_arguments(options)
    args = Shellwords.split(options.fetch(:xcargs))
    path = args.fetch(args.index("-authenticationKeyPath") + 1)
    assert_equal @private_key, File.read(path)
    assert_equal 0o600, File.stat(path).mode & 0o777
    assert_includes path, "signing test "
    refute_includes options.fetch(:xcargs), @private_key

    project = Struct.new(:xcodebuild_parameters).new(["-scheme Runner"])
    cache = {
      archive_path: options.fetch(:archive_path),
      config_path: File.join(@directory, "ExportOptions.plist"),
      temporary_output_path: @directory
    }
    Gym.stub(:config, options) do
      Gym.stub(:project, project) do
        Gym.stub(:cache, cache) do
          # Exercise gym's actual command generators so a change in how it
          # forwards xcargs cannot silently break export authentication.
          [Gym::BuildCommandGenerator, Gym::PackageCommandGeneratorXcode7].each do |generator|
            command = Shellwords.split(generator.options.join(" "))
            assert_includes command, "-allowProvisioningUpdates"
            assert_includes command, "DEVELOPMENT_TEAM=6T3LU73T8S"
            {
              "-authenticationKeyPath" => path,
              "-authenticationKeyID" => @key.fetch(:key_id),
              "-authenticationKeyIssuerID" => @key.fetch(:issuer_id)
            }.each do |flag, value|
              assert_includes command, flag
              assert_equal value, command.fetch(command.index(flag) + 1)
              assert_equal 1, command.count(flag)
            end
          end
        end
      end
    end
    path
  end
end
