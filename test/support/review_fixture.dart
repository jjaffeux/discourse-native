/// `GET /review.json` as core serializes it: rows carry ids, and the records
/// they name are side-loaded at the top level (`embed :ids, include: true`).
/// Shapes follow `ReviewableSerializer` and its subclasses, and
/// `ReviewablesController#index`, in discourse/discourse.
Map<String, dynamic> reviewListFixture({bool more = true}) => {
  'reviewables': [
    {
      'id': 77,
      'type': 'ReviewableFlaggedPost',
      'type_source': 'core',
      'topic_id': 45,
      'topic_url': '/t/dock-lines/45',
      'target_type': 'Post',
      'target_id': 900,
      'target_url': 'https://forum.example/discuss/t/dock-lines/45/3',
      'category_id': 5,
      'created_at': '2026-11-10T09:00:00.000Z',
      'can_edit': false,
      'score': 9.0,
      'version': 2,
      'created_from_flag': true,
      'status': 0,
      'target_created_by_id': 12,
      'created_by_id': 3,
      'reviewable_score_ids': [501, 502],
      'bundled_action_ids': ['77-agree', '77-disagree'],
      'claimed_by_id': null,
      'cooked': '<p>Buy cheap rope here</p>',
      'raw': 'Buy cheap rope here',
      'post_id': 900,
    },
    {
      'id': 78,
      'type': 'ReviewableQueuedPost',
      'status': 0,
      'score': 1.0,
      'version': 0,
      'created_at': '2026-11-11T09:00:00.000Z',
      'target_created_by_id': 12,
      'reviewable_score_ids': [503],
      'bundled_action_ids': ['78-approve_post', '78-reject'],
      'payload': {'raw': 'First post body', 'title': 'Hello harbour'},
      'fancy_title': 'Hello harbour',
      'cooked': '<p>First post body</p>',
    },
    {
      'id': 79,
      'type': 'ReviewableUser',
      'status': 0,
      'score': 0.0,
      'version': 0,
      'created_at': '2026-11-12T09:00:00.000Z',
      'target_created_by_id': 14,
      'reviewable_score_ids': <int>[],
      'bundled_action_ids': ['79-approve_user', '79-reject_user'],
      'payload': {'username': 'newbie', 'email': 'newbie@example.com'},
    },
    {
      'id': 80,
      'type': 'Chat::ReviewableMessage',
      'status': 0,
      'version': 1,
      'target_created_by_id': 12,
      'reviewable_score_ids': <int>[],
      'bundled_action_ids': <String>[],
      'cooked': '<p>chat text</p>',
    },
  ],
  'meta': {
    'status': 'pending',
    'total_rows_reviewables': more ? 14 : 4,
    'reviewable_types': [
      'ReviewableFlaggedPost',
      'ReviewableQueuedPost',
      'ReviewableUser',
      'ReviewablePost',
      'Chat::ReviewableMessage',
    ],
    'reviewable_count': 4,
    'unseen_reviewable_count': 1,
    'load_more_reviewables': ?(more
        ? '/review?offset=10&status=pending'
        : null),
  },
  'users': [
    {'id': 3, 'username': 'flagger', 'avatar_template': '/a/{size}/3.png'},
    {'id': 12, 'username': 'spammer', 'trust_level': 0},
    {'id': 14, 'username': 'newbie'},
  ],
  'topics': [
    {'id': 45, 'title': 'Dock lines', 'fancy_title': 'Dock lines'},
  ],
  'score_types': [
    {'id': 8, 'title': 'Spam', 'type': 'spam', 'icon': 'flag'},
    {'id': 4, 'title': 'Inappropriate', 'type': 'inappropriate'},
    {'id': 9, 'title': 'Needs approval', 'type': 'needs_approval'},
  ],
  'reviewable_scores': [
    {
      'id': 501,
      'score': 5.0,
      'status': 0,
      'created_at': '2026-11-10T09:00:00.000Z',
      'user_id': 3,
      'score_type_id': 8,
    },
    {'id': 502, 'score': 4.0, 'status': 1, 'user_id': 14, 'score_type_id': 4},
    {
      'id': 503,
      'status': 0,
      'score_type_id': 9,
      'reason': '<p>New users need approval</p>',
    },
  ],
  'bundled_actions': [
    {
      'id': '77-agree',
      'icon': 'thumbs-up',
      'label': 'Yes',
      'action_ids': [
        '77-post-agree_and_keep',
        '77-post-delete_and_agree',
        '77-post-agree_and_suspend',
        '77-post-agree_and_edit',
        '77-post-delete_user',
      ],
    },
    {
      'id': '77-disagree',
      'label': 'No',
      'action_ids': ['77-post-disagree'],
    },
    {
      'id': '78-approve_post',
      'action_ids': ['78-approve_post'],
    },
    {
      'id': '78-reject',
      'label': 'Reject',
      'action_ids': ['78-reject_post', '78-revise_and_reject_post'],
    },
    {
      'id': '79-approve_user',
      'action_ids': ['79-user-approve_user'],
    },
    {
      'id': '79-reject_user',
      'label': 'Delete user',
      'action_ids': ['79-user-delete_user'],
    },
  ],
  'actions': [
    {
      'id': '77-post-agree_and_keep',
      'action_name': 'post-agree_and_keep',
      'server_action': 'agree_and_keep',
      'label': 'Keep post',
      'description': 'Agree with the flag and keep the post.',
      'completed_message': 'Flag agreed.',
    },
    {
      'id': '77-post-delete_and_agree',
      'server_action': 'delete_and_agree',
      'label': 'Delete post',
      'dsa_classification_required': true,
    },
    {
      'id': '77-post-agree_and_suspend',
      'server_action': 'agree_and_suspend',
      'label': 'Suspend user',
      'client_action': 'suspend',
    },
    {
      'id': '77-post-agree_and_edit',
      'server_action': 'agree_and_edit',
      'label': 'Edit post',
      'client_action': 'edit',
    },
    {
      'id': '77-post-delete_user',
      'server_action': 'delete_user',
      'label': 'Delete user',
      'confirm_message': 'Are you sure you want to delete @spammer?',
      'confirm_destructive': true,
    },
    {'id': '77-post-disagree', 'server_action': 'disagree', 'label': 'No'},
    {
      'id': '78-approve_post',
      'server_action': 'approve_post',
      'label': 'Approve',
    },
    {'id': '78-reject_post', 'server_action': 'reject_post', 'label': 'Reject'},
    {
      'id': '78-revise_and_reject_post',
      'server_action': 'revise_and_reject_post',
      'label': 'Revise',
    },
    {
      'id': '79-user-approve_user',
      'server_action': 'approve_user',
      'label': 'Approve',
    },
    {
      'id': '79-user-delete_user',
      'server_action': 'delete_user',
      'label': 'Delete user',
      'require_reject_reason': true,
    },
  ],
  '__rest_serializer': '1',
};

/// `GET /review/<id>.json`: the same records, with the row under
/// `reviewable`.
Map<String, dynamic> reviewDetailFixture(int id, {int? version}) {
  final list = reviewListFixture();
  final row = Map<String, dynamic>.from(
    (list['reviewables'] as List).cast<Map<String, dynamic>>().firstWhere(
      (row) => row['id'] == id,
    ),
  );
  if (version != null) row['version'] = version;
  return {
    ...list..remove('reviewables'),
    'reviewable': row,
    'meta': {'types': <String, dynamic>{}},
  };
}

/// `PUT /review/<id>/perform/<action>` on success.
Map<String, dynamic> reviewPerformFixture(
  int id, {
  int version = 3,
  bool stillPending = false,
  Map<int, int> updates = const {},
}) => {
  'reviewable_perform_result': {
    'success': true,
    'remove_reviewable_ids': stillPending ? <int>[] : [id],
    if (updates.isNotEmpty)
      'reviewable_updates': {
        for (final entry in updates.entries)
          '${entry.key}': {'status': entry.value},
      },
    'version': version,
    'reviewable_count': 3,
    'unseen_reviewable_count': 0,
  },
};
