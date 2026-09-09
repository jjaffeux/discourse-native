import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final questionnaireExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'A one-question-at-a-time form for fixed, multiple, freeform and intentionally skipped answers.',
  notes:
      'DQuestionnaireController is the unstyled behavior owner: it keeps typed '
      'answers, stable item identity, visited state, validation and navigation. '
      'Disabled conditional items retain their draft but leave progress, validation '
      'and submission. DQuestionnaireSavedState is JSON-ready for host-owned '
      'persistence. Async validation is revision-cancelled when answers change. '
      'The styled widget matches base-nova geometry and composes DButton, DInput, '
      'DProgress, DCard, DDialog and DNativeSelect. Flutter builds deterministic '
      'initial markup rather than React server HTML; persistence, transport, close '
      'and branching remain outside the component.',
  examples: [
    StyleguideExample(
      title: 'Basic composition',
      description:
          'The reference three-step flow combines a fixed/freeform answer, multiple selection and a final fixed answer.',
      states: const [
        'Single',
        'Multiple',
        'Freeform',
        'Explicit skip',
        'Composition',
      ],
      code: '''DQuestionnaire(
  items: planningItems,
  onSubmit: (answers) => savePlan(answers),
)''',
      builder: (_) => const _BasicQuestionnaire(),
    ),
    StyleguideExample(
      title: 'Answer shortcuts',
      description:
          'Choose letter or number hints. Disabled choices do not consume a shortcut and typing in the freeform field is never intercepted.',
      states: const ['Letters', 'Numbers', 'Keyboard', 'Native select'],
      code: '''DQuestionnaire(
  shortcuts: DQuestionnaireShortcutMode.letters,
  items: items,
)''',
      builder: (_) => const _ShortcutQuestionnaire(),
    ),
    StyleguideExample(
      title: 'Custom and async validation',
      description:
          'The answer is checked asynchronously. Editing while validation is pending cancels the stale result.',
      states: const ['Required', 'Async', 'Cancellation', 'Error focus'],
      code: '''DQuestionnaireItem(
  id: 'handoff', required: true,
  validator: (answer, snapshot) async => validate(answer),
  // ...
)''',
      builder: (_) => const _ValidationQuestionnaire(),
    ),
    StyleguideExample(
      title: 'Controlled navigation',
      description:
          'The host accepts each requested checkpoint and can reject or redirect it before the controller changes items.',
      states: const ['Controlled', 'Acceptance', 'Navigation state'],
      code: '''DQuestionnaire(
  currentItemId: checkpoint,
  onCurrentItemChanged: (next) {
    setState(() => checkpoint = next);
    return true;
  },
  items: items,
)''',
      builder: (_) => const _ControlledQuestionnaire(),
    ),
    StyleguideExample(
      title: 'Resume and reset',
      description:
          'Starts on question two with saved fixed, multiple and freeform answers. Reset returns to that saved draft.',
      states: const ['Serializable', 'Resume', 'Reset', 'Visited'],
      code: '''final saved = DQuestionnaireSavedState.fromJson(json);
DQuestionnaire(items: items, initialState: saved)''',
      builder: (_) => const _ResumeQuestionnaire(),
    ),
    StyleguideExample(
      title: 'Conditional and custom progress',
      description:
          'Cloud adds a region step. Progress immediately reflects the visible flow and only the item transition animates.',
      states: const [
        'Conditional',
        'Custom progress',
        'Animated items',
        'Reduced motion',
      ],
      code: '''DQuestionnaire(
  animateItems: true,
  progressBuilder: (_, state, __) => DProgress(
    value: state.current.toDouble(), max: state.total.toDouble()),
  items: conditionalItems,
)''',
      builder: (_) => const _ConditionalQuestionnaire(),
    ),
    StyleguideExample(
      title: 'Card composition',
      description:
          'Question semantics stay in Questionnaire while Card owns the passive surface.',
      states: const ['Card', 'Composition'],
      code: '''DCard(children: [
  DCardContent(child: DQuestionnaire(items: items)),
])''',
      builder: (_) => const _CardQuestionnaire(),
    ),
    StyleguideExample(
      title: 'Dialog composition',
      description:
          'The Dialog host owns Escape, outside dismissal, cancellation and focus restoration.',
      states: const ['Dialog', 'Focus restoration', 'Host cancellation'],
      code: '''showDDialog<void>(context: context, builder: (_, __) =>
  DDialogContent(children: [DQuestionnaire(items: items)]))''',
      builder: (_) => const _DialogQuestionnaire(),
    ),
    StyleguideExample(
      title: 'Unstyled behavior',
      description:
          'A caller-authored surface listens directly to the controller without using the styled Questionnaire root.',
      states: const ['Headless', 'Typed state', 'Custom composition'],
      code: '''AnimatedBuilder(
  animation: controller,
  builder: (_, __) => buildCustomQuestion(controller.snapshot),
)''',
      builder: (_) => const _HeadlessQuestionnaire(),
    ),
  ],
);

