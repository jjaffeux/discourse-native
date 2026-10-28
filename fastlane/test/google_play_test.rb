require "minitest/autorun"
require "minitest/mock"
require "fastlane"
require "tempfile"

class GooglePlayFastfile < Fastlane::FastFile
  def opt_out_usage; end
  def default_platform(_platform); end
  def sh(*arguments, **_options)
    "/test/rustup" if arguments == ["brew", "--prefix", "rustup"]
  end
  def build_google_play_app(_options) = "/test/Discourse.aab"
  def upload_to_play_store(**_options); end
  def google_play_track_version_codes(**_options); end
end

class PlayBuildNumberClient
  attr_reader :current_edit, :aborted

  def initialize(aabs:, apks:, error: nil)
    @aabs, @apks, @error = aabs, apks, error
  end

  def begin_edit(package_name:)
    @current_edit = package_name
  end

  def aab_version_codes
    raise @error if @error
    @aabs
  end

  def apks_version_codes = @apks

  def abort_current_edit
    @current_edit = nil
    @aborted = true
  end
end

Fastlane.load_actions
GOOGLE_PLAY_FASTFILE = GooglePlayFastfile.new(File.expand_path("../Fastfile", __dir__))

class GooglePlayTest < Minitest::Test
  def test_verify_checks_this_apps_internal_track_without_building_or_uploading
    with_service_account do |key|
      query = nil
      GOOGLE_PLAY_FASTFILE.stub(:build_google_play_app, ->(*) { flunk "Verification must not build" }) do
        GOOGLE_PLAY_FASTFILE.stub(:upload_to_play_store, ->(**) { flunk "Verification must not upload" }) do
          GOOGLE_PLAY_FASTFILE.stub(:google_play_track_version_codes, ->(**options) { query = options; [1] }) do
            GOOGLE_PLAY_FASTFILE.stub(:next_android_build_number, "2") do
              GOOGLE_PLAY_FASTFILE.runner.execute(:verify, :android, { json_key: key })
            end
          end
        end
      end
      assert_equal({ package_name: "org.discourse.native", json_key: key, track: "internal" }, query)
    end
  end

  def test_version_codes_are_positive_global_integers_within_the_play_limit
    %w[1 135 2100000000].each do |value|
      assert_equal value, GOOGLE_PLAY_FASTFILE.android_build_number(build_number: value)
    end
    [nil, "", "0", "-1", "1.1", "12abc", "2100000001"].each do |value|
      assert_raises(FastlaneCore::Interface::FastlaneError) do
        GOOGLE_PLAY_FASTFILE.android_build_number(build_number: value)
      end
    end
  end

  def test_beta_uploads_only_the_bundle_to_internal_testing_by_default
    with_service_account do |key|
      uploads = []
      GOOGLE_PLAY_FASTFILE.stub(:upload_to_play_store, ->(**options) { uploads << options }) do
        GOOGLE_PLAY_FASTFILE.runner.execute(:beta, :android, { json_key: key, build_number: 2 })
      end
      assert_equal 1, uploads.length
      upload = uploads.fetch(0)
      assert_equal "org.discourse.native", upload.fetch(:package_name)
      assert_equal "internal", upload.fetch(:track)
      assert_equal "completed", upload.fetch(:release_status)
      assert_equal "/test/Discourse.aab", upload.fetch(:aab)
      assert_equal key, upload.fetch(:json_key)
      %i[skip_upload_apk skip_upload_metadata skip_upload_changelogs skip_upload_images skip_upload_screenshots].each do |option|
        assert_equal true, upload.fetch(option)
      end
    end
  end

  def test_draft_uploads_are_opt_in_and_still_use_internal_testing
    with_service_account do |key|
      upload = nil
      GOOGLE_PLAY_FASTFILE.stub(:upload_to_play_store, ->(**options) { upload = options }) do
        GOOGLE_PLAY_FASTFILE.runner.execute(:beta, :android, { json_key: key, build_number: 2, draft: true })
      end
      assert_equal "draft", upload.fetch(:release_status)
      assert_equal "internal", upload.fetch(:track)
    end
  end

  def test_missing_play_credentials_fail_before_building
    original = ENV.delete("GOOGLE_PLAY_JSON_KEY_PATH")
    GOOGLE_PLAY_FASTFILE.stub(:build_google_play_app, ->(*) { flunk "Must not build without upload credentials" }) do
      assert_raises(FastlaneCore::Interface::FastlaneError) do
        GOOGLE_PLAY_FASTFILE.runner.execute(:beta, :android, {})
      end
    end
  ensure
    ENV["GOOGLE_PLAY_JSON_KEY_PATH"] = original
  end

  def test_selects_the_next_global_android_version_code_from_bundles_and_apks
    [[[], [], "1"], [["42", "7"], [103], "104"]].each do |aabs, apks, expected|
      client = PlayBuildNumberClient.new(aabs: aabs, apks: apks)
      with_service_account do |key|
        Supply::Client.stub(:make_from_config, client) do
          assert_equal expected, GOOGLE_PLAY_FASTFILE.next_android_build_number(json_key: key)
        end
      end
      assert client.aborted
    end
  end

  def test_version_lookup_cleans_up_its_edit_after_an_api_error
    client = PlayBuildNumberClient.new(aabs: [], apks: [], error: RuntimeError.new("API unavailable"))
    with_service_account do |key|
      Supply::Client.stub(:make_from_config, client) do
        error = assert_raises(RuntimeError) do
          GOOGLE_PLAY_FASTFILE.next_android_build_number(json_key: key)
        end
        assert_equal "API unavailable", error.message
      end
    end
    assert client.aborted
  end

  def test_beta_automatically_uses_the_next_build_number
    with_service_account do |key|
      build = nil
      GOOGLE_PLAY_FASTFILE.stub(:next_android_build_number, "104") do
        GOOGLE_PLAY_FASTFILE.stub(:build_google_play_app, ->(options) { build = options; "/test/Discourse.aab" }) do
          GOOGLE_PLAY_FASTFILE.runner.execute(:beta, :android, { json_key: key, version: "1.1.0" })
        end
      end
      assert_equal "104", build.fetch(:build_number)
      assert_equal "1.1.0", build.fetch(:version)
    end
  end

  private

  def with_service_account
    Tempfile.create(["google-play-test-", ".json"]) do |file|
      file.write("{}")
      file.flush
      yield file.path
    end
  end
end
