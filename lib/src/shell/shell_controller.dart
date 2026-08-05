import 'package:flutter/foundation.dart';

import '../data/authenticator.dart';
import '../data/discourse_api.dart';
import '../data/instance_store.dart';
import '../data/user_api_key.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/sidebar.dart';

/// Which pane occupies the space next to the rail when the shell is compact.
///
/// Only one of them can be on screen at a time on a phone; the rail itself is
/// always visible alongside whichever one is showing.
enum MobilePane { sidebar, content }

/// Everything the shell needs to decide what to draw.
///
/// Deliberately a plain [ChangeNotifier] so the skeleton carries no state
/// management dependency. Swapping in Riverpod or Bloc later only touches
/// [ShellScope] and this class.
class ShellController extends ChangeNotifier {
  ShellController({
    required this.store,
    required this.api,
    required this.authenticator,
  });

  final InstanceStore store;
  final DiscourseApi api;
  final Authenticator authenticator;

  bool _connecting = false;

  /// True while the authorize flow is open, so the UI can show progress.
  bool get connecting => _connecting;

  String? _connectError;
  String? get connectError => _connectError;

  final List<DiscourseInstance> _instances = [];
  List<DiscourseInstance> get instances => List.unmodifiable(_instances);
  bool get hasInstances => _instances.isNotEmpty;

  bool _loaded = false;

  /// False until the stored sites have been read, so the shell can avoid
  /// flashing the empty state on launch.
  bool get loaded => _loaded;

  int _instanceIndex = 0;
  int get instanceIndex => _instanceIndex;
  DiscourseInstance? get currentInstance =>
      hasInstances ? _instances[_instanceIndex] : null;

  String? _destinationId;

  /// Id of the highlighted sidebar entry, or null once the user has navigated
  /// deeper than the entry the stack started from.
  String? get destinationId => _destinationId;

  final List<ContentRoute> _contentStack = [];
  List<ContentRoute> get contentStack => List.unmodifiable(_contentStack);
  ContentRoute? get currentContent =>
      _contentStack.isEmpty ? null : _contentStack.last;
  bool get canPopContent => _contentStack.length > 1;

  MobilePane _mobilePane = MobilePane.sidebar;
  MobilePane get mobilePane => _mobilePane;

  bool _rightSidebarVisible = true;
  bool get rightSidebarVisible => _rightSidebarVisible;

  Future<void> load() async {
    final stored = await store.load();
    _instances
      ..clear()
      ..addAll(stored);
    _instanceIndex = 0;
    _resetToInstanceDefault();
    _loaded = true;
    notifyListeners();
  }

  bool contains(String url) => _instances.any((i) => i.url == url);

  /// Appends a connected site and selects it.
  Future<void> addInstance(DiscourseInstance instance) async {
    if (contains(instance.url)) return;

    _instances.add(instance);
    _instanceIndex = _instances.length - 1;
    _resetToInstanceDefault();
    _mobilePane = MobilePane.sidebar;
    notifyListeners();

    await store.save(_instances);
  }

  Future<void> removeInstance(DiscourseInstance instance) async {
    final index = _instances.indexOf(instance);
    if (index < 0) return;

    _instances.removeAt(index);
    _instanceIndex = _instanceIndex.clamp(
      0,
      _instances.isEmpty ? 0 : _instances.length - 1,
    );
    _resetToInstanceDefault();
    notifyListeners();

    await store.save(_instances);
  }

  /// Sends the user to the current site to authorize, then records who they
  /// turned out to be.
  Future<void> connectCurrentInstance() async {
    final instance = currentInstance;
    if (instance == null || _connecting) return;

    _connecting = true;
    _connectError = null;
    notifyListeners();

    try {
      final credentials = await authenticator.connect(instance.url);
      final user = await api.currentUser(
        siteUrl: instance.url,
        apiKey: credentials.key,
      );
      _replaceInstance(
        instance,
        instance.copyWith(user: user, apiVersion: credentials.apiVersion),
      );
      await store.save(_instances);
    } on UserApiAuthException catch (e) {
      // Backing out of the browser is a normal thing to do, not an error.
      _connectError = e.failure == UserApiAuthFailure.cancelled
          ? null
          : e.message;
    } on SiteLookupException catch (e) {
      _connectError = e.message;
    } catch (e) {
      _connectError = 'Could not connect to ${instance.host}.';
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Forgets the key and who we were, leaving the site in the rail.
  Future<void> disconnectCurrentInstance() async {
    final instance = currentInstance;
    if (instance == null) return;

    await authenticator.disconnect(instance.url);
    _replaceInstance(instance, instance.copyWith(clearUser: true));
    notifyListeners();
    await store.save(_instances);
  }

  void _replaceInstance(DiscourseInstance old, DiscourseInstance updated) {
    final index = _instances.indexOf(old);
    if (index >= 0) _instances[index] = updated;
  }

  void _resetToInstanceDefault() {
    final instance = currentInstance;
    _contentStack.clear();

    if (instance == null) {
      _destinationId = null;
      return;
    }

    final destination = instance.defaultDestination;
    _destinationId = destination.id;
    _contentStack.add(ContentRoute.fromDestination(destination));
  }

  /// Tapping the already-selected instance is how you get back to its sidebar
  /// on a phone, where the sidebar and the content cannot both be visible.
  void selectInstance(int index) {
    assert(index >= 0 && index < _instances.length);
    if (index != _instanceIndex) {
      _instanceIndex = index;
      _resetToInstanceDefault();
    }
    _mobilePane = MobilePane.sidebar;
    notifyListeners();
  }

  void selectDestination(SidebarDestination destination) {
    _destinationId = destination.id;
    _contentStack
      ..clear()
      ..add(ContentRoute.fromDestination(destination));
    _mobilePane = MobilePane.content;
    notifyListeners();
  }

  /// Replaces the main region with something deeper, keeping a way back.
  void pushContent(ContentRoute route) {
    _contentStack.add(route);
    _mobilePane = MobilePane.content;
    notifyListeners();
  }

  /// Unwinds one step: first through the content stack, then — on compact
  /// layouts only — back out to the sidebar.
  ///
  /// Returns false when there is nothing left to unwind, which is the signal
  /// to let the platform handle the back gesture.
  bool handleBack({bool canReturnToSidebar = true}) {
    if (canPopContent) {
      _contentStack.removeLast();
      notifyListeners();
      return true;
    }
    if (canReturnToSidebar && _mobilePane == MobilePane.content) {
      _mobilePane = MobilePane.sidebar;
      notifyListeners();
      return true;
    }
    return false;
  }

  void showContentPane() {
    if (_mobilePane == MobilePane.content) return;
    _mobilePane = MobilePane.content;
    notifyListeners();
  }

  void toggleRightSidebar() {
    _rightSidebarVisible = !_rightSidebarVisible;
    notifyListeners();
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }
}