DQuestionnaireChoice<Object> _choice(
  String value,
  String label, {
  String? description,
  bool enabled = true,
}) => DQuestionnaireChoice<Object>(
  value: value,
  label: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
  description: description == null ? null : Text(description),
  semanticLabel: description == null ? label : '$label. $description',
  enabled: enabled,
);

List<DQuestionnaireItem> _planningItems() => [
  DQuestionnaireItem(
    id: 'direction',
    required: true,
    title: const Text('What should the agent build next?'),
    description: const Text('Choose a direction or describe another task.'),
    choices: [
      _choice(
        'timeline',
        'Tool call timeline',
        description: 'Show what the agent ran and what came back.',
      ),
      _choice(
        'approvals',
        'Approval checkpoints',
        description: 'Ask before sensitive or destructive actions.',
      ),
      _choice(
        'handoffs',
        'Sub-agent handoffs',
        description: 'Make delegated work and results easier to follow.',
      ),
    ],
    input: const DQuestionnaireInputConfiguration(
      label: 'Describe another feature',
      placeholder: 'Describe another feature…',
    ),
  ),
  DQuestionnaireItem(
    id: 'updates',
    multiple: true,
    required: false,
    title: const Text('What should every progress update include?'),
    description: const Text('Select all that apply, or skip this question.'),
    choices: [
      _choice('progress', 'Progress'),
      _choice('decisions', 'Decisions'),
      _choice('risks', 'Risks'),
      _choice('next', 'Next step'),
    ],
  ),
  DQuestionnaireItem(
    id: 'timing',
    required: true,
    title: const Text('When should work begin?'),
    description: const Text('Choose when the agent should begin the work.'),
    choices: [
      _choice('now', 'Start now'),
      _choice('cycle', 'Next development cycle'),
      _choice('backlog', 'Add it to the backlog'),
    ],
  ),
];

class _ExampleFrame extends StatelessWidget {
  const _ExampleFrame({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 448),
      child: child,
    ),
  );
}

class _BasicQuestionnaire extends StatefulWidget {
  const _BasicQuestionnaire();
  @override
  State<_BasicQuestionnaire> createState() => _BasicQuestionnaireState();
}

class _BasicQuestionnaireState extends State<_BasicQuestionnaire> {
  String? result;
  @override
  Widget build(BuildContext context) => _ExampleFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DQuestionnaire(
          items: _planningItems(),
          submitLabel: 'Save plan',
          onSubmit: (answers) => setState(() {
            result = 'Saved ${answers.answers.length} answers';
          }),
        ),
        if (result != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(result!)),
        ],
      ],
    ),
  );
}

class _ShortcutQuestionnaire extends StatefulWidget {
  const _ShortcutQuestionnaire();
  @override
  State<_ShortcutQuestionnaire> createState() => _ShortcutQuestionnaireState();
}

