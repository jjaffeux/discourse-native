import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../data/discourse_api.dart';
import '../data/discover_sites.dart';
import '../data/http_basic_auth.dart';
import '../models/discourse_instance.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'app_home_theme.dart';
import 'discover_site_suggestions.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

const Duration addInstanceLookupDebounce = Duration(milliseconds: 750);

Future<void> showAddInstanceSheet(
  BuildContext context, {
  DiscoverSites? discoverSites,
}) async {
  final title = appL10n.addASite;
  final shell = ShellScope.maybeRead(context);
  final source = discoverSites ?? shell?.discoverSites ?? DiscoverSites();
  final ownsSource = discoverSites == null && shell == null;
  final addressFocus = FocusNode(debugLabel: 'Add site address');
  try {
    if (context.isTouch) {
      await showShellSheet<void>(
        context: context,
        title: title,
        initialFocusNode: addressFocus,
        fillAvailableHeight: true,
        padding: const EdgeInsets.all(DSpacing.lg),
        surfaceBuilder: (context, child) => AppHomeTheme(child: child),
        builder: (context) =>
            _AddInstanceForm(focusNode: addressFocus, discoverSites: source),
      );
      return;
    }
    await showDDialog<void>(
      context: context,
      initialFocusNode: addressFocus,
      builder: (context, controller) => AppHomeTheme(
        child: DDialogContent(
          maxWidth: 600,
          semanticLabel: title,
          children: [
            DDialogHeader(children: [DDialogTitle(child: Text(title))]),
            _AddInstanceForm(focusNode: addressFocus, discoverSites: source),
          ],
        ),
      ),
    );
  } finally {
    if (ownsSource) source.dispose();
  }
}

class _AddInstanceForm extends StatefulWidget {
  const _AddInstanceForm({
    required this.discoverSites,
    required this.focusNode,
  });

  // Own the node until the closing route has actually unmounted. The overlay
  // helpers resolve on pop, before their dismissal animation finishes.
  final FocusNode focusNode;
  final DiscoverSites discoverSites;

  @override
  State<_AddInstanceForm> createState() => _AddInstanceFormState();
}

class _AddInstanceFormState extends State<_AddInstanceForm> {
  final TextEditingController _field = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  Uri? _authenticationOrigin;
  HttpBasicAuthentication? _authentication;
  HttpBasicAuthentication? _validatedAuthentication;
  HttpBasicAuthentication? _pendingAuthentication;
  Timer? _lookupTimer;
  int _lookupGeneration = 0;
  _SiteCheckState _siteCheck = _SiteCheckState.idle;
  String? _validatedTerm;
  DiscourseInstance? _validatedInstance;
  ShellController? _validatedController;
  String? _pendingTerm;
  ShellController? _pendingController;
  Future<_SiteCheckResult>? _pendingLookup;
  bool _connecting = false;
  String? _error;
  String? _credentialError;

  @override
  void dispose() {
    _lookupTimer?.cancel();
    _field.dispose();
    _username.dispose();
    _password.dispose();
    widget.focusNode.dispose();
    super.dispose();
  }

  void _addressChanged(String value) {
    _lookupTimer?.cancel();
    _lookupTimer = null;
    final generation = ++_lookupGeneration;
    final term = value.trim();
    final canLookup = _canLookup(term);

    setState(() {
      _siteCheck = term.isNotEmpty && !canLookup
          ? _SiteCheckState.invalid
          : _SiteCheckState.idle;
      _validatedTerm = null;
      _validatedInstance = null;
      _validatedController = null;
      _error = null;
      _credentialError = null;
      _authenticationOrigin = null;
      _authentication = null;
      _username.clear();
      _password.clear();
    });

    if (!canLookup) return;
    _lookupTimer = Timer(addInstanceLookupDebounce, () {
      _lookupTimer = null;
      unawaited(_validate(term, generation));
    });
  }

  bool _canLookup(String term) {
    if (term.isEmpty) return false;
    try {
      DiscourseApi.normalize(term);
      return true;
    } on SiteLookupException {
      return false;
    }
  }

