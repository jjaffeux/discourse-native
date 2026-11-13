import '../models/found_group.dart';
import '../models/found_hashtag.dart';
import '../models/search_results.dart';

const int maximumDiscourseSearchTermLength = 2048;
const int maximumDiscourseHashtagsPerRequest = 20;
const List<String> defaultDiscourseHashtagOrder = ['category', 'tag'];

abstract interface class ShellSearchApi {
  Future<SearchResults> searchPosts({
    required String siteUrl,
    required String term,
    String? typeFilter,
    int? topicId,
    bool searchForId = false,
    String? restrictToArchetype,
    String? apiKey,
    String? clientId,
  });

  Future<FoundUsersAndGroups> searchMentions({
    required String siteUrl,
    required String term,
    int? topicId,
    int limit = 7,
    String? apiKey,
    String? clientId,
  });

  Future<FoundUsersAndGroups> searchUsersAndGroups({
    required String siteUrl,
    required String term,
    int limit = 6,
    String? apiKey,
    String? clientId,
  });

  Future<List<FoundHashtag>> searchHashtags({
    required String siteUrl,
    required String term,
    List<String> order = defaultDiscourseHashtagOrder,
    String? apiKey,
    String? clientId,
  });

  Future<List<String>> recentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });
}