class _ShortcutQuestionnaireState extends State<_ShortcutQuestionnaire> {
  DQuestionnaireShortcutMode? mode = DQuestionnaireShortcutMode.letters;
  late final items = [
    DQuestionnaireItem(
      id: 'action',
      required: true,
      title: const Text('What should the agent do next?'),
      description: const Text(
        'Use the displayed shortcut or navigate with the keyboard.',
      ),
      choices: [
        _choice('inspect', 'Inspect the implementation'),
        _choice('disabled', 'Unavailable action', enabled: false),
        _choice('tests', 'Run the relevant tests'),
        _choice('patch', 'Prepare the patch'),
      ],
      input: const DQuestionnaireInputConfiguration(
        label: 'Another action',
        placeholder: 'Type another action…',
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) => _ExampleFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 170,
          child: DNativeSelect<DQuestionnaireShortcutMode>(
            entries: const [
              DNativeSelectOption(
                value: DQuestionnaireShortcutMode.letters,
                label: 'Letters',
              ),
              DNativeSelectOption(
                value: DQuestionnaireShortcutMode.numbers,
                label: 'Numbers',
              ),
            ],
            initialValue: mode,
            placeholder: 'No shortcuts',
            label: 'Shortcut style',
            onChanged: (value) => setState(() => mode = value),
          ),
        ),
        const SizedBox(height: 16),
        DQuestionnaire(items: items, shortcuts: mode),
      ],
    ),
  );
}

class _ValidationQuestionnaire extends StatefulWidget {
  const _ValidationQuestionnaire();
  @override
  State<_ValidationQuestionnaire> createState() =>
      _ValidationQuestionnaireState();
}

class _ValidationQuestionnaireState extends State<_ValidationQuestionnaire> {
  late final items = [
    DQuestionnaireItem(
      id: 'handoff',
      required: true,
      title: const Text('How detailed should the handoff be?'),
      description: const Text(
        'Public handoffs require enough context for another reviewer.',
      ),
      choices: [
        _choice('summary', 'Concise summary'),
        _choice('complete', 'Complete handoff'),
      ],
      validator: (answer, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        return answer.valueAs<String>() == 'summary'
            ? 'Choose a complete handoff for this audience.'
            : null;
      },
    ),
  ];

  @override
  Widget build(BuildContext context) =>
      _ExampleFrame(child: DQuestionnaire(items: items));
}

class _ControlledQuestionnaire extends StatefulWidget {
  const _ControlledQuestionnaire();
  @override
  State<_ControlledQuestionnaire> createState() =>
      _ControlledQuestionnaireState();
}

class _ControlledQuestionnaireState extends State<_ControlledQuestionnaire> {
  String checkpoint = 'scope';
  bool allowNavigation = true;
  late final items = [
    DQuestionnaireItem(
      id: 'scope',
      required: true,
      title: const Text('What may the agent change?'),
      choices: [
        _choice('component', 'Only the target component'),
        _choice('tests', 'Component and related tests'),
      ],
    ),
    DQuestionnaireItem(
      id: 'verification',
      required: true,
      title: const Text('Which verification level should it use?'),
      choices: [
        _choice('targeted', 'Targeted tests'),
        _choice('package', 'Package tests and typecheck'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => _ExampleFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Current checkpoint: $checkpoint'),
        DSwitchTile(
          value: allowNavigation,
          title: const Text('Host accepts navigation'),
          onChanged: (value) => setState(() => allowNavigation = value),
        ),
        DQuestionnaire(
          currentItemId: checkpoint,
          items: items,
          onCurrentItemChanged: (next) {
            if (!allowNavigation) return false;
            setState(() => checkpoint = next);
            return true;
          },
        ),
      ],
    ),
  );
}

class _ResumeQuestionnaire extends StatefulWidget {
  const _ResumeQuestionnaire();
  @override
  State<_ResumeQuestionnaire> createState() => _ResumeQuestionnaireState();
}

class _ResumeQuestionnaireState extends State<_ResumeQuestionnaire> {
  late final items = _planningItems();
  late final saved = DQuestionnaireSavedState(
    currentItemId: 'updates',
    answers: {
      'direction': DQuestionnaireAnswer.fixed(const ['timeline']),
      'updates': DQuestionnaireAnswer.fixed(const ['progress', 'risks']),
    },
    visitedItemIds: const {'direction', 'updates'},
  );

