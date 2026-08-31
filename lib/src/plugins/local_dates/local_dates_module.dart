import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../chat/chat_preview_contract.dart';
import 'local_date.dart';
import 'local_date_environment.dart';
import 'local_dates_contract.dart';
import 'local_dates_cooked_time_parser.dart';
import 'local_dates_plugin.dart';
import 'local_dates_services.dart';

const localDatesPluginId = PluginId('discourse-local-dates');

final localDatesModule = LocalDatesModule(
  environment: LocalDateEnvironment.instance,
);

final class LocalDatesModule implements PluginModule {
  const LocalDatesModule({required this.environment});

  final LocalDateEnvironment environment;

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: localDatesPluginId,
    staticContributionTargets: [
      PluginStaticContributionTarget(PluginId('chat'), optional: true),
    ],
    syntaxIds: {'discourse-local-dates/local-date'},
  );

  @override
  void register(PluginRegistrar registrar) {
    final plugin = LocalDatesPlugin(environment: environment);
    registrar.addCapability(plugin);
    registrar.addStaticContribution(
      chatPreviewContributions,
      name: 'local-date',
      value: plugin,
    );
    registrar.addSyntaxId(plugin.composerSyntaxKind.id);
    registrar.addSession(
      (bindings, _) => PluginSessionContribution(
        lifecycle: _LocalDatesSessionLifecycle(),
        services: [
          PluginService<Object>(
            localDatesCookedTimeParserService,
            LocalDatesCookedTimeParser(
              formatter: LocalDateFormatter(environment: environment),
            ),
          ),
          PluginService<Object>(
            localDatesUiService,
            LocalDatesUiService(
              composer: bindings.require(corePluginComposerPort),
              siteState: bindings.require(corePluginSiteStatePort),
              currentSite: bindings.require(corePluginCurrentSitePort),
            ),
          ),
        ],
      ),
      requires: const [
        corePluginComposerPort,
        corePluginSiteStatePort,
        corePluginCurrentSitePort,
      ],
    );
  }
}

final class _LocalDatesSessionLifecycle extends PluginSessionLifecycle {}
