import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/discourse_instance.dart';

/// Persists the connected sites between launches.
///
/// Only public site metadata lives here. Credentials will need the keychain
/// instead, once there is a login flow.
class InstanceStore {
  static const String _key = 'discourse_native.instances';

  Future<List<DiscourseInstance>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => DiscourseInstance.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // A shape change should cost the user their list, not crash the app.
      return const [];
    }
  }

  Future<void> save(List<DiscourseInstance> instances) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(instances.map((i) => i.toJson()).toList()),
    );
  }
}
