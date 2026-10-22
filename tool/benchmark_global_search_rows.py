#!/usr/bin/env python3
"""Count preparation in real GlobalSearchPanel interactions. Run in the validation lane."""
from pathlib import Path
import argparse
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
parser.add_argument('--revision', help='Read panel and fixture from this Git revision')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source=root/'lib/src/shell/global_search_panel.dart'
test=root/'test/global_search_panel_test.dart'
saved_source = source.read_text()
saved_test = test.read_text()
try:
    original_source = saved_source
    original_test = saved_test
    if args.revision:
        original_source = subprocess.check_output(['git', 'show', f'{args.revision}:lib/src/shell/global_search_panel.dart'], cwd=root, text=True)
        original_test = subprocess.check_output(['git', 'show', f'{args.revision}:test/global_search_panel_test.dart'], cwd=root, text=True)
    assert 'Widget _result(GlobalSearchResult result) {' in original_source or 'Widget _result(_PreparedSearchResult row) {' in original_source, 'Unknown row factory'
    s=original_source.replace('final RegExp _whitespace', 'final globalSearchPreparationCounts = <String, int>{};\nvoid countSearchPreparation(String name) => globalSearchPreparationCounts.update(name, (n) => n + 1, ifAbsent: () => 1);\n\nfinal RegExp _whitespace')
    s=s.replace('Widget _result(GlobalSearchResult result) {', "Widget _result(GlobalSearchResult result) {\n    countSearchPreparation('rowFactory');\n    countSearchPreparation('openCallback');")
    s=s.replace('Widget _result(_PreparedSearchResult row) {', "Widget _result(_PreparedSearchResult row) {\n    countSearchPreparation('rowFactory');")
    s=s.replace('open: () => widget.onOpen(result),', "open: (() { countSearchPreparation('openCallback'); return () => widget.onOpen(result); })(),")
    source.write_text(s)
    extra=r'''
class _PagedPreparationApi extends _PanelApi {
  _PagedPreparationApi(this.pages);
  final int pages;
  @override
  Future<GlobalSearchPage> search({required String siteUrl, required String? apiKey, String? clientId, required GlobalSearchRequest request, Future<void>? abortTrigger, void Function(List<GlobalSearchSection>)? onProgress}) async {
    return GlobalSearchPage(sections: [GlobalSearchSection(scope: GlobalSearchScope.forum, results: List.generate(30, (i) { final n=request.offset+i; return GlobalSearchResult(id:'prepared-$n', scope:GlobalSearchScope.forum,title:'Prepared result $n', path:'/t/prepared/${n+1}', excerpt:'A wrapped search result excerpt for row $n.'); }))], hasMore:request.offset+30<pages*30, consumedCount:30);
  }
}
'''
    case=r'''
  for (final repetition in [1, 2, 3, 4, 5]) {
  for (final pages in [1, 30]) {
    testWidgets('preparation measurement $pages pages run $repetition', (tester) async {
      final opened=<GlobalSearchResult>[];
      final c=await _pump(tester, api:_PagedPreparationApi(pages), onOpen:opened.add, height:300);
      globalSearchPreparationCounts.clear();
      c.setScope(GlobalSearchScope.forum);
      c.setQuery('prepared');
      await tester.pumpAndSettle();
      for(var p=1;p<pages;p++){c.loadMore();await tester.pumpAndSettle();}
      expect(c.results.length,pages*30);
      final state=tester.state<GlobalSearchPanelState>(find.byType(GlobalSearchPanel));
      final arrivalCounts=Map<String,int>.of(globalSearchPreparationCounts);
      globalSearchPreparationCounts.clear();
      for(var k=0;k<10;k++){expect(state.handleKey(LogicalKeyboardKey.arrowDown),isTrue);await tester.pumpAndSettle();}
      final counts=Map<String,int>.of(globalSearchPreparationCounts);
      final mounted=find.byWidgetPredicate((w)=>w is DItem && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('global-search-result-')).evaluate().length;
      expect(mounted,lessThan(c.results.length));
      expect(state.handleKey(LogicalKeyboardKey.enter),isTrue);
      expect(opened.single.id,'prepared-9');
      expect(tester.takeException(),isNull);
      debugPrint('PREPARATION ${pages*30} run=$repetition arrivals=$arrivalCounts selection=$counts mounted=$mounted errors=0');
      state.resetSelection();
      expect(state.handleKey(LogicalKeyboardKey.arrowUp),isTrue);
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((w)=>w is DItem && w.selected).hitTestable(),findsOneWidget);
      expect(state.handleKey(LogicalKeyboardKey.enter),isTrue);
      expect(opened.last.id,'prepared-${pages*30-1}');
      expect(tester.takeException(),isNull);
      debugPrint('REVEAL ${pages*30} run=$repetition selectionAndReveal=$globalSearchPreparationCounts');
    });
  }
  }
'''
    test.write_text(original_test.replace('void main() {','void main() {\n'+case,1)+extra)
    cmd=['flutter','test','--no-pub','test/global_search_panel_test.dart','--plain-name','preparation measurement','--reporter','expanded']
    r=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,cwd=root)
    print(r.stdout)
    args.output.write_text(r.stdout)
    sys.exit(r.returncode)
finally:
    source.write_text(saved_source)
    test.write_text(saved_test)
