// Names, handles and responses visible in the supplied participant screenshot.
const participantScreenshotRows = <Map<String, Object?>>[
  {
    'status': 'going',
    'user': {'name': 'pengguna1', 'username': 'Alfima'},
  },
  {
    'status': 'going',
    'user': {'name': 'AnneClaire', 'username': 'AnneClaire'},
  },
  {
    'status': 'going',
    'user': {'name': 'Angeline Yodo', 'username': 'ayodo'},
  },
  {
    'status': 'going',
    'user': {'name': 'Danielle Lloyd', 'username': 'Danielle'},
  },
  {
    'status': 'going',
    'user': {'name': 'Emily Roman', 'username': 'Emily_Roman'},
  },
  {
    'status': 'going',
    'user': {'name': 'Flavia Sasaki Siqueira', 'username': 'fsasaki'},
  },
];

String participantFixturePath({String filter = '', String? type}) => Uri(
  path: '/discourse-post-event/events/42/invitees.json',
  queryParameters: {'filter': filter, 'type': ?type},
).toString();
