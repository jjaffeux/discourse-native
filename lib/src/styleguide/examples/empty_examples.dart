import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';
import 'empty_artwork.dart';
import 'empty_example_source.dart';

final emptyExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description: 'A composed empty state with media, explanation and next steps.',
  notes:
      'Frozen base-nova geometry: 24px padding, 16px outer gap, 384px slots, '
      '8px header gap, 10px content gap; media adds 8px below its 32px tile. '
      'Title is 14/20 medium with −0.35px tracking; description is 14/22.75. '
      'Native line wrapping replaces CSS text-balance. The layout owns no input, '
      'Form, animation, focus or controllers. Compose scrolling in short panes. '
      'Actions use the merged DButton owner. '
      'The search uses a merged DInput; reconcile its Input Group '
      'styling when that component merges. Avatar fallbacks are local deterministic '
      'data in place of remote portraits. Reference/native visual review is pending.',
  examples: [
    for (final kind in [
      'Basic',
      'Outline',
      'Background',
      'Avatar',
      'Avatar Group',
      'RTL',
    ])
      StyleguideExample(
        title: kind,
        description: switch (kind) {
          'Outline' => 'One-pixel dashed border using the live border token.',
          'Background' =>
            'The muted token with its existing alpha multiplied by 30%.',
          'Avatar' => 'A 48px public avatar in the unstyled media slot.',
          'Avatar Group' =>
            'Three 48px avatars, 8px overlap and native group rings.',
          'RTL' => 'Arabic content, directional action order and wrapping.',
          _ => 'The reference project composition with working local actions.',
        },
        states: [kind, 'Local actions', 'Live theme', 'Large text'],
        code: _exampleCode(kind),
        builder: (_) => _EmptySample(kind: kind),
      ),
    StyleguideExample(
      title: 'Search content (native input composition)',
      description:
          'Submit a local search, validate an empty query, or activate '
          'support. Editing survives preview changes. Input Group remains pending.',
      states: const [
        'Form',
        'Keyboard',
        'Editing',
        'Validation',
        'Arbitrary child',
      ],
      code:
          "// Mount const EmptySearchSample() in your application.\n$emptySearchSource",
      builder: (_) => const EmptySearchSample(),
    ),
  ],
);

class _EmptySample extends StatefulWidget {
  const _EmptySample({required this.kind});
  final String kind;
  @override
  State<_EmptySample> createState() => _EmptySampleState();
}

