final dashboardFixture = <String, dynamic>{
  'sections': [
    {
      'id': 'highlights',
      'data': {
        'kpis': [
          {
            'type': 'new_signups',
            'value': 128,
            'previous_value': 100,
            'percent_change': 28,
          },
          {'type': 'dau_mau', 'value': 24.5, 'percent_change': -1.5},
          {'type': 'new_contributors', 'value': 42, 'percent_change': 5},
        ],
      },
    },
    {
      'id': 'reports',
      'data': {
        'items': [
          {
            'source': 'core_report',
            'identifier': 'daily_engaged_users',
            'title': 'Daily engaged users',
            'url': '/admin/reports/daily_engaged_users',
            'rows': 1,
            'cols': 1,
          },
          {
            'source': 'core_report',
            'identifier': 'time_to_first_response',
            'title': 'Time to first response',
            'url': '/admin/reports/time_to_first_response',
            'rows': 1,
            'cols': 1,
          },
        ],
      },
    },
    {
      'id': 'traffic',
      'data': {
        'kpis': {
          'browser_pageviews': {'value': 2500, 'percent_change': 14},
          'logged_in_share': {'value': 40},
          'bounce_rate': {'value': 32},
          'average_session_duration_seconds': {'value': 170},
        },
        'pageview_series': [
          {
            'req': 'page_view_logged_in_browser',
            'label': 'Logged in',
            'data': [
              {'x': '2026-10-23', 'y': 30},
              {'x': '2026-10-24', 'y': 40},
              {'x': '2026-10-25', 'y': 35},
            ],
          },
          {
            'req': 'page_view_anon_browser',
            'label': 'Anonymous',
            'data': [
              {'x': '2026-10-23', 'y': 60},
              {'x': '2026-10-24', 'y': 50},
              {'x': '2026-10-25', 'y': 70},
            ],
          },
          {
            'req': 'page_view_crawler',
            'label': 'Crawlers',
            'data': [
              {'x': '2026-10-23', 'y': 90},
              {'x': '2026-10-24', 'y': 100},
              {'x': '2026-10-25', 'y': 85},
            ],
          },
        ],
        'top_referrers': {
          'rows': [
            {'normalized_referrer': 'google.com', 'count': 800, 'percent': 32},
          ],
          'error': null,
        },
        'top_entry_urls': {
          'rows': [
            {'entry_url': '/t/sailing/42', 'count': 100, 'percent': 4},
          ],
          'error': null,
        },
        'top_countries': {
          'rows': [
            {'country_code': 'FR', 'count': 600, 'percent': 24},
          ],
          'error': null,
        },
      },
    },
    {
      'id': 'engagement',
      'data': {
        'kpis': [
          {'type': 'daily_engaged_users', 'value': 180, 'percent_change': 4},
        ],
        'trust_level_pipeline': {
          'rows': [
            {
              'trust_level': 1,
              'name': 'Basic',
              'count': 700,
              'share': 50,
              'promoted_in': 10,
              'demoted_in': 1,
            },
          ],
        },
        'posters': {
          'rows': [
            {'name': 'Returning', 'count': 180, 'share': 75},
          ],
        },
        'activity_by_category': {
          'rows': [
            {
              'category_id': 5,
              'name': 'Sailing',
              'topics': 30,
              'posts': 90,
              'page_views': 200,
              'share': 40,
              'share_change': 2,
            },
          ],
        },
      },
    },
    {
      'id': 'search',
      'data': {
        'logging_enabled': true,
        'kpis': {
          'total_searches': {'value': 140},
          'no_result_rate': {'value': 12, 'point_change': -3},
        },
        'trending': [
          {'term': 'sailing', 'searches': 40},
        ],
        'content_gaps': [
          {'term': 'rigging', 'searches': 10, 'status': 'no_match'},
        ],
      },
    },
    {
      'id': 'system',
      'data': {
        'version': {
          'installed_version': '3.6.0',
          'latest_version': '3.7.0',
          'installed_sha': 'abcdef0123456789',
          'updated_at': '2026-10-25T00:00:00Z',
        },
        'storage': {
          'uploads': {
            'used_bytes': 104857600,
            'free_bytes': 314572800,
            'remote': false,
          },
          'backups': {
            'used_bytes': 104857600,
            'free_bytes': 314572800,
            'remote': false,
            'count': 2,
          },
        },
        'discourse_updated_at': '2026-10-24T00:00:00Z',
        'dashboard_updated_at': '2026-10-25T00:00:00Z',
      },
    },
  ],
  'problems': [
    {
      'id': 1,
      'priority': 'high',
      'message': '<p>Email is failing.</p>',
      'identifier': 'email',
    },
  ],
  'configuration': {
    'sections': [
      for (final id in [
        'highlights',
        'reports',
        'traffic',
        'engagement',
        'search',
        'system',
      ])
        {'id': id, 'visible': true},
      {'id': 'plugin_health', 'visible': false},
    ],
  },
};
final dashboardReportsFixture = <String, dynamic>{
  'items': [
    {
      'key': 'core_report:daily_engaged_users',
      'data': {
        'data': [
          {'x': '2026-10-23', 'y': 160},
          {'x': '2026-10-24', 'y': 180},
          {'x': '2026-10-25', 'y': 200},
        ],
        'average': true,
      },
      'error': false,
    },
    {
      'key': 'core_report:time_to_first_response',
      'data': {
        'data': [
          {'x': '2026-10-23', 'y': 2},
          {'x': '2026-10-24', 'y': 3},
          {'x': '2026-10-25', 'y': 4},
        ],
        'average': true,
      },
      'error': false,
    },
  ],
};
