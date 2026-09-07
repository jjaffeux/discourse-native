// Wire fields and timestamps from the upstream acceptance fixture at
// discourse/discourse-prometheus-alert-receiver@bd31ece26c61fd8d293c9d4b50244254c59d6065.
Map<String, dynamic> alertJson({
  String status = 'firing',
  String datacenter = 'sjc1',
  String identifier = 'myalert',
  String? description,
}) => {
  'status': status,
  'identifier': identifier,
  'datacenter': datacenter,
  'description': description,
  'starts_at': '2020-07-27T17:26:49.526234411Z',
  'ends_at': status == 'resolved' ? '2020-07-27T17:35:35.870002386Z' : null,
  'external_url': 'https://alertmanager.example.com',
  'generator_url':
      'https://metrics.example.com/graph?g0.expr=mymetric&g0.tab=1',
  'link_url':
      'https://logs.example.com/app/kibana#/discover?_g=()&_a=(columns:!())',
};

Map<String, dynamic> alertTopicJson(List<Object?> alerts) => {
  'id': 7,
  'title': 'Database alerts',
  'details': {'can_create_post': true},
  'alert_data': alerts,
  'post_stream': {
    'stream': [10, 11],
    'posts': [
      {
        'id': 10,
        'topic_id': 7,
        'post_number': 1,
        'username': 'system',
        'cooked': '<p>Database runbook</p>',
      },
      {
        'id': 11,
        'topic_id': 7,
        'post_number': 2,
        'username': 'sam',
        'cooked': '<p>Investigating</p>',
      },
    ],
  },
};
