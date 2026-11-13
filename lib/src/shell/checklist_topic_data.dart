import '../models/post.dart';

abstract interface class ChecklistTopicData {
  bool postWriting(int postId);
  void Function() holdPostWrite(int postId);
  bool publishChecklist(Post previous, Post next);
  Future<Post?> checklistPost(int topicId, int postId, String? apiKey);
}
