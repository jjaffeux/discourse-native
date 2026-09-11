import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/user_directory_column_width_store.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/shell/user_directory_controller.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/styleguide/examples/data_table_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Offline production-widget fixture. Widths stay in memory; no account calls.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _Review());
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = false;
  bool _narrow = false;
  bool _large = false;
  bool _rtl = false;
  bool _example = false;
  String _status = 'Ready';
  UserDirectoryQuery _query = const UserDirectoryQuery();
  final _store = UserDirectoryColumnWidthStore(persistence: _Widths());
  List<UserDirectoryColumn> _columns = const [
    UserDirectoryColumn(
      id: 1,
      name: 'likes_received',
      type: UserDirectoryColumnType.automatic,
      position: 1,
    ),
    UserDirectoryColumn(
      id: 2,
      name: 'post_count',
      type: UserDirectoryColumnType.automatic,
      position: 2,
    ),
    UserDirectoryColumn(
      id: 3,
      name: 'days_visited',
      type: UserDirectoryColumnType.automatic,
      position: 3,
    ),
    UserDirectoryColumn(
      id: 4,
      name: 'time_read',
      type: UserDirectoryColumnType.automatic,
      position: 4,
    ),
  ];
  final _rows = List.generate(
    1000,
    (index) => UserDirectoryItem(
      id: index + 1,
      user: UserDirectoryUser(
        id: index + 1,
        username: 'member${index + 1}',
        name: 'Community member ${index + 1}',
        primaryGroupName: index % 10 == 0 ? 'staff' : null,
      ),
      values: {
        'likes_received': 2000 - index,
        'post_count': index * 3,
        'days_visited': index % 30,
        'time_read': index * 600,
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final items = _rows
        .where(
          (row) =>
              row.user.username.contains(_query.search) &&
              (_query.group == null ||
                  row.user.primaryGroupName == _query.group),
        )
        .toList();
    items.sort((a, b) {
      final result = _query.order == 'username'
          ? a.user.username.compareTo(b.user.username)
          : (a.values[_query.order] as int? ?? 0).compareTo(
              b.values[_query.order] as int? ?? 0,
            );
      return _query.ascending ? result : -result;
    });
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: (_dark ? AppTheme.dark : AppTheme.light).copyWith(
        platform: TargetPlatform.macOS,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DButton(
                      label: Text(_dark ? 'Dark' : 'Light'),
                      onPressed: () => setState(() => _dark = !_dark),
                    ),
                    DButton(
                      label: Text(_narrow ? '390px' : 'Wide'),
                      onPressed: () => setState(() => _narrow = !_narrow),
                    ),
                    DButton(
                      label: Text(_large ? '200% text' : '100% text'),
                      onPressed: () => setState(() => _large = !_large),
                    ),
                    DButton(
                      label: Text(_rtl ? 'RTL' : 'LTR'),
                      onPressed: () => setState(() => _rtl = !_rtl),
                    ),
                    DButton(
                      label: Text(_example ? 'Styleguide' : 'Users'),
                      onPressed: () => setState(() => _example = !_example),
                    ),
                    DSelect<String>(
                      width: 140,
                      value: _status,
                      onChanged: (value) => setState(() => _status = value!),
                      entries: [
                        for (final status in [
                          'Ready',
                          'Loading',
                          'Empty',
                          'Error',
                        ])
                          DSelectItem(
                            value: status,
                            textValue: status,
                            child: Text(status),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Align(
                  child: SizedBox(
                    width: _narrow ? 390 : double.infinity,
                    child: Builder(
                      builder: (context) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(_large ? 2 : 1),
                        ),
                        child: Directionality(
                          textDirection: _rtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: _example
                              ? SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      for (final example
                                          in dataTableExamples.examples)
                                        Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            children: [
                                              Text(example.title),
                                              Builder(builder: example.builder),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                )
                              : UsersPage(
                                  siteUrl: 'https://users-review.invalid',
                                  columnWidthStore: _store,
                                  data: UsersPageData(
                                    items: _status == 'Ready'
                                        ? items
                                        : const [],
                                    columns: _columns
                                        .where((column) => column.enabled)
                                        .toList(),
                                    availableColumns: _columns,
                                    groupNames: const ['staff'],
                                    canManageColumns: true,
                                    currentUsername: 'member1',
                                    query: _query,
                                    totalRows: items.length,
                                    loaded: _status != 'Loading',
                                    loading: _status == 'Loading',
                                    error: _status == 'Error'
                                        ? 'The directory could not be loaded.'
                                        : null,
                                  ),
                                  onSearchChanged: (value) => setState(
                                    () =>
                                        _query = _query.copyWith(search: value),
                                  ),
                                  onPeriodChanged: (value) => setState(
                                    () =>
                                        _query = _query.copyWith(period: value),
                                  ),
                                  onGroupChanged: (value) => setState(
                                    () => _query = value == null
                                        ? _query.withoutGroup()
                                        : _query.copyWith(group: value),
                                  ),
                                  onSortChanged: (order, ascending) => setState(
                                    () => _query = _query.copyWith(
                                      order: order,
                                      ascending: ascending,
                                    ),
                                  ),
                                  onManageColumns: (columns) async {
                                    setState(() => _columns = columns);
                                    return true;
                                  },
                                  onRefresh: () async {},
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Widths implements UserDirectoryColumnWidthPersistence {
  String? _value;
  @override
  Future<String?> readWidths({required String siteUrl}) async => _value;
  @override
  Future<bool> writeWidths({
    required String siteUrl,
    required String encoded,
  }) async {
    _value = encoded;
    return true;
  }
}