class _EmptySampleState extends State<_EmptySample> {
  String? _result;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final rtl = kind == 'RTL';
    final tokens = DTokens.of(context);
    final (title, description, action) = switch (kind) {
      'Outline' => (
        'Cloud Storage Empty',
        'Upload files to your cloud storage to access them anywhere.',
        'Upload Files',
      ),
      'Background' => (
        'No Notifications',
        "You're all caught up. New notifications will appear here.",
        'Refresh',
      ),
      'Avatar' => (
        'User Offline',
        'This user is currently offline. You can leave a message to notify them or try again later.',
        'Leave Message',
      ),
      'Avatar Group' => (
        'No Team Members',
        'Invite your team to collaborate on this project.',
        'Invite Members',
      ),
      'RTL' => (
        'لا توجد مشاريع بعد',
        'لم تقم بإنشاء أي مشاريع بعد. ابدأ بإنشاء مشروعك الأول.',
        'إنشاء مشروع',
      ),
      _ => (
        'No Projects Yet',
        "You haven't created any projects yet. Get started by creating your first project.",
        'Create Project',
      ),
    };
    void act(String value) => setState(() => _result = value);
    final basic = kind == 'Basic' || rtl;
    return DDirection(
      textDirection: rtl ? TextDirection.rtl : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DEmpty(
            outlined: kind == 'Outline',
            backgroundColor: kind == 'Background'
                ? tokens.muted.withValues(alpha: tokens.muted.a * .3)
                : null,
            children: [
              DEmptyHeader(
                children: [
                  if (kind == 'Avatar' || kind == 'Avatar Group')
                    DEmptyMedia(
                      child: kind == 'Avatar'
                          ? _avatar('LR')
                          : DAvatarGroup(
                              children: [
                                for (final label in ['CN', 'LR', 'ER'])
                                  _avatar(label),
                              ],
                            ),
                    )
                  else
                    DEmptyMedia(
                      variant: DEmptyMediaVariant.icon,
                      child: Builder(
                        builder: (context) =>
                            emptyReferenceIcon(context, switch (kind) {
                              'Outline' => 'cloud',
                              'Background' => 'bell',
                              _ => 'folder-code',
                            }),
                      ),
                    ),
                  DEmptyTitle(title),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: kind == 'Background' ? 320 : 384,
                    ),
                    child: DEmptyDescription(description),
                  ),
                ],
              ),
              DEmptyContent(
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DButton(
                        label: Text(action),
                        icon: switch (kind) {
                          'Background' => Builder(
                            builder: (context) =>
                                emptyReferenceIcon(context, 'refresh-ccw'),
                          ),
                          'Avatar Group' => Builder(
                            builder: (context) =>
                                emptyReferenceIcon(context, 'plus'),
                          ),
                          _ => null,
                        },
                        variant: kind == 'Outline' || kind == 'Background'
                            ? DButtonVariant.outline
                            : DButtonVariant.primary,
                        size:
                            kind == 'Outline' ||
                                kind == 'Avatar' ||
                                kind == 'Avatar Group'
                            ? DButtonSize.small
                            : DButtonSize.regular,
                        onPressed: () => act(action),
                      ),
                      if (basic)
                        DButton(
                          label: Text(rtl ? 'استيراد مشروع' : 'Import Project'),
                          variant: DButtonVariant.outline,
                          onPressed: () => act('Import Project'),
                        ),
                    ],
                  ),
                ],
              ),
              if (basic)
                DButton(
                  label: Text(rtl ? 'تعرف على المزيد' : 'Learn More'),
                  variant: DButtonVariant.link,
                  size: DButtonSize.small,
                  iconPosition: DButtonIconPosition.end,
                  icon: Builder(
                    builder: (context) => Transform.rotate(
                      angle: rtl ? -math.pi / 2 : 0,
                      child: emptyReferenceIcon(context, 'arrow-up-right'),
                    ),
                  ),
                  onPressed: () => act('Project help opened'),
                ),
            ],
          ),
          if (_result != null)
            Semantics(liveRegion: true, child: Text(_result!)),
        ],
      ),
    );
  }
}

DAvatar _avatar(String label) => DAvatar(
  dimension: 48,
  semanticLabel: label,
  fallback: DAvatarFallback(child: Text(label)),
);

/// Local form fixture; resources stay owned by the native form and this state.
class EmptySearchSample extends StatefulWidget {
  const EmptySearchSample({super.key});
  @override
  State<EmptySearchSample> createState() => _EmptySearchSampleState();
}

class _EmptySearchSampleState extends State<EmptySearchSample> {
  final _form = GlobalKey<FormState>();
  String _query = '';
  String? _result;
  void _submit() {
    if (_form.currentState!.validate()) {
      _form.currentState!.save();
      setState(() => _result = 'No local pages match “$_query”.');
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: DEmpty(
      children: [
        const DEmptyHeader(
          children: [
            DEmptyTitle('404 - Not Found'),
            DEmptyDescription(
              "The page you're looking for doesn't exist. Try searching for what you need below.",
            ),
          ],
        ),
        DEmptyContent(
          children: [
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                width:
                    constraints.maxWidth *
                    (MediaQuery.sizeOf(context).width >= 640 ? .75 : 1),
                child: DInput(
                  hintText: 'Try searching for pages...',
                  labelText: 'Search pages',
                  prefix: const Icon(Icons.search, size: 16),
                  suffix: const DKbd('/'),
                  textInputAction: TextInputAction.search,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a search query.'
                      : null,
                  onSaved: (value) => _query = value!.trim(),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ),
            DButton(label: const Text('Search'), onPressed: _submit),
            DEmptyDescription.child(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Need help?'),
                  DButton(
                    label: const Text('Contact support'),
                    variant: DButtonVariant.link,
                    onPressed: () => setState(
                      () => _result =
                          'Support is available at help@example.test.',
                    ),
                  ),
                ],
              ),
            ),
            if (_result != null)
              Semantics(
                liveRegion: true,
                child: Text(_result!, textAlign: TextAlign.center),
              ),
          ],
        ),
      ],
    ),
  );
}

String _exampleCode(String kind) =>
    "// Mount _EmptySample(kind: '$kind') in your application.\n$emptySampleSource";
