// Isolated local-data review fixture. It performs no account or network writes.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/styleguide/examples/combobox_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _ComboboxReview());
}

class _ComboboxReview extends StatefulWidget {
  const _ComboboxReview();

  @override
  State<_ComboboxReview> createState() => _ComboboxReviewState();
}

class _ComboboxReviewState extends State<_ComboboxReview> {
  StyleguideTheme palette = StyleguideTheme.light;
  double scale = 1;
  bool rtl = false;
  bool reducedMotion = false;
  bool narrow = false;
  String saved = 'Nothing saved';

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: palette.resolve(AppTheme.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reducedMotion,
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('Combobox review — isolated local data'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final candidate in StyleguideTheme.values)
                  DButton(
                    label: Text(candidate.label),
                    onPressed: () => setState(() => palette = candidate),
                  ),
                DButton(
                  label: Text('${(scale * 100).round()}% text'),
                  onPressed: () => setState(() => scale = scale == 1 ? 2 : 1),
                ),
                DButton(
                  label: const Text('RTL'),
                  onPressed: () => setState(() => rtl = !rtl),
                ),
                DButton(
                  label: Text(reducedMotion ? 'Motion reduced' : 'Motion on'),
                  onPressed: () =>
                      setState(() => reducedMotion = !reducedMotion),
                ),
                DButton(
                  label: Text(narrow ? '216px preview' : '320px preview'),
                  onPressed: () => setState(() => narrow = !narrow),
                ),
                Text(saved),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      for (final example in comboboxExamples.examples) ...[
                        Text(
                          example.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: narrow ? 216 : 320,
                          child: Builder(builder: example.builder),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: GroupPage(
                    siteUrl: 'https://fixture.invalid',
                    route: GroupRoute.detail('support'),
                    registry: PluginRegistry.empty,
                    data: const GroupPageData(
                      detail: GroupDetail(
                        group: Group(
                          id: 9,
                          name: 'support',
                          fullName: 'Support Team',
                          userCount: 1,
                          canSeeMembers: true,
                          canAdminGroup: true,
                        ),
                      ),
                      members: GroupMembersPage(
                        members: [
                          GroupMember(
                            id: 3,
                            username: 'sam',
                            name: 'Sam Example',
                          ),
                        ],
                        total: 1,
                      ),
                      currentUserStaff: true,
                      loaded: true,
                    ),
                    onSearchUsers: (query) async => const [
                      FoundUser(username: 'lee', name: 'Lee Example'),
                      FoundUser(username: 'mira', name: 'Mira Example'),
                    ],
                    onAddMembers: (usernames, emails) async {
                      setState(
                        () => saved =
                            'Saved: ${[...usernames, ...emails].join(', ')}',
                      );
                      return GroupMembershipMutationResult(
                        usernames: usernames,
                        emails: emails,
                      );
                    },
                    onOpenMember: (_, _) {},
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
