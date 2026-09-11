import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_sheet.dart';
import 'package:discourse_native/src/styleguide/examples/guarded_modal_example.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const AssignmentReviewApp());
}

/// Local-data fixture mounting the production assignment form and kit routes.
class AssignmentReviewApp extends StatefulWidget {
  const AssignmentReviewApp({super.key});

  @override
  State<AssignmentReviewApp> createState() => _AssignmentReviewAppState();
}

class _AssignmentReviewAppState extends State<AssignmentReviewApp> {
  bool _dark = false;
  bool _narrow = false;
  bool _large = false;
  bool _rtl = false;
  bool _fail = false;
  bool _statuses = false;
  Assignment? _assignment;
  final _suggestions = AssignmentSuggestions(
    users: const [
      AssignmentUser(username: 'j.jaffeux', name: 'Joffrey Jaffeux'),
      AssignmentUser(username: 'MarkDoerr', name: 'MarkDoerr'),
      AssignmentUser(username: 'martin', name: 'Martin Brennan'),
      AssignmentUser(username: 'peter', name: 'Peter'),
    ],
    assignAllowedForGroups: const ['support', 'team'],
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _toggle('Light / dark', () => _dark = !_dark),
                  _toggle('Desktop / mobile', () => _narrow = !_narrow),
                  _toggle('100 / 200%', () => _large = !_large),
                  _toggle('LTR / RTL', () => _rtl = !_rtl),
                  _toggle('Save error: $_fail', () => _fail = !_fail),
                  _toggle('Statuses: $_statuses', () => _statuses = !_statuses),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = _narrow ? 390.0 : constraints.maxWidth;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: width,
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            size: Size(width, constraints.maxHeight),
                            textScaler: TextScaler.linear(_large ? 2 : 1),
                          ),
                          child: Directionality(
                            textDirection: _rtl
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: Navigator(
                              onGenerateRoute: (_) => MaterialPageRoute<void>(
                                builder: (context) => Scaffold(
                                  body: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      spacing: 16,
                                      children: [
                                        const DLabel(
                                          child: Text(
                                            'Assignment review · local data',
                                          ),
                                        ),
                                        DButton(
                                          label: const Text('Assign topic'),
                                          onPressed: () => _open(context),
                                        ),
                                        const GuardedModalExample(),
                                        const GuardedModalExample(drawer: true),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _toggle(String label, VoidCallback change) => DButton(
    label: Text(label),
    variant: DButtonVariant.outline,
    onPressed: () => setState(change),
  );

  Future<void> _open(BuildContext context) {
    final drawer = MediaQuery.sizeOf(context).width < 768;
    var saving = false;
    Widget editor(VoidCallback close) => AssignmentEditor(
      drawer: drawer,
      existing: _assignment,
      title: _assignment == null ? 'Assign topic' : 'Edit topic assignment',
      statusesEnabled: _statuses,
      statuses: const ['Open', 'In progress', 'Done'],
      loadSuggestions: () async => _suggestions,
      searchAssignees: (_, term) async => _suggestions.initialAssignees
          .where(
            (person) => '${person.displayName} ${person.identifier}'
                .toLowerCase()
                .contains(term.toLowerCase()),
          )
          .toList(),
      save: (assignee, {note, status}) async {
        saving = true;
        await Future<void>.delayed(const Duration(seconds: 2));
        saving = false;
        if (_fail) return 'Assignment could not be saved. Please try again.';
        _assignment = Assignment(
          assignee: assignee,
          note: note,
          status: status,
        );
        return null;
      },
      remove: _assignment == null
          ? null
          : () async {
              _assignment = null;
              return null;
            },
      onCancel: close,
      onComplete: close,
    );
    return drawer
        ? showDDrawer<void>(
            context: context,
            showSwipeHandle: true,
            requestInitialFocus: false,
            canDismiss: () => !saving,
            builder: (_, modal) => editor(modal.close),
          )
        : showDDialog<void>(
            context: context,
            canDismiss: () => !saving,
            builder: (_, modal) => editor(modal.close),
          );
  }
}
