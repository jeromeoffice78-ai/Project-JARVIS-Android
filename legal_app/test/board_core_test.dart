import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_legal_enterprise/board_core.dart';
import 'package:jarvis_legal_enterprise/legal_core.dart';

void main() {
  group('BoardBriefingEngine', () {
    const BoardBriefingEngine engine = BoardBriefingEngine();

    test('builds standby briefing with no matters', () {
      final BoardBrief brief = engine.build(
        matters: const <LegalMatter>[],
        directives: const <ChairmanDirective>[],
        now: DateTime.utc(2026, 9, 3, 12),
      );

      expect(brief.executiveSummary, contains('No open legal matters'));
      expect(brief.financeRevenue, contains('subscription-exempt'));
      expect(brief.chairmanActions, isNotEmpty);
    });

    test('escalates critical directives and evidence matters', () {
      final LegalMatter matter = LegalMatter(
        id: 'matter-1',
        title: 'Evidence review',
        summary: 'Review police report and video evidence.',
        jurisdiction: 'Georgia',
        status: 'Open',
        createdAt: DateTime.utc(2026, 9, 3),
        directorCodes: const <String>[
          'LEGAL_CPO',
          'LEGAL_INVESTIGATOR',
          'LEGAL_QA',
        ],
      );
      final ChairmanDirective directive = ChairmanDirective(
        id: 'directive-1',
        title: 'Priority review',
        instruction: 'Escalate evidence review.',
        createdAt: DateTime.utc(2026, 9, 3),
        priority: DirectivePriority.critical,
      );

      final BoardBrief brief = engine.build(
        matters: <LegalMatter>[matter],
        directives: <ChairmanDirective>[directive],
        now: DateTime.utc(2026, 9, 3, 12),
      );

      expect(brief.executiveSummary, contains('1 open legal matter'));
      expect(brief.governanceRisk, contains('1 critical Chairman directive'));
      expect(brief.evidenceIntegrity, contains('1 matter(s) require evidence'));
      expect(
        brief.chairmanActions.join(' '),
        contains('critical Chairman directive'),
      );
    });
  });

  group('ChairmanDirective', () {
    test('round-trips through JSON', () {
      final ChairmanDirective original = ChairmanDirective(
        id: 'd1',
        title: 'Approve filing',
        instruction: 'Review before filing.',
        createdAt: DateTime.utc(2026, 9, 3, 10),
        priority: DirectivePriority.high,
        status: DirectiveStatus.active,
      );

      final ChairmanDirective decoded =
          ChairmanDirective.fromJson(original.toJson());

      expect(decoded.id, original.id);
      expect(decoded.priority, DirectivePriority.high);
      expect(decoded.status, DirectiveStatus.active);
      expect(decoded.instruction, original.instruction);
    });
  });
}
