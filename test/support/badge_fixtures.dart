final badgeWire = <String, dynamic>{
  'id': 1,
  'name': 'Autobiographer',
  'slug': 'autobiographer',
  'description':
      'Filled out <a href="/my/preferences/profile">profile</a> information',
  'long_description':
      '<p>This badge is granted for completing your profile.</p>',
  'badge_type_id': 3,
  'badge_grouping_id': 1,
  'grant_count': 60,
  'has_badge': true,
  'enabled': true,
  'listable': true,
  'icon': 'user-pen',
  'multiple_grant': false,
  'allow_title': false,
};

final badgeCatalogWire = <String, dynamic>{
  'badges': [
    badgeWire,
    {
      ...badgeWire,
      'id': 2,
      'name': 'Reader',
      'slug': 'reader',
      'icon': 'book-open-reader',
      'has_badge': false,
    },
    {
      ...badgeWire,
      'id': 3,
      'name': 'Nice Reply',
      'badge_grouping_id': 2,
      'badge_type_id': 2,
    },
  ],
  'badge_types': [
    {'id': 1, 'name': 'Gold'},
    {'id': 2, 'name': 'Silver'},
    {'id': 3, 'name': 'Bronze'},
  ],
  'badge_groupings': [
    {'id': 2, 'name': 'Community', 'position': 11, 'system': true},
    {'id': 1, 'name': 'Getting Started', 'position': 10, 'system': true},
  ],
};

Map<String, dynamic> badgeGrantsWire({
  int offset = 0,
  int count = 1,
  int? total,
}) => {
  'user_badge_info': {
    'user_badges': [
      for (var i = offset; i < offset + count; i++)
        {
          'id': i + 1,
          'user_id': 42,
          'granted_at': '2026-09-08T09:15:00Z',
          'topic_id': 100,
          'post_number': 3,
          'post_id': 101,
        },
    ],
    'grant_count': total,
    'username': null,
  },
  'users': [
    {'id': 42, 'username': 'sam', 'name': 'Sam'},
  ],
  'topics': [
    {'id': 100, 'slug': 'welcome', 'title': 'Welcome to the community'},
  ],
};
