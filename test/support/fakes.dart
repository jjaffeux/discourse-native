import 'package:discourse_native/src/data/authenticator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';

/// Keeps instances in memory instead of shared_preferences, which needs a
/// platform channel.
class FakeInstanceStore implements InstanceStore {
  FakeInstanceStore([this._instances = const []]);

  List<DiscourseInstance> _instances;
  int saveCount = 0;

  @override
  Future<List<DiscourseInstance>> load() async => _instances;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    _instances = List.of(instances);
    saveCount++;
  }
}

/// Answers lookups from a map of term to result, with no network involved.
class FakeDiscourseApi implements DiscourseApi {
  FakeDiscourseApi({this.results = const {}, this.failure, this.user});

  final Map<String, DiscourseInstance> results;
  final SiteLookupFailure? failure;

  /// Returned by [currentUser]; defaults to a plausible account.
  final DiscourseUser? user;

  final List<String> lookups = [];

  @override
  Duration get timeout => const Duration(seconds: 10);

  @override
  Future<DiscourseInstance> lookup(String term) async {
    lookups.add(term);
    final result = results[term];
    if (result != null) return result;
    throw SiteLookupException(
      failure ?? SiteLookupFailure.unreachable,
      term,
    );
  }

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => user ?? const DiscourseUser(username: 'joffreyj', name: 'Joffrey');

  @override
  void close() {}
}

DiscourseInstance instance(String host, {String? title}) => DiscourseInstance(
  url: 'https://$host',
  title: title ?? host,
  apiVersion: 4,
);

/// Runs the handshake without a browser or a keychain.
class FakeAuthenticator implements Authenticator {
  FakeAuthenticator({this.credentials, this.failure});

  final UserApiCredentials? credentials;
  final UserApiAuthFailure? failure;

  final List<String> connected = [];
  final List<String> disconnected = [];
  final Map<String, String> keys = {};

  @override
  Future<UserApiCredentials> connect(String siteUrl) async {
    if (failure != null) throw UserApiAuthException(failure!);
    connected.add(siteUrl);
    final result =
        credentials ??
        const UserApiCredentials(key: 'api-key', apiVersion: 4, push: false);
    keys[siteUrl] = result.key;
    return result;
  }

  @override
  Future<void> disconnect(String siteUrl) async {
    disconnected.add(siteUrl);
    keys.remove(siteUrl);
  }

  @override
  Future<String?> apiKeyFor(String siteUrl) async => keys[siteUrl];

  @override
  String get applicationName => 'Discourse Native';

  @override
  UserApiKeyProtocol get protocol => const UserApiKeyProtocol();

  @override
  SecureStore get store => throw UnimplementedError();
}
