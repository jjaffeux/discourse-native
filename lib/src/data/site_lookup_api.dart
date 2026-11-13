import '../models/discourse_instance.dart';
import '../models/site_basic_info.dart';
import 'http_basic_auth.dart';

abstract interface class SiteLookupApi {
  Future<DiscourseInstance> lookup(
    String term, {
    HttpBasicAuthentication? authentication,
  });

  Future<SiteBasicInfo> basicInfo(String siteUrl);
}
