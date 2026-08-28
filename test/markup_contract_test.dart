import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/markup_contract.dart';

void main() {
  test('discovers core and owner-local markup contracts', () async {
    final contracts = await loadMarkupContracts();

    expect(contracts, isNotEmpty);
    expect(contracts.map((contract) => contract.name), contains('core-onebox'));
    expect(
      contracts.where((contract) => !contract.name.startsWith('core-')),
      isNotEmpty,
    );
    for (final contract in contracts) {
      expect(
        contract.catalog,
        contract.name.startsWith('core-')
            ? startsWith('tool/markup_contracts/')
            : matches(
                RegExp(r'^lib/src/plugins/[^/]+/tool/markup_contract\.json$'),
              ),
        reason: contract.name,
      );
    }
  });

  test('each owner catalog carries exactly its declared snapshots', () async {
    for (final contract in await loadMarkupContracts()) {
      final snapshotEntities = await Directory(
        contract.snapshot,
      ).list(followLinks: false).toList();
      final snapshotFiles = snapshotEntities
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .toSet();
      final declaredFiles = {
        for (final path in contract.watched) path.replaceAll('/', '__'),
      };

      expect(snapshotFiles, declaredFiles, reason: contract.name);
    }
  });

  test('core pins the generic lightbox consumer contract', () async {
    final core = (await loadMarkupContracts()).singleWhere(
      (contract) => contract.name == 'core-onebox',
    );

    expect(core.watched, contains('frontend/discourse/app/lib/lightbox.js'));
    expect(
      core.watched,
      isNot(contains(predicate<String>((path) => path.startsWith('plugins/')))),
    );
  });

  test('rejects snapshot paths which resolve outside the repository', () async {
    final repository = await Directory.systemTemp.createTemp(
      'markup-contract-repository-',
    );
    final outside = await Directory.systemTemp.createTemp(
      'markup-contract-outside-',
    );
    addTearDown(() => repository.delete(recursive: true));
    addTearDown(() => outside.delete(recursive: true));
    final catalog = File(
      '${repository.path}/tool/markup_contracts/core/markup_contract.json',
    );
    await catalog.parent.create(recursive: true);
    await Link(
      '${catalog.parent.path}/escaped',
    ).create(outside.path, recursive: true);
    await catalog.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'contracts': [
          {
            'name': 'escaped',
            'snapshot': 'escaped',
            'readers': 'reader.dart',
            'watched': ['upstream.dart'],
          },
        ],
      }),
    );

    expect(loadMarkupContracts(repository: repository), throwsFormatException);
  });

  test('rejects watched paths which flatten to one snapshot', () async {
    final repository = await Directory.systemTemp.createTemp(
      'markup-contract-collision-',
    );
    addTearDown(() => repository.delete(recursive: true));
    final catalog = File(
      '${repository.path}/tool/markup_contracts/core/markup_contract.json',
    );
    await catalog.parent.create(recursive: true);
    await catalog.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'contracts': [
          {
            'name': 'collision',
            'snapshot': 'snapshot',
            'readers': 'reader.dart',
            'watched': ['a/b__c', 'a__b/c'],
          },
        ],
      }),
    );

    expect(loadMarkupContracts(repository: repository), throwsFormatException);
  });
}
