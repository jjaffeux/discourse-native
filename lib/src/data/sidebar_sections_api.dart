import '../models/sidebar.dart';

abstract interface class SidebarSectionsApi {
  Future<List<SidebarSection>> customSidebarSections({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  });

  Future<SidebarSection> reorderSidebarLinks({
    required String siteUrl,
    required String apiKey,
    required int sectionId,
    required List<int> linksOrder,
    String? clientId,
  });

  Future<List<SidebarSection>> moveSidebarLink({
    required String siteUrl,
    required String apiKey,
    required int sourceSectionId,
    required int targetSectionId,
    required int linkId,
    required int position,
    String? clientId,
  });
}
