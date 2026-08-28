import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';

/// Test-only shorthand for exercising Chat through an installed shell.
///
/// Production plugin code resolves [ChatShellService] from its scoped session;
/// this extension keeps shell-heavy fixtures concise without restoring a
/// concrete-shell compatibility API to the Chat implementation.
extension TestChatShell on ShellController {
  ChatShellService get _chatShell => pluginSession.require(chatShellService);

  ChatController get chat => pluginSession.require(chatControllerService);
  TestChatRecords get chatRecords => TestChatRecords(chat);
  ChatNavigationHandoff get chatNavigation => _chatShell.navigation;
  Future<bool> openChatUrl(String url) => _chatShell.openPluginUrl(url);
  void openChatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    int? messageId,
    bool focusComposer = false,
  }) => _chatShell.openThread(
    siteUrl: siteUrl,
    channelId: channelId,
    threadId: threadId,
    messageId: messageId,
    focusComposer: focusComposer,
  );
  bool openChatChannel(int channelId, {int? messageId}) =>
      _chatShell.openChannel(channelId, messageId: messageId);
  bool openChatChannelInfo({
    required String siteUrl,
    required int channelId,
    ChatChannelInfoTab tab = ChatChannelInfoTab.settings,
  }) => _chatShell.openChannelInfo(
    siteUrl: siteUrl,
    channelId: channelId,
    tab: tab,
  );
  bool openChatChannelThreads({
    required String siteUrl,
    required int channelId,
  }) => _chatShell.openChannelThreads(siteUrl: siteUrl, channelId: channelId);
  bool revealChatChannelMessage({
    required String siteUrl,
    required int channelId,
    required int messageId,
  }) => _chatShell.revealChannelMessage(
    siteUrl: siteUrl,
    channelId: channelId,
    messageId: messageId,
  );
  Future<String?> openChatQuote(
    String siteUrl,
    int channelId,
    String markdown,
  ) => _chatShell.openQuote(siteUrl, channelId, markdown);
  Future<void> openChat() => _chatShell.openShortcut();
}

final class TestChatRecords {
  const TestChatRecords(this._chat);

  final ChatController _chat;

  T put<T extends Storable<T>>(String siteUrl, T record) =>
      _chat.putRecordForTesting(siteUrl, record);

  List<T> putAll<T extends Storable<T>>(String siteUrl, Iterable<T> records) =>
      _chat.putRecordsForTesting(siteUrl, records);

  T? read<T extends Storable<T>>(String siteUrl, Object id) =>
      _chat.readRecordForTesting<T>(siteUrl, id);
}
