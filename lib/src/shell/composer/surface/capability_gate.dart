enum ComposerSurfaceCapability {
  rawSourceIsolation,
  atomicInlinePosition,
  atomicBlockPosition,
  independentBlockGeometry,
  headlessMutationRouting,
  plainTextEditing,
  imeComposition,
  crossComponentSelection,
  revisionBoundComponentActions,
  clipboard,
  undoRedo,
  accessibility,
  swiftPackageManager,
}

/// An explicit shipping gate for a private composer-surface implementation.
final class ComposerSurfaceCapabilityGate {
  const ComposerSurfaceCapabilityGate({
    required this.adapter,
    required this.supported,
    required this.blockers,
  });

  final String adapter;
  final Set<ComposerSurfaceCapability> supported;
  final Map<ComposerSurfaceCapability, String> blockers;

  bool get isProductionReady => blockers.isEmpty;
}

/// Capabilities proven by the dependency-free projected TextField spike.
///
/// It is intentionally read-only. Mutations must not be enabled until every
/// edit can be translated back through the headless composer transaction API.
const projectedTextFieldComposerSurfaceGate = ComposerSurfaceCapabilityGate(
  adapter: 'projected TextField spike',
  supported: {
    ComposerSurfaceCapability.rawSourceIsolation,
    ComposerSurfaceCapability.atomicInlinePosition,
    ComposerSurfaceCapability.atomicBlockPosition,
    ComposerSurfaceCapability.independentBlockGeometry,
  },
  blockers: {
    ComposerSurfaceCapability.headlessMutationRouting:
        'Surface edits are not translated into verified source transactions.',
    ComposerSurfaceCapability.plainTextEditing:
        'The projected surface is read-only.',
    ComposerSurfaceCapability.imeComposition:
        'IME ranges have not been mapped across atomic source spans.',
    ComposerSurfaceCapability.crossComponentSelection:
        'Drag and keyboard selection have not been normalized through the '
        'headless selection model.',
    ComposerSurfaceCapability.clipboard:
        'Copy and cut do not yet serialize canonical source selections.',
    ComposerSurfaceCapability.revisionBoundComponentActions:
        'Component edit and remove actions are not exposed by this surface.',
    ComposerSurfaceCapability.undoRedo:
        'History must remain owned by the headless composer session.',
    ComposerSurfaceCapability.accessibility:
        'Screen-reader navigation and component actions are not verified.',
  },
);

/// Capabilities covered when the projected surface is owned by the hybrid
/// session bridge.
///
/// Composition-free ordinary text and history commands are translated through
/// the canonical session. IME composition and clipboard serialization remain
/// gated rather than creating native editor state outside that session.
const composerHybridFieldSurfaceGate = ComposerSurfaceCapabilityGate(
  adapter: 'hybrid projected TextField',
  supported: {
    ComposerSurfaceCapability.rawSourceIsolation,
    ComposerSurfaceCapability.atomicInlinePosition,
    ComposerSurfaceCapability.atomicBlockPosition,
    ComposerSurfaceCapability.independentBlockGeometry,
    ComposerSurfaceCapability.headlessMutationRouting,
    ComposerSurfaceCapability.plainTextEditing,
    ComposerSurfaceCapability.crossComponentSelection,
    ComposerSurfaceCapability.revisionBoundComponentActions,
    ComposerSurfaceCapability.undoRedo,
  },
  blockers: {
    ComposerSurfaceCapability.imeComposition:
        'IME ranges have not been mapped between text leaves and canonical '
        'source.',
    ComposerSurfaceCapability.clipboard:
        'Copy and cut must serialize canonical source selections; the surface '
        'toolbar is disabled until then.',
    ComposerSurfaceCapability.accessibility:
        'Labels are supplied, but screen-reader navigation and component '
        'actions are not yet verified.',
  },
);

/// Why the investigated SuperEditor version cannot be added to this app.
const superEditorDev52ComposerSurfaceGate = ComposerSurfaceCapabilityGate(
  adapter: 'super_editor 0.3.0-dev.52',
  supported: {
    ComposerSurfaceCapability.atomicInlinePosition,
    ComposerSurfaceCapability.atomicBlockPosition,
    ComposerSurfaceCapability.independentBlockGeometry,
  },
  blockers: {
    ComposerSurfaceCapability.swiftPackageManager:
        'Its super_keyboard 0.4.0 dependency has an iOS podspec but no '
        'Package.swift; this app intentionally has no CocoaPods integration.',
    ComposerSurfaceCapability.headlessMutationRouting:
        'Editor requests are not yet translated into verified source '
        'transactions.',
    ComposerSurfaceCapability.imeComposition:
        'IME behavior across project-owned atomic components is unverified.',
    ComposerSurfaceCapability.crossComponentSelection:
        'Cross-node dragging and keyboard selection are unverified.',
    ComposerSurfaceCapability.clipboard:
        'Canonical-source copy and cut are unverified.',
    ComposerSurfaceCapability.revisionBoundComponentActions:
        'Project-owned component action lifetimes are unverified.',
    ComposerSurfaceCapability.undoRedo:
        'SuperEditor history cannot become a second source of truth.',
    ComposerSurfaceCapability.accessibility:
        'Inline widget semantics and screen-reader navigation are unverified.',
  },
);