  Future<void> _validate(String term, int generation) async {
    if (!mounted || generation != _lookupGeneration) return;
    final controller = ShellScope.read(context);
    setState(() => _siteCheck = _SiteCheckState.checking);

    final result = await _lookup(term, controller);
    if (!mounted || generation != _lookupGeneration) return;
    if (!identical(ShellScope.read(context), controller)) {
      setState(() => _siteCheck = _SiteCheckState.idle);
      return;
    }

    setState(() {
      if (result.error case final HttpBasicAuthenticationRequired challenge) {
        _showAuthentication(challenge);
        return;
      }
      final instance = result.instance;
      if (instance == null) {
        _siteCheck = _SiteCheckState.invalid;
        _validatedTerm = null;
        _validatedInstance = null;
        _validatedController = null;
      } else {
        _siteCheck = _SiteCheckState.valid;
        _validatedTerm = term;
        _validatedInstance = instance;
        _validatedController = controller;
        _validatedAuthentication = _authentication;
      }
    });
  }

  Future<_SiteCheckResult> _lookup(String term, ShellController controller) {
    final pending = _pendingLookup;
    if (pending != null &&
        _pendingTerm == term &&
        identical(_pendingAuthentication, _authentication) &&
        identical(_pendingController, controller)) {
      return pending;
    }

    final lookup = _performLookup(term, controller, _authentication);
    _pendingTerm = term;
    _pendingAuthentication = _authentication;
    _pendingController = controller;
    _pendingLookup = lookup;
    unawaited(
      lookup.then((_) {
        if (identical(_pendingLookup, lookup)) {
          _pendingTerm = null;
          _pendingController = null;
          _pendingLookup = null;
        }
      }),
    );
    return lookup;
  }

  Future<_SiteCheckResult> _performLookup(
    String term,
    ShellController controller,
    HttpBasicAuthentication? authentication,
  ) async {
    try {
      return _SiteCheckResult.success(
        await controller.api.siteLookup.lookup(
          term,
          authentication: authentication,
        ),
      );
    } catch (error) {
      return _SiteCheckResult.failure(error);
    }
  }

  void _credentialsChanged(String _) {
    _lookupTimer?.cancel();
    ++_lookupGeneration;
    setState(() {
      _authentication = null;
      _validatedInstance = null;
      _validatedTerm = null;
      _validatedAuthentication = null;
      _error = null;
      _credentialError = null;
      _siteCheck = _SiteCheckState.authentication;
    });
  }

  void _showAuthentication(HttpBasicAuthenticationRequired challenge) {
    final retried = _authentication?.origin == challenge.origin;
    if (_authenticationOrigin != challenge.origin) {
      _username.clear();
      _password.clear();
      _authentication = null;
    }
    _authenticationOrigin = challenge.origin;
    _validatedInstance = null;
    _validatedTerm = null;
    _siteCheck = _SiteCheckState.authentication;
    _credentialError = retried ? appL10n.httpBasicAuthenticationRejected : null;
  }

