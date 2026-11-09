import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

const zendeskModule = ZendeskModule();
const _id = PluginId('discourse-zendesk-plugin');
const _service = PluginServiceKey<_ZendeskSession>(owner: _id, name: 'tickets');
const _hasTicket = 'discourse_zendesk_plugin_has_ticket';
const _ticketUrl = 'discourse_zendesk_plugin_zendesk_url';
const _status = 'discourse_zendesk_plugin_status';
const _canCreate = 'can_create_zendesk_ticket';
const _canView = 'can_view_zendesk_ticket';

typedef _Permissions = ({bool configured, bool create, bool view});
typedef _Ticket = ({bool exists, String? url});

final class ZendeskModule implements PluginModule {
  const ZendeskModule();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: _id);

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const _ZendeskPlugin());
    registrar.addSession(
      (bindings, _) {
        final session = _ZendeskSession(
          bindings.require(corePluginTransportPort),
          bindings.require(corePluginRequestPort),
          bindings.require(corePluginSiteStatePort),
          bindings.require(corePluginTopicRefreshPort),
        );
        return PluginSessionContribution(
          lifecycle: session,
          services: [PluginService<Object>(_service, session)],
        );
      },
      requires: const [
        corePluginTransportPort,
        corePluginRequestPort,
        corePluginSiteStatePort,
        corePluginTopicRefreshPort,
      ],
    );
  }
}

final class _ZendeskPlugin
    implements
        SitePlugin,
        CurrentUserPlugin<_Permissions>,
        TopicRecordPlugin<_Ticket>,
        IsolateTopicDecoderPlugin,
        TopicMenuPlugin {
  const _ZendeskPlugin();

  @override
  String get name => _id.value;

  @override
  SitePlugin Function() get isolateTopicDecoderFactory => _ZendeskPlugin.new;

  @override
  PluginDataPersistenceCodec<_Permissions> get currentUserCodec =>
      const _PermissionsCodec();

  @override
  _Permissions? readCurrentUser(Map<String, dynamic> json, String siteUrl) =>
      currentUserCodec.decode(json);

  @override
  PluginDataKey<_Ticket> get record =>
      const PluginDataKey(owner: 'discourse-zendesk-plugin', name: 'ticket');

  @override
  _Ticket? readTopic(
    Map<String, dynamic> json,
    String siteUrl, {
    TopicRecordDecodeContext context = const TopicRecordDecodeContext.partial(),
  }) {
    final exists = json[_hasTicket];
    if (exists is! bool) return null;
    final url = json[_ticketUrl];
    return (exists: exists, url: url is String ? url : null);
  }

  @override
  List<TopicMenuAction> topicMenuActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final ticket = topic.plugins.get(record);
    if (ticket == null) return const [];
    final session = PluginUiScope.require(context, _service);
    final permissions = session.permissionsFor(siteUrl);
    if (permissions?.configured != true) return const [];

    if (ticket.exists) {
      final url = ticket.url;
      if (permissions?.view != true || url == null || url.isEmpty) {
        return const [];
      }
      return [
        TopicMenuAction(
          label: context.l10n.zendeskViewTicket,
          icon: DIcons.link,
          onSelected: (_) => unawaited(openExternalLink(url)),
        ),
      ];
    }
    if (permissions?.create != true) return const [];
    return [
      TopicMenuAction(
        label: context.l10n.zendeskCreateTicket,
        icon: DIcons.plus,
        onSelected: (context) =>
            unawaited(session.create(context, siteUrl, topic.id)),
      ),
    ];
  }
}

final class _PermissionsCodec extends PluginDataPersistenceCodec<_Permissions> {
  const _PermissionsCodec();

  @override
  PluginDataKey<_Permissions> get key => const PluginDataKey(
    owner: 'discourse-zendesk-plugin',
    name: 'permissions',
  );

  @override
  _Permissions? decode(Object? value) {
    if (value is! Map || !value.containsKey(_status)) return null;
    final status = value[_status];
    return (
      configured: status == true || (status is String && status.isNotEmpty),
      create: value[_canCreate] == true,
      view: value[_canView] == true,
    );
  }

  @override
  Object encode(_Permissions value) => {
    _status: value.configured,
    _canCreate: value.create,
    _canView: value.view,
  };
}

final class _ZendeskSession extends PluginSessionLifecycle {
  _ZendeskSession(this.transport, this.requests, this.sites, this.topics);

  final PluginApiTransport transport;
  final PluginRequestHost requests;
  final PluginSiteStateHost sites;
  final PluginTopicRefreshHost topics;
  final _creating = <(String, int)>{};

  _Permissions? permissionsFor(String site) =>
      sites.currentUserFor(site)?.plugins.get(const _PermissionsCodec().key);

  Future<void> create(BuildContext context, String site, int topic) async {
    final permissions = permissionsFor(site);
    if (permissions?.configured != true || permissions?.create != true) return;
    final operation = (site, topic);
    if (!_creating.add(operation)) return;
    final lease = requests.capture(site);
    try {
      final credentials = await requests.writeCredentialFor(site);
      if (!lease.isCurrent) return;
      final account = credentials.credentials;
      final key = account?.apiKey;
      if (account == null || key == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final response = await account.run(
        () => transport.pluginWriteJson(
          siteUrl: site,
          path: '/zendesk-plugin/issues',
          apiKey: key,
          clientId: account.clientId,
          method: 'POST',
          body: {'topic_id': topic},
        ),
      );
      if (!lease.isCurrent) return;
      if (response[_hasTicket] != true) {
        throw const FormatException('Missing Zendesk ticket confirmation');
      }
      if (context.mounted) {
        DToast.show(context, context.l10n.zendeskTicketCreated);
      }
      await topics.refreshAfterMutation?.call(
        siteUrl: site,
        topicId: topic,
        lease: lease,
      );
    } catch (_) {
      if (lease.isCurrent && context.mounted) {
        DToast.show(context, context.l10n.zendeskTicketFailed);
      }
    } finally {
      _creating.remove(operation);
    }
  }
}