  @override
  Widget build(BuildContext context) => _ExampleFrame(
    child: DQuestionnaire(items: items, initialState: saved, showReset: true),
  );
}

class _ConditionalQuestionnaire extends StatefulWidget {
  const _ConditionalQuestionnaire();
  @override
  State<_ConditionalQuestionnaire> createState() =>
      _ConditionalQuestionnaireState();
}

class _ConditionalQuestionnaireState extends State<_ConditionalQuestionnaire> {
  late final items = [
    DQuestionnaireItem(
      id: 'runtime',
      required: true,
      title: const Text('Where should the agent run?'),
      description: const Text('Cloud adds an environment question.'),
      choices: [
        _choice('local', 'Local workspace'),
        _choice('cloud', 'Cloud workspace'),
      ],
    ),
    DQuestionnaireItem(
      id: 'region',
      required: true,
      enabledWhen: (state) => state.valueFor<String>('runtime') == 'cloud',
      title: const Text('Which cloud environment should it use?'),
      choices: [
        _choice('preview', 'Preview'),
        _choice('staging', 'Staging'),
        _choice('sandbox', 'Isolated sandbox'),
      ],
    ),
    DQuestionnaireItem(
      id: 'approval',
      required: true,
      title: const Text('When should the agent request approval?'),
      choices: [
        _choice('files', 'Before writing files'),
        _choice('commands', 'Before running commands'),
        _choice('sensitive', 'Only for sensitive actions'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => _ExampleFrame(
    child: DQuestionnaire(
      items: items,
      animateItems: true,
      progressBuilder: (context, state, _) => DProgress(
        value: state.current.toDouble(),
        min: 0,
        max: state.total.toDouble(),
        label: DProgressLabel(
          child: Text('Checkpoint ${state.current} of ${state.total}'),
        ),
      ),
    ),
  );
}

class _CardQuestionnaire extends StatelessWidget {
  const _CardQuestionnaire();
  @override
  Widget build(BuildContext context) => _ExampleFrame(
    child: DCard(
      children: [
        const DCardHeader(
          title: DCardTitle(child: Text('Create a task')),
          description: DCardDescription(
            child: Text('Choose the task and review depth.'),
          ),
        ),
        DCardContent(
          child: DQuestionnaire(items: _planningItems().take(2).toList()),
        ),
      ],
    ),
  );
}

class _DialogQuestionnaire extends StatelessWidget {
  const _DialogQuestionnaire();

  @override
  Widget build(BuildContext context) => DButton(
    label: const Text('Open clarification'),
    onPressed: () => showDDialog<void>(
      context: context,
      builder: (dialogContext, dialog) => DDialogContent(
        semanticLabel: 'Clarification questionnaire',
        children: [
          const DDialogHeader(
            children: [
              DDialogTitle(child: Text('Clarify the request')),
              DDialogDescription(
                child: Text('Cancellation and dismissal remain dialog-owned.'),
              ),
            ],
          ),
          DQuestionnaire(
            items: _planningItems().take(2).toList(),
            submitLabel: 'Send answers',
            onSubmit: (_) => dialog.close(),
          ),
        ],
      ),
    ),
  );
}

class _HeadlessQuestionnaire extends StatefulWidget {
  const _HeadlessQuestionnaire();
  @override
  State<_HeadlessQuestionnaire> createState() => _HeadlessQuestionnaireState();
}

class _HeadlessQuestionnaireState extends State<_HeadlessQuestionnaire> {
  late final DQuestionnaireController controller = DQuestionnaireController(
    items: _planningItems().take(2).toList(),
  );

  @override
  Widget build(BuildContext context) => _ExampleFrame(
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final item = controller.currentItem!;
        final answer = controller.answerFor(item.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${controller.progress.current}/${controller.progress.total} · ${item.id} · ${answer.status.name}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in item.choices)
                  DButton(
                    variant: answer.values.contains(choice.value)
                        ? DButtonVariant.secondary
                        : DButtonVariant.outline,
                    onPressed: () => item.multiple
                        ? controller.toggle(item.id, choice.value)
                        : controller.setSingle(item.id, choice.value),
                    label: choice.label,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DQuestionnaireActions(
              previous: controller.canGoPrevious ? controller.previous : null,
              skip: controller.canSkip ? controller.skip : null,
              next: controller.canGoNext ? controller.next : null,
              reset: controller.reset,
            ),
          ],
        );
      },
    ),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