  Future<void> _connect() async {
    final term = _field.text.trim();
    if (term.isEmpty || _connecting) return;
    if (_authenticationOrigin case final origin?) {
      try {
        _authentication ??= HttpBasicAuthentication(
          origin: origin,
          username: _username.text,
          password: _password.text,
        );
      } on FormatException {
        setState(
          () => _credentialError = appL10n.httpBasicAuthenticationInvalid,
        );
        return;
      }
    }

    _lookupTimer?.cancel();
    _lookupTimer = null;
    final generation = ++_lookupGeneration;
    setState(() {
      _connecting = true;
      _siteCheck = _SiteCheckState.checking;
      _error = null;
      _credentialError = null;
    });

    final controller = ShellScope.read(context);
    bool current() =>
        mounted &&
        generation == _lookupGeneration &&
        identical(ShellScope.read(context), controller);
    bool currentRoute() =>
        current() && ModalRoute.of(context)?.isCurrent == true;
    final cached =
        _validatedTerm == term &&
            identical(_validatedController, controller) &&
            identical(_validatedAuthentication, _authentication)
        ? _validatedInstance
        : null;
    final result = cached == null
        ? await _lookup(term, controller)
        : _SiteCheckResult.success(cached);
    if (!current()) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _siteCheck = _SiteCheckState.idle;
        });
      }
      return;
    }
    if (result.error case final HttpBasicAuthenticationRequired challenge) {
      if (!currentRoute()) return;
      setState(() {
        _connecting = false;
        _showAuthentication(challenge);
      });
      return;
    }

    final instance = result.instance;
    String failure;
    if (instance != null) {
      final renewing =
          controller.contains(instance.url) &&
          _authentication?.origin.origin == Uri.parse(instance.url).origin;
      if (controller.contains(instance.url) && !renewing) {
        failure = appL10n.isAlreadyInYourList(instance.title);
      } else {
        HttpBasicAuthChange? savedAuthentication;
        try {
          final authentication = _authentication;
          if (authentication != null &&
              authentication.origin.origin == Uri.parse(instance.url).origin) {
            if (!currentRoute()) return;
            savedAuthentication = await controller.basicAuth.remember(
              authentication,
            );
          }
          if (!current() || (savedAuthentication != null && !currentRoute())) {
            await savedAuthentication?.rollback();
            return;
          }
          if (renewing) {
            if (controller.currentInstance?.url == instance.url) {
              unawaited(controller.refreshCurrentTab());
            }
            if (mounted && currentRoute()) Navigator.of(context).pop();
            return;
          }
          final added = await controller.addInstance(instance);
          if (added) {
            if (mounted && currentRoute()) Navigator.of(context).pop();
            return;
          }
          await savedAuthentication?.rollback();
        } catch (_) {
          try {
            await savedAuthentication?.rollback();
          } catch (_) {}
        }
        failure = appL10n.couldnTSaveThisSiteTryAgain;
      }
    } else {
      final error = result.error!;
      failure = error is SiteLookupException
          ? error.message
          : appL10n.couldnTReachAddinstancesheet(term);
    }
    if (!current()) return;
    setState(() {
      _connecting = false;
      _siteCheck = instance == null
          ? _SiteCheckState.invalid
          : _SiteCheckState.valid;
      _error = failure;
    });
  }

  Widget? _siteCheckIcon(ThemeData theme) => switch (_siteCheck) {
    _SiteCheckState.idle || _SiteCheckState.authentication => null,
    _SiteCheckState.checking => const Center(
      child: SizedBox.square(
        key: ValueKey('add-site-checking'),
        dimension: 18,
        child: DSpinner(),
      ),
    ),
    _SiteCheckState.valid => DTooltip(
      message: appL10n.validDiscourseSite,
      child: DIcon(
        DIcons.check,
        key: const ValueKey('add-site-valid'),
        size: 20,
        color: theme.discourse.success,
      ),
    ),
    _SiteCheckState.invalid => DTooltip(
      message: appL10n.siteIsUnavailableOrIsNotADiscourseForum,
      child: DIcon(
        DIcons.xmark,
        key: const ValueKey('add-site-invalid'),
        size: 20,
        color: theme.colorScheme.error,
      ),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.enterTheAddressOfADiscourseForum,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        DInput(
          controller: _field,
          focusNode: widget.focusNode,
          autofocus: true,
          enabled: !_connecting,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onChanged: _addressChanged,
          onSubmitted: (_) => _connect(),
          semanticLabel: context.l10n.forumAddress,
          hintText: context.l10n.siteAddressExample,
          prefix: const DIcon(DIcons.globe, size: 16),
          suffix: _connecting ? null : _siteCheckIcon(theme),
          errorText: _error,
        ),
        if (_authenticationOrigin case final origin?) ...[
          const SizedBox(height: DSpacing.lg),
          Text(context.l10n.httpBasicAuthenticationRequired(origin.origin)),
          const SizedBox(height: DSpacing.md),
          DInput(
            controller: _username,
            labelText: context.l10n.httpBasicAuthenticationUsername,
            semanticLabel: context.l10n.httpBasicAuthenticationUsername,
            enabled: !_connecting,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            onChanged: _credentialsChanged,
          ),
          const SizedBox(height: DSpacing.md),
          DInput(
            controller: _password,
            labelText: context.l10n.httpBasicAuthenticationPassword,
            semanticLabel: context.l10n.httpBasicAuthenticationPassword,
            enabled: !_connecting,
            obscureText: true,
            errorText: _credentialError,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.go,
            onChanged: _credentialsChanged,
            onSubmitted: (_) => _connect(),
          ),
        ],
        const SizedBox(height: 16),
        DButton(
          label: Text(context.l10n.connect),
          onPressed: _connect,
          variant: DButtonVariant.primary,
          loading: _connecting,
        ),
        const SizedBox(height: DSpacing.xl),
        DiscoverSiteSuggestions(
          source: widget.discoverSites,
          enabled: !_connecting,
          onSelected: (site) {
            _field.value = TextEditingValue(
              text: site.url,
              selection: TextSelection.collapsed(offset: site.url.length),
            );
            _addressChanged(site.url);
            unawaited(_connect());
          },
        ),
      ],
    );
  }
}

enum _SiteCheckState { idle, checking, valid, invalid, authentication }

final class _SiteCheckResult {
  const _SiteCheckResult.success(DiscourseInstance this.instance)
    : error = null;

  const _SiteCheckResult.failure(this.error) : instance = null;

  final DiscourseInstance? instance;
  final Object? error;
}
