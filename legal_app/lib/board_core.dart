import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'legal_core.dart';

enum DirectivePriority { normal, high, critical }

enum DirectiveStatus { active, completed, cancelled }

final class ChairmanDirective {
  const ChairmanDirective({
    required this.id,
    required this.title,
    required this.instruction,
    required this.createdAt,
    this.priority = DirectivePriority.normal,
    this.status = DirectiveStatus.active,
  });

  final String id;
  final String title;
  final String instruction;
  final DateTime createdAt;
  final DirectivePriority priority;
  final DirectiveStatus status;

  ChairmanDirective copyWith({
    DirectivePriority? priority,
    DirectiveStatus? status,
  }) {
    return ChairmanDirective(
      id: id,
      title: title,
      instruction: instruction,
      createdAt: createdAt,
      priority: priority ?? this.priority,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'instruction': instruction,
        'created_at': createdAt.toUtc().toIso8601String(),
        'priority': priority.name,
        'status': status.name,
      };

  static ChairmanDirective fromJson(Map<String, dynamic> json) {
    return ChairmanDirective(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled directive',
      instruction: json['instruction'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      priority: DirectivePriority.values.firstWhere(
        (DirectivePriority value) => value.name == json['priority'],
        orElse: () => DirectivePriority.normal,
      ),
      status: DirectiveStatus.values.firstWhere(
        (DirectiveStatus value) => value.name == json['status'],
        orElse: () => DirectiveStatus.active,
      ),
    );
  }
}

final class ChairmanDirectiveStore {
  ChairmanDirectiveStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'jarvis_chairman_directives_v1';
  final FlutterSecureStorage _storage;

  Future<List<ChairmanDirective>> load() async {
    final String? raw = await _storage.read(key: _key);
    if (raw == null || raw.trim().isEmpty) return <ChairmanDirective>[];

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return <ChairmanDirective>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ChairmanDirective.fromJson)
          .toList(growable: false);
    } on Object {
      return <ChairmanDirective>[];
    }
  }

  Future<void> save(List<ChairmanDirective> directives) async {
    final String raw = jsonEncode(
      directives
          .map((ChairmanDirective directive) => directive.toJson())
          .toList(growable: false),
    );
    await _storage.write(key: _key, value: raw);
  }
}

final class BoardBrief {
  const BoardBrief({
    required this.generatedAt,
    required this.executiveSummary,
    required this.legalOperations,
    required this.governanceRisk,
    required this.evidenceIntegrity,
    required this.growthStrategy,
    required this.securityCompliance,
    required this.financeRevenue,
    required this.chairmanActions,
  });

  final DateTime generatedAt;
  final String executiveSummary;
  final String legalOperations;
  final String governanceRisk;
  final String evidenceIntegrity;
  final String growthStrategy;
  final String securityCompliance;
  final String financeRevenue;
  final List<String> chairmanActions;

  String toPrompt() {
    final String actions = chairmanActions
        .asMap()
        .entries
        .map((MapEntry<int, String> entry) =>
            '${entry.key + 1}. ${entry.value}')
        .join('\n');

    return '''JARVIS LEGAL ENTERPRISE — BOARD BRIEFING\nGenerated: ${generatedAt.toLocal()}\n\nEXECUTIVE SUMMARY\n$executiveSummary\n\nAEGIS — GOVERNANCE & RISK\n$governanceRisk\n\nLEX — LEGAL OPERATIONS\n$legalOperations\n\nVERITAS — EVIDENCE & INTEGRITY\n$evidenceIntegrity\n\nATLAS — STRATEGY & GROWTH\n$growthStrategy\n\nSENTINEL — SECURITY & COMPLIANCE\n$securityCompliance\n\nMERIDIAN — FINANCE & REVENUE\n$financeRevenue\n\nCHAIRMAN ACTION QUEUE\n$actions''';
  }
}

final class BoardBriefingEngine {
  const BoardBriefingEngine();

