import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_controller.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_data.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'user_notes_fixture.dart';

void main() {
  test(
    'installed decoders own transient count fields and core ignores them',
    () async {
      final plugins = PluginInstaller.install(
        const PluginManifest([userNotesModule]),
      );
      addTearDown(plugins.close);
      final wire = {
        'id': 3,
        'post_number': 1,
        'username': 'mira',
        'user_custom_fields': {'user_notes_count': 2},
      };
      expect(
        plugins.models
            .post(wire, notesSite)
            .plugins
            .get(userNotesCountKey)!
            .value,
        2,
      );
      expect(
        const DiscourseModelCodec.core().post(wire, notesSite).plugins.isEmpty,
        isTrue,
      );
      final card = plugins.models.userCard({
        'id': 7,
        'username': 'mira',
        'custom_fields': {'user_notes_count': 1},
      }, notesSite);
      expect(card.plugins.get(userNotesCountKey)!.value, 1);
      final user = plugins.models.currentUser({
        'id': 7,
        'username': 'mira',
        'custom_fields': {'user_notes_count': 1},
      }, notesSite);
      expect(user.plugins.isEmpty, isTrue);
    },
  );
  test(
    'actual module installs narrowly scoped services without network while disabled',
    () async {
      final transport = RecordingPluginTransport();
      final host = await PluginHostHarness.open(
        transport: transport,
        manifest: const PluginManifest([userNotesModule]),
        sites: const [PluginHostSite(url: notesSite)],
      );
      addTearDown(host.close);
      expect(
        host.require(userNotesControllerService).canOpen(notesSite),
        isFalse,
      );
      expect(transport.requests, isEmpty);
    },
  );
}
