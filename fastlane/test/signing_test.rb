require "minitest/autorun"
require "minitest/mock"
require "open3"
require "fastlane"
require "gym"
require "gym/generators/package_command_generator_xcode7"

# Load the real lane, but never build, upload, or invoke shell commands in tests.
class SigningFastfile < Fastlane::FastFile
  def opt_out_usage; end
  def default_platform(_platform); end
  def sh(*arguments, **_options)
    "/test homebrew/rustup" if arguments == ["brew", "--prefix", "rustup"]
  end
  def latest_testflight_build_number(**_options) = 134
  def upload_to_testflight(**_options); end
  def upload_to_play_store(**_options); end
  def next_android_build_number(**_options) = "42"
  def prune_testflight_artifacts(**_options); end
  def prune_full_profile_build_cache; end
  def build_google_play_app(_options)
    raise "build_google_play_app must be stubbed"
  end

  def build_app(**_options)
    raise "build_app must be stubbed"
  end
end

Fastlane.load_actions
SIGNING_FASTFILE = SigningFastfile.new(File.expand_path("../Fastfile", __dir__))

class SigningTest < Minitest::Test
  def setup
    @original_path = ENV["PATH"]
    @original_rustup_toolchain = ENV["RUSTUP_TOOLCHAIN"]
    @original_google_key = ENV["GOOGLE_PLAY_JSON_KEY_PATH"]
    @original_android_signing = ENV["ANDROID_KEY_PROPERTIES"]
    @temporary_root = Dir.mktmpdir("signing-test-")
    @directory = File.join(@temporary_root, "signing test files")
    Dir.mkdir(@directory)
    @api_key_path = File.join(@directory, "api-key.json")
    ENV["GOOGLE_PLAY_JSON_KEY_PATH"] = File.join(@directory, "google-key.json")
    ENV["ANDROID_KEY_PROPERTIES"] = File.join(@directory, "key.properties")
    File.write(ENV.fetch("GOOGLE_PLAY_JSON_KEY_PATH"), "{}")
    File.write(ENV.fetch("ANDROID_KEY_PROPERTIES"), "test signing configuration")
    @private_key = OpenSSL::PKey::EC.generate("prime256v1").private_to_pem
    @key = {
      key_id: "TESTKEY123",
      issuer_id: "00000000-0000-0000-0000-000000000001",
      key: @private_key
    }
    write_api_key
  end

  def teardown
    ENV["PATH"] = @original_path
    ENV["RUSTUP_TOOLCHAIN"] = @original_rustup_toolchain
    ENV["GOOGLE_PLAY_JSON_KEY_PATH"] = @original_google_key
    ENV["ANDROID_KEY_PROPERTIES"] = @original_android_signing
    FileUtils.remove_entry(@temporary_root)
  end

  def test_beta_builds_all_platforms_before_uploading_and_preserves_signing
    builds = []
    key_paths = []
    events = []
    android_options = nil
    android_upload = nil
    apple_uploads = []
    build = lambda do |**options|
      environment, status = Open3.capture2(
        "/bin/sh", "-c", 'printf "%s\n%s\n" "$PATH" "$RUSTUP_TOOLCHAIN"'
      )
      assert status.success?
      path, toolchain = environment.lines.map(&:chomp)
      assert_equal "/test homebrew/rustup/bin", path.split(File::PATH_SEPARATOR).first
      assert_equal "1.92.0", toolchain
      builds << options
      events << :build_apple
      key_paths << verify_signing_arguments(options)
      "#{options.fetch(:output_name)}.#{builds.length == 1 ? 'ipa' : 'pkg'}"
    end

    android_build = lambda do |options|
      events << :build_android
      android_options = options
      "Discourse-1.1.0-42.aab"
    end
    upload_android = lambda do |**options|
      events << :upload_android
      android_upload = options
    end
    upload_apple = lambda do |**options|
      events << :upload_apple
      apple_uploads << options
    end

    SIGNING_FASTFILE.stub(:build_google_play_app, android_build) do
      SIGNING_FASTFILE.stub(:upload_to_play_store, upload_android) do
        SIGNING_FASTFILE.stub(:upload_to_testflight, upload_apple) do
          SIGNING_FASTFILE.stub(:build_app, build) do
            Dir.stub(:tmpdir, @directory) do
              SIGNING_FASTFILE.runner.execute(:beta, nil, {
                version: "1.1.0",
                api_key_path: @api_key_path,
                uses_non_exempt_encryption: false,
                skip_checks: true,
                allow_dirty: true,
                wait_for_processing: false
              })
            end
          end
        end
      end
    end

    assert_equal 2, builds.length
    assert_equal [:build_apple, :build_apple, :build_android, :upload_android, :upload_apple, :upload_apple], events
    assert_equal "1.1.0", android_options.fetch(:version)
    assert_equal "42", android_options.fetch(:build_number)
    assert_equal "internal", android_upload.fetch(:track)
    assert_equal "completed", android_upload.fetch(:release_status)
    assert_equal "Discourse-1.1.0-42.aab", android_upload.fetch(:aab)
    assert_equal %w[ios osx], apple_uploads.map { |upload| upload.fetch(:app_platform) }
    assert_match /1\.1\.0-135\.ipa\z/, apple_uploads[0].fetch(:ipa)
    assert_match /1\.1\.0-136\.pkg\z/, apple_uploads[1].fetch(:pkg)
    assert_match %r{/ios/Runner.xcworkspace\z}, builds[0].fetch(:workspace)
    assert_match %r{/macos/Runner.xcworkspace\z}, builds[1].fetch(:workspace)
    key_paths.each { |path| refute_path_exists path }
  end

  def test_missing_android_credentials_fail_before_any_apple_build_or_upload
    ENV.delete("GOOGLE_PLAY_JSON_KEY_PATH")
    SIGNING_FASTFILE.stub(:build_app, ->(**) { flunk "Must fail before archiving Apple builds" }) do
      assert_raises(FastlaneCore::Interface::FastlaneError) do
        SIGNING_FASTFILE.runner.execute(:beta, nil, {
          version: "1.1.0", api_key_path: @api_key_path,
          uses_non_exempt_encryption: false, skip_checks: true, allow_dirty: true
        })
      end
    end
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

  def test_selects_local_distribution_signing_when_a_profile_is_configured
    export_options = {
      method: "app-store",
      signingStyle: "automatic",
      teamID: "6T3LU73T8S",
      uploadSymbols: true
    }
    build = lambda do |**options|
      assert_equal export_options.merge(
        signingStyle: "manual",
        signingCertificate: "Apple Distribution",
        provisioningProfiles: { "org.discourse.native" => "Local App Store profile" }
      ), options.fetch(:export_options)
      refute options.key?(:provisioning_profile)
    end

    SIGNING_FASTFILE.stub(:build_app, build) do
      SIGNING_FASTFILE.build_testflight_app(
        api_key_path: @api_key_path,
        provisioning_profile: "Local App Store profile",
        export_options: export_options
      )
    end
    assert_equal "automatic", export_options.fetch(:signingStyle)
  end

  def test_preserves_automatic_signing_for_a_blank_local_profile
    export_options = { signingStyle: "automatic" }
    build = ->(**options) { assert_equal export_options, options.fetch(:export_options) }

    SIGNING_FASTFILE.stub(:build_app, build) do
      SIGNING_FASTFILE.build_testflight_app(
        api_key_path: @api_key_path,
        provisioning_profile: " ",
        export_options: export_options
      )
    end
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
