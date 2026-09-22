import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const GroupsLayoutReview());
}

class GroupsLayoutReview extends StatefulWidget {
  const GroupsLayoutReview({super.key});

  @override
  State<GroupsLayoutReview> createState() => _GroupsLayoutReviewState();
}

class _GroupsLayoutReviewState extends State<GroupsLayoutReview> {
  bool _dark = true;
  bool _mobile = false;
  String _search = '';
  String? _type;
  String _opened = '';

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: (_dark ? AppTheme.dark : AppTheme.light).copyWith(
      platform: _mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: DSpacing.controlGap,
                  children: [
                    DButton(
                      label: Text(_dark ? 'Light palette' : 'Dark palette'),
                      onPressed: () => setState(() => _dark = !_dark),
                    ),
                    DButton(
                      label: Text(_mobile ? 'Desktop layout' : 'Mobile layout'),
                      onPressed: () => setState(() => _mobile = !_mobile),
                    ),
                    DButton(
                      label: const Text('Styleguide'),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const ComponentStyleguidePage(),
                        ),
                      ),
                    ),
                    if (_opened.isNotEmpty) Text('Opened $_opened'),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: _mobile ? 390 : 1000,
                    child: GroupsPage(
                      siteUrl: 'https://groups-review.invalid',
                      data: GroupsPageData(
                        groups: reviewGroups
                            .where(
                              (g) =>
                                  g.name.contains(_search) &&
                                  (_type != 'my' || g.isGroupUser),
                            )
                            .toList(),
                        totalRows: reviewGroups
                            .where(
                              (g) =>
                                  g.name.contains(_search) &&
                                  (_type != 'my' || g.isGroupUser),
                            )
                            .length,
                        typeFilters: const ['my', 'automatic', 'public'],
                        query: _search,
                        type: _type,
                        loaded: true,
                      ),
                      onSearchChanged: (value) =>
                          setState(() => _search = value),
                      onTypeChanged: (value) => setState(() => _type = value),
                      onRefresh: () async {},
                      onOpenGroup: (group) =>
                          setState(() => _opened = group.name),
                      loadMemberPreview: (group) async => [
                        for (
                          var i = 0;
                          i < (group.userCount! < 4 ? group.userCount! : 4);
                          i++
                        )
                          GroupMember(
                            id: i + 1,
                            username: ['Gavin', 'Chris', 'Sam', 'Val'][i],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

const reviewGroups = [
  Group(
    id: 1,
    name: 'admins',
    userCount: 20,
    canSeeMembers: true,
    isGroupUser: true,
    flairIcon: 'gear',
    flairBackgroundColor: '66532a',
    flairColor: 'f8d477',
    bioExcerpt: 'First responders for anything urgent.',
  ),
  Group(
    id: 2,
    name: 'moderators',
    userCount: 89,
    canSeeMembers: true,
    isGroupUser: true,
    flairIcon: 'flag',
    flairBackgroundColor: '294e68',
    flairColor: '98cde8',
  ),
  Group(
    id: 3,
    name: 'staff',
    userCount: 1,
    canSeeMembers: true,
    flairIcon: 'users',
    flairBackgroundColor: '275a4b',
    flairColor: '96d4b4',
  ),
  Group(
    id: 4,
    name: 'trust_level_3',
    userCount: 12,
    canSeeMembers: true,
    flairBackgroundColor: 'a457b9',
    flairColor: 'ffffff',
  ),
  Group(
    id: 5,
    name: 'beta-testers',
    userCount: 1,
    canSeeMembers: true,
    isGroupUser: true,
    flairIcon: 'flag-checkered',
    flairBackgroundColor: '674631',
    flairColor: 'edb18b',
    bioExcerpt: 'Reviews and ships the release notes.',
  ),
  Group(
    id: 6,
    name: 'community-leads',
    userCount: 18,
    canSeeMembers: true,
    flairBackgroundColor: '16bba6',
    flairColor: 'ffffff',
  ),
  Group(
    id: 7,
    name: 'design-team',
    userCount: 22,
    canSeeMembers: true,
    isGroupUser: true,
    flairIcon: 'palette',
    flairBackgroundColor: '66532a',
    flairColor: 'f8d477',
    bioExcerpt: 'Looks after the handbook and the guides.',
  ),
];
