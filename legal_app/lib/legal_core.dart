import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String chairmanRole = 'chairman';

final class AccessPolicy {
  const AccessPolicy();

  bool hasFullAccess({required String role, required bool subscriptionActive}) {
    if (role.trim().toLowerCase() == chairmanRole) {
      return true;
    }
    return subscriptionActive;
  }

  String accessLabel({required String role, required bool subscriptionActive}) {
    if (role.trim().toLowerCase() == chairmanRole) {
      return 'CHAIRMAN • PERMANENT FREE ACCESS';
    }
    return subscriptionActive ? 'ACTIVE SUBSCRIPTION' : 'SUBSCRIPTION REQUIRED';
  }
}

final class LegalDirector {
  const LegalDirector({
    required this.code,
    required this.title,
    required this.mission,
  });

  final String code;
  final String title;
  final String mission;
}

const List<LegalDirector> legalDirectors = <LegalDirector>[
  LegalDirector(
    code: 'LEGAL_CPO',
    title: 'Chief Legal Strategist',
    mission: 'Defines the case objective, legal posture, decision tree, and acceptance criteria.',
  ),
  LegalDirector(
    code: 'LEGAL_ARCH',
    title: 'Lead Jurisdictional Architect',
    mission: 'Maps jurisdiction, controlling authority, procedural rules, and entity hierarchy.',
  ),
  LegalDirector(
    code: 'LEGAL_COUNSEL',
    title: 'Lead Trial & Drafting Counsel',
    mission: 'Builds arguments, pleadings, motions, contracts, letters, briefs, and hearing strategy.',
  ),
  LegalDirector(
    code: 'LEGAL_INVESTIGATOR',
    title: 'Principal Evidentiary Analyst',
    mission: 'Builds evidence trails, discovery plans, chronology, witnesses, exhibits, and contradictions.',
  ),
  LegalDirector(
    code: 'LEGAL_QA',
    title: 'Director of Statutory Auditing',
    mission: 'Validates citations, elements, deadlines, procedural compliance, and adverse-risk gaps.',
  ),
];

final class BoardMember {
  const BoardMember({
    required this.name,
    required this.seat,
    required this.focus,
    required this.isHuman,
  });

  final String name;
  final String seat;
  final String focus;
  final bool isHuman;
}

const List<BoardMember> enterpriseBoard = <BoardMember>[
  BoardMember(
    name: 'Jerome Office',
    seat: 'Chairman',
    focus: 'Final authority, ownership, strategy, approvals, and enterprise direction.',
    isHuman: true,
  ),
  BoardMember(
    name: 'Aegis',
    seat: 'AI Governance Director',
    focus: 'Enterprise governance, risk controls, board process, and escalation policy.',
    isHuman: false,
  ),
  BoardMember(
    name: 'Lex',
    seat: 'AI Legal Operations Director',
    focus: 'Matter routing, legal workflow throughput, deadlines, and operating standards.',
    isHuman: false,
  ),
  BoardMember(
    name: 'Veritas',
    seat: 'AI Evidence & Integrity Director',
    focus: 'Evidence quality, provenance, contradictions, and factual integrity.',
    isHuman: false,
  ),
  BoardMember(
    name: 'Atlas',
    seat: 'AI Strategy & Growth Director',
    focus: 'Growth, market positioning, service design, and strategic partnerships.',
    isHuman: false,
  ),
  BoardMember(
    name: 'Sentinel',
    seat: 'AI Security & Compliance Director',
    focus: 'Security posture, privacy, access control, regulatory and operational compliance.',
    isHuman: false,
  ),
  BoardMember(
    name: 'Meridian',
    seat: 'AI Finance & Revenue Director',
    focus: 'Pricing, unit economics, revenue architecture, cash controls, and profitability.',
    isHuman: false,
  ),
];

final class LegalMatter {
  const LegalMatter({
    required this.id,
    required this.title,
    required this.summary,
    required this.jurisdiction,
    required this.status,
    required this.createdAt,
    required this.directorCodes,
  });

  final String id;
  final String title;
  final String summary;
  final String jurisdiction;
  final String status;
  final DateTime createdAt;
  final List<String> directorCodes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'summary': summary,
        'jurisdiction': jurisdiction,
        'status': status,
        'created_at': createdAt.toUtc().toIso8601String(),
        'director_codes': directorCodes,
      };

  static LegalMatter fromJson(Map<String, dynamic> json) {
    return LegalMatter(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled matter',
      summary: json['summary'] as String? ?? '',
      jurisdiction: json['jurisdiction'] as String? ?? 'Not specified',
      status: json['status'] as String? ?? 'Open',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      directorCodes: (json['director_codes'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

final class LegalRouter {
  const LegalRouter();

  List<LegalDirector> route(String text) {
    final String value = text.toLowerCase();
    final Set<String> selected = <String>{'LEGAL_CPO', 'LEGAL_QA'};

    if (_containsAny(value, <String>['court', 'county', 'state', 'federal', 'jurisdiction', 'venue', 'statute', 'code', 'rule'])) {
      selected.add('LEGAL_ARCH');
    }
    if (_containsAny(value, <String>['motion', 'brief', 'contract', 'agreement', 'letter', 'complaint', 'answer', 'petition', 'hearing', 'trial'])) {
      selected.add('LEGAL_COUNSEL');
    }
    if (_containsAny(value, <String>['evidence', 'video', 'photo', 'witness', 'discovery', 'record', 'timeline', 'police report', 'document'])) {
      selected.add('LEGAL_INVESTIGATOR');
    }

    return legalDirectors.where((LegalDirector director) => selected.contains(director.code)).toList(growable: false);
  }

  bool _containsAny(String source, List<String> needles) => needles.any(source.contains);

  String buildDirectorBrief({
    required String matterTitle,
    required String summary,
    required String jurisdiction,
    required List<LegalDirector> directors,
  }) {
    final String team = directors.map((LegalDirector d) => '${d.code} — ${d.title}').join('\n');
    return '''JARVIS LEGAL ENTERPRISE — DIRECTOR BRIEF\n\nMatter: $matterTitle\nJurisdiction: $jurisdiction\n\nIssue:\n$summary\n\nAssigned command team:\n$team\n\nOperating sequence:\n1. Define objective, posture, deadlines, and decision criteria.\n2. Confirm jurisdiction and controlling procedural/substantive authority.\n3. Build factual chronology and evidence matrix.\n4. Draft required instrument or action plan.\n5. Audit citations, elements, deadlines, service, filing, and adverse-risk gaps.\n\nAttorney review is required before relying on generated work as legal advice or filing it with a court.''';
  }
}

final class LegalMatterStore {
  LegalMatterStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'jarvis_legal_matters_v1';
  final FlutterSecureStorage _storage;

  Future<List<LegalMatter>> load() async {
    final String? raw = await _storage.read(key: _key);
    if (raw == null || raw.trim().isEmpty) {
      return <LegalMatter>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return <LegalMatter>[];
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(LegalMatter.fromJson)
          .toList(growable: false);
    } on Object {
      return <LegalMatter>[];
    }
  }

  Future<void> save(List<LegalMatter> matters) async {
    final String raw = jsonEncode(matters.map((LegalMatter matter) => matter.toJson()).toList());
    await _storage.write(key: _key, value: raw);
  }
}
