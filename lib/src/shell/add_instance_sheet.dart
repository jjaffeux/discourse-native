import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../data/discourse_api.dart';
import '../data/discover_sites.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../models/discourse_instance.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'app_home_theme.dart';
import 'discover_site_suggestions.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

const Duration addInstanceLookupDebounce = Duration(milliseconds: 750);

Future<void> showAddInstanceSheet(
  BuildContext context, {
  DiscoverSites? discoverSites,
}) async {
  const title = 'Add a site';
  final shell = ShellScope.maybeRead(context);
  final source = discoverSites ?? shell?.discoverSites ?? DiscoverSites();
  final ownsSource = discoverSites == null && shell == null;
  final isTouch = switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };

  final addressFocus = FocusNode(debugLabel: 'Add site address');
  try {
    if (isTouch) {
      await showDDrawer<void>(
        context: context,
        showSwipeHandle: true,
        initialFocusNode: addressFocus,
        builder: (context, controller) => AppHomeTheme(
          child: DDrawerContent(
            semanticLabel: title,
            children: [
              DDrawerHeader(
                children: [
                  Row(
                    children: [
                      const Expanded(child: DDrawerTitle(child: Text(title))),
                      DButton.iconOnly(
                        variant: DButtonVariant.ghost,
                        icon: const DIcon(DIcons.xmark),
                        tooltip: 'Close',
                        onPressed: () => controller.close(),
                      ),
                    ],
                  ),
                ],
              ),
              Flexible(
                child: DScrollArea(
                  padding: const EdgeInsets.all(DSpacing.lg),
                  child: _AddInstanceForm(
                    focusNode: addressFocus,
                    discoverSites: source,
                  ),
                ),
              ),
            ],
          ),
        ),
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
            const DDialogHeader(children: [DDialogTitle(child: Text(title))]),
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

  @override
  void dispose() {
    _lookupTimer?.cancel();
    _field.dispose();
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
      }
    });
  }

  Future<_SiteCheckResult> _lookup(String term, ShellController controller) {
    final pending = _pendingLookup;
    if (pending != null &&
        _pendingTerm == term &&
        identical(_pendingController, controller)) {
      return pending;
    }

    final lookup = _performLookup(term, controller);
    _pendingTerm = term;
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
  ) async {
    try {
      return _SiteCheckResult.success(
        await controller.api.siteLookup.lookup(term),
      );
    } catch (error, stackTrace) {
      return _SiteCheckResult.failure(error, stackTrace);
    }
  }

  Future<void> _connect() async {
    final term = _field.text.trim();
    if (term.isEmpty || _connecting) return;

    _lookupTimer?.cancel();
    _lookupTimer = null;
    ++_lookupGeneration;

    setState(() {
      _connecting = true;
      _siteCheck = _SiteCheckState.checking;
      _error = null;
    });

    final controller = ShellScope.read(context);
    String failure;
    final cached =
        _validatedTerm == term && identical(_validatedController, controller)
        ? _validatedInstance
        : null;
    final result = cached == null
        ? await _lookup(term, controller)
        : _SiteCheckResult.success(cached);

    if (!mounted) return;
    if (!identical(ShellScope.read(context), controller)) {
      setState(() {
        _connecting = false;
        _siteCheck = _SiteCheckState.idle;
      });
      return;
    }

    final instance = result.instance;
    if (instance != null) {
      setState(() {
        _siteCheck = _SiteCheckState.valid;
        _validatedTerm = term;
        _validatedInstance = instance;
        _validatedController = controller;
      });

      if (!controller.contains(instance.url)) {
        final added = await controller.addInstance(instance);
        if (!mounted) return;
        if (!identical(ShellScope.read(context), controller)) {
          setState(() => _connecting = false);
          return;
        }
        if (added) {
          // The barrier and Escape stay live while connecting, and a dismissed
          // route keeps this State mounted for its exit animation. A success
          // landing in that window must not pop whatever route is on top now.
          if (ModalRoute.of(context)?.isCurrent == true) {
            Navigator.of(context).pop();
          }
          return;
        }
        failure = "Couldn't save this site. Try again.";
      } else {
        failure = '${instance.title} is already in your list.';
      }
    } else {
      final error = result.error!;
      final stackTrace = result.stackTrace!;
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'site.add',
        source: 'shell',
        handled: true,
        degraded: false,
      );
      failure = error is SiteLookupException
          ? error.message
          : "Couldn't reach $term.";
    }

    if (!mounted) return;
    setState(() {
      _connecting = false;
      if (instance == null) _siteCheck = _SiteCheckState.invalid;
      _error = failure;
    });
  }

  Widget? _siteCheckIcon(ThemeData theme) => switch (_siteCheck) {
    _SiteCheckState.idle => null,
    _SiteCheckState.checking => const Center(
      child: SizedBox.square(
        key: ValueKey('add-site-checking'),
        dimension: 18,
        child: DSpinner(),
      ),
    ),
    _SiteCheckState.valid => DTooltip(
      message: 'Valid Discourse site',
      child: DIcon(
        DIcons.check,
        key: const ValueKey('add-site-valid'),
        size: 20,
        color: theme.discourse.success,
      ),
    ),
    _SiteCheckState.invalid => DTooltip(
      message: 'Site is unavailable or is not a Discourse forum',
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
          'Enter the address of a Discourse forum.',
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
          semanticLabel: 'Forum address',
          hintText: 'meta.discourse.org',
          prefix: const DIcon(DIcons.globe, size: 16),
          suffix: _siteCheckIcon(theme),
          errorText: _error,
        ),
        const SizedBox(height: 16),
        DButton(
          label: const Text('Connect'),
          onPressed: _connect,
          variant: DButtonVariant.primary,
          loading: _connecting,
        ),
        const SizedBox(height: DSpacing.xl),
        DiscoverSiteSuggestions(
          source: widget.discoverSites,
          address: _field.text,
          enabled: !_connecting,
          onSelected: (site) {
            _field.value = TextEditingValue(
              text: site.url,
              selection: TextSelection.collapsed(offset: site.url.length),
            );
            _addressChanged(site.url);
          },
        ),
      ],
    );
  }
}

enum _SiteCheckState { idle, checking, valid, invalid }

final class _SiteCheckResult {
  const _SiteCheckResult.success(DiscourseInstance this.instance)
    : error = null,
      stackTrace = null;

  const _SiteCheckResult.failure(this.error, this.stackTrace) : instance = null;

  final DiscourseInstance? instance;
  final Object? error;
  final StackTrace? stackTrace;
}
