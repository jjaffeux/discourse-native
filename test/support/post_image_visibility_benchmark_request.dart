import 'package:discourse_native/src/data/site_image_repository.dart';

final class PostImageBenchmarkRequest {
  const PostImageBenchmarkRequest({
    required this.result,
    required this.release,
    required this.setVisible,
  });

  final Future<SiteImageBytes?> result;
  final void Function() release;
  final void Function(bool) setVisible;
}

PostImageBenchmarkRequest postImageBenchmarkRequest(
  SiteImageRepository repository, {
  required String siteUrl,
  required String url,
  required bool useLeases,
  required bool visible,
}) {
  if (!useLeases) {
    return PostImageBenchmarkRequest(
      result: repository.load(siteUrl: siteUrl, url: url),
      release: () {},
      setVisible: (_) {},
    );
  }
  final request = repository.request(siteUrl: siteUrl, url: url);
  request.setVisible(visible);
  return PostImageBenchmarkRequest(
    result: request.result,
    release: request.release,
    setVisible: request.setVisible,
  );
}
