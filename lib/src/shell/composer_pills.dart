import '../models/found_hashtag.dart';

typedef ComposerPills = ({
  FoundHashtag? Function(String ref) hashtag,

  bool? Function(String username) mention,

  void Function(Set<String> refs, Set<String> usernames) resolve,
});