  BoardBrief build({
    required List<LegalMatter> matters,
    required List<ChairmanDirective> directives,
    DateTime? now,
  }) {
    final DateTime generatedAt = now ?? DateTime.now();
    final List<LegalMatter> openMatters = matters
        .where((LegalMatter matter) => matter.status.toLowerCase() == 'open')
        .toList(growable: false);
    final List<ChairmanDirective> activeDirectives = directives
        .where((ChairmanDirective directive) =>
            directive.status == DirectiveStatus.active)
        .toList(growable: false);
    final List<ChairmanDirective> criticalDirectives = activeDirectives
        .where((ChairmanDirective directive) =>
            directive.priority == DirectivePriority.critical)
        .toList(growable: false);

    final Set<String> jurisdictions = openMatters
        .map((LegalMatter matter) => matter.jurisdiction.trim())
        .where((String value) => value.isNotEmpty)
        .toSet();

    final int evidenceHeavy = openMatters
        .where(
          (LegalMatter matter) =>
              matter.directorCodes.contains('LEGAL_INVESTIGATOR'),
        )
        .length;
    final int draftingHeavy = openMatters
        .where(
          (LegalMatter matter) => matter.directorCodes.contains('LEGAL_COUNSEL'),
        )
        .length;
    final int jurisdictionHeavy = openMatters
        .where(
          (LegalMatter matter) => matter.directorCodes.contains('LEGAL_ARCH'),
        )
        .length;

    final String executiveSummary = openMatters.isEmpty
        ? 'No open legal matters are currently recorded. The enterprise is in standby posture with ${activeDirectives.length} active Chairman directive(s).'
        : '${openMatters.length} open legal matter(s) are active across ${jurisdictions.isEmpty ? 0 : jurisdictions.length} jurisdiction(s), with ${activeDirectives.length} active Chairman directive(s).';

    final String legalOperations = openMatters.isEmpty
        ? 'Matter queue is clear. Intake, routing, and drafting capacity are available.'
        : 'Open matter load: ${openMatters.length}. Drafting-intensive matters: $draftingHeavy. Jurisdiction-intensive matters: $jurisdictionHeavy. Maintain director routing and verify deadlines before execution.';

    final String governanceRisk = criticalDirectives.isEmpty
        ? 'No critical Chairman directive is currently flagged. Preserve final-approval authority with the Chairman for filings, commitments, publication, and financial actions.'
        : '${criticalDirectives.length} critical Chairman directive(s) require priority governance attention. Escalate conflicting actions or irreversible commitments before execution.';

    final String evidenceIntegrity = evidenceHeavy == 0
        ? 'No matter is currently tagged for elevated evidentiary handling. Continue preserving source provenance for all uploaded records.'
        : '$evidenceHeavy matter(s) require evidence/investigation support. Preserve originals, chronology, source identity, and contradiction tracking before relying on evidence.';

    final String growthStrategy = openMatters.isEmpty
        ? 'Capacity is available for client acquisition, service packaging, and commercial workflow testing without disrupting the legal matter queue.'
        : 'Growth activity should remain subordinate to matter deadlines. Productize repeatable intake, research, document preparation, and status-report workflows without representing automated output as licensed legal representation.';

    final String securityCompliance =
        'Chairman data remains local-first. Keep API secrets out of the mobile client, preserve least-privilege access, and require secure backend authorization for remote or multi-user operations.';

    final String financeRevenue =
        'Chairman access remains permanently subscription-exempt. Customer/client monetization should be enforced server-side so billing state cannot override Chairman ownership access.';

    final List<String> actions = <String>[];
    if (criticalDirectives.isNotEmpty) {
      actions.add('Review ${criticalDirectives.length} critical Chairman directive(s).');
    }
    if (openMatters.isNotEmpty) {
      actions.add('Review the ${openMatters.length} open matter(s) for deadlines, required filings, and next actions.');
    }
    if (evidenceHeavy > 0) {
      actions.add('Audit evidence provenance and chronology for $evidenceHeavy evidence-intensive matter(s).');
    }
    if (draftingHeavy > 0) {
      actions.add('Review draft-ready work for $draftingHeavy matter(s) before external use or filing.');
    }
    if (actions.isEmpty) {
      actions.add('No urgent legal action is recorded; maintain readiness and review new intake.');
    }
    actions.add('Preserve Chairman final approval for external legal, financial, and publishing actions.');

    return BoardBrief(
      generatedAt: generatedAt,
      executiveSummary: executiveSummary,
      legalOperations: legalOperations,
      governanceRisk: governanceRisk,
      evidenceIntegrity: evidenceIntegrity,
      growthStrategy: growthStrategy,
      securityCompliance: securityCompliance,
      financeRevenue: financeRevenue,
      chairmanActions: actions,
    );
  }
}
