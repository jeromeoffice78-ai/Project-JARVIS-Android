import 'dart:async';

import 'package:flutter/material.dart';

import 'jarvis_legal_api.dart';
import 'legal_core.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisLegalEnterpriseApp());
}

class JarvisLegalEnterpriseApp extends StatelessWidget {
  const JarvisLegalEnterpriseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'JARVIS Legal Enterprise',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E5A66),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF071217),
      ),
      home: const ChairmanCommandCenter(),
    );
  }
}

class ChairmanCommandCenter extends StatefulWidget {
  const ChairmanCommandCenter({super.key});

  @override
  State<ChairmanCommandCenter> createState() => _ChairmanCommandCenterState();
}

class _ChairmanCommandCenterState extends State<ChairmanCommandCenter> {
  static const String _role = String.fromEnvironment(
    'JARVIS_ROLE',
    defaultValue: chairmanRole,
  );
  static const bool _subscriptionActive = bool.fromEnvironment(
    'JARVIS_SUBSCRIPTION_ACTIVE',
    defaultValue: false,
  );

  final AccessPolicy _policy = const AccessPolicy();
  final LegalRouter _router = const LegalRouter();
  final LegalMatterStore _store = LegalMatterStore();
  late final JarvisLegalApi _api;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _jurisdictionController =
      TextEditingController(text: 'Georgia');
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _aiController = TextEditingController();

  List<LegalMatter> _matters = <LegalMatter>[];
  List<LegalDirector> _assigned = legalDirectors;
  int _index = 0;
  bool _loading = true;
  bool _asking = false;
  String _directorBrief =
      'Create a matter or enter an issue to generate the five-director operating brief.';
  String _aiAnswer = 'JARVIS legal counsel channel ready.';

  bool get _hasAccess => _policy.hasFullAccess(
        role: _role,
        subscriptionActive: _subscriptionActive,
      );

  @override
  void initState() {
    super.initState();
    _api = JarvisLegalApi();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<LegalMatter> matters = await _store.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _matters = matters;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _api.close();
    _titleController.dispose();
    _jurisdictionController.dispose();
    _summaryController.dispose();
    _aiController.dispose();
    super.dispose();
  }

  Future<void> _createMatter() async {
    final String title = _titleController.text.trim();
    final String summary = _summaryController.text.trim();
    final String jurisdiction = _jurisdictionController.text.trim().isEmpty
        ? 'Not specified'
        : _jurisdictionController.text.trim();

    if (title.isEmpty || summary.isEmpty) {
      _message('Matter title and issue summary are required.');
      return;
    }

    final List<LegalDirector> routed =
        _router.route('$title $summary $jurisdiction');
    final LegalMatter matter = LegalMatter(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      summary: summary,
      jurisdiction: jurisdiction,
      status: 'Open',
      createdAt: DateTime.now(),
      directorCodes:
          routed.map((LegalDirector d) => d.code).toList(growable: false),
    );

    final List<LegalMatter> updated = <LegalMatter>[matter, ..._matters];
    await _store.save(updated);
    if (!mounted) {
      return;
    }

    setState(() {
      _matters = updated;
      _assigned = routed;
      _directorBrief = _router.buildDirectorBrief(
        matterTitle: title,
        summary: summary,
        jurisdiction: jurisdiction,
        directors: routed,
      );
      _aiController.text = _directorBrief;
      _titleController.clear();
      _summaryController.clear();
    });
    _message('Matter created and routed to ${routed.length} legal directors.');
  }

  Future<void> _deleteMatter(LegalMatter matter) async {
    final List<LegalMatter> updated = _matters
        .where((LegalMatter item) => item.id != matter.id)
        .toList(growable: false);
    await _store.save(updated);
    if (!mounted) {
      return;
    }
    setState(() => _matters = updated);
  }

  void _routePreview() {
    final String value = _summaryController.text.trim();
    if (value.isEmpty) {
      _message('Enter an issue summary first.');
      return;
    }
    final List<LegalDirector> routed = _router.route(value);
    setState(() {
      _assigned = routed;
      _directorBrief = _router.buildDirectorBrief(
        matterTitle: _titleController.text.trim().isEmpty
            ? 'New matter'
            : _titleController.text.trim(),
        summary: value,
        jurisdiction: _jurisdictionController.text.trim().isEmpty
            ? 'Not specified'
            : _jurisdictionController.text.trim(),
        directors: routed,
      );
      _aiController.text = _directorBrief;
    });
  }

  Future<void> _askJarvis() async {
    final String prompt = _aiController.text.trim();
    if (prompt.isEmpty || _asking) {
      return;
    }

    setState(() {
      _asking = true;
      _aiAnswer = 'JARVIS is processing the legal command...';
    });

    try {
      if (!_api.isConfigured) {
        setState(() {
          _aiAnswer =
              'Offline director synthesis:\n\n$prompt\n\nLive AI counsel will activate automatically when JARVIS_HTTP_BASE is configured in the GitHub build environment.';
        });
        return;
      }

      final String answer = await _api.ask(prompt: prompt, role: _role);
      if (!mounted) {
        return;
      }
      setState(() => _aiAnswer = answer);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _aiAnswer =
            'Live JARVIS connection unavailable. Your local Legal Enterprise remains active.\n\n$error';
      });
    } finally {
      if (mounted) {
        setState(() => _asking = false);
      }
    }
  }

  void _message(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return _AccessLockedPage(role: _role);
    }

    final List<Widget> pages = <Widget>[
      _buildCommandPage(),
      _buildMattersPage(),
      _buildBoardPage(),
      _buildAiPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('JARVIS LEGAL ENTERPRISE'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                avatar: const Icon(Icons.verified_user_rounded, size: 18),
                label: Text(
                  _policy.accessLabel(
                    role: _role,
                    subscriptionActive: _subscriptionActive,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.gavel_rounded),
            label: 'Command',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_copy_rounded),
            label: 'Matters',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_rounded),
            label: 'Board',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_alt_rounded),
            label: 'AI Counsel',
          ),
        ],
      ),
    );
  }

  Widget _buildCommandPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _chairmanCard(),
        const SizedBox(height: 16),
        Text('New Legal Matter', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Matter title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _jurisdictionController,
          decoration: const InputDecoration(
            labelText: 'Jurisdiction',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _summaryController,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'Issue summary / objective',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _createMatter,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Create & Route'),
            ),
            OutlinedButton.icon(
              onPressed: _routePreview,
              icon: const Icon(Icons.account_tree_rounded),
              label: const Text('Preview Team'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Assigned Directors', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ..._assigned.map(_directorTile),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(_directorBrief),
          ),
        ),
      ],
    );
  }

  Widget _chairmanCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            const CircleAvatar(
              radius: 28,
              child: Icon(Icons.chair_alt_rounded, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Jerome Office',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text('Chairman • Founder • Final Authority'),
                  const SizedBox(height: 5),
                  const Text('Owner access: $0.00 • No subscription required'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _directorTile(LegalDirector director) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_balance_rounded),
        title: Text(director.title),
        subtitle: Text('${director.code}\n${director.mission}'),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildMattersPage() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_matters.isEmpty) {
      return const Center(
        child: Text('No matters yet. Create the first matter from Command.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _matters.length,
      itemBuilder: (BuildContext context, int index) {
        final LegalMatter matter = _matters[index];
        return Card(
          child: ExpansionTile(
            leading: const Icon(Icons.folder_special_rounded),
            title: Text(matter.title),
            subtitle: Text('${matter.jurisdiction} • ${matter.status}'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(matter.summary),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Directors: ${matter.directorCodes.join(', ')}'),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() {
                        _aiController.text = _router.buildDirectorBrief(
                          matterTitle: matter.title,
                          summary: matter.summary,
                          jurisdiction: matter.jurisdiction,
                          directors: legalDirectors
                              .where(
                                (LegalDirector d) =>
                                    matter.directorCodes.contains(d.code),
                              )
                              .toList(growable: false),
                        );
                        _index = 3;
                      });
                    },
                    icon: const Icon(Icons.psychology_alt_rounded),
                    label: const Text('Open in AI Counsel'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Delete matter',
                    onPressed: () => unawaited(_deleteMatter(matter)),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBoardPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Seven-Member Board', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
          'Chairman retains final authority. AI board members are advisory decision-support agents.',
        ),
        const SizedBox(height: 14),
        ...enterpriseBoard.map(
          (BoardMember member) => Card(
            child: ListTile(
              leading: Icon(
                member.isHuman ? Icons.person_rounded : Icons.smart_toy_rounded,
              ),
              title: Text(member.name),
              subtitle: Text('${member.seat}\n${member.focus}'),
              isThreeLine: true,
              trailing: member.isHuman
                  ? const Chip(label: Text('CHAIRMAN'))
                  : const Chip(label: Text('AI')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('JARVIS Legal Counsel', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          _api.isConfigured
              ? 'Live backend configured.'
              : 'Offline-first mode. Live backend can be attached through GitHub environment variables.',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _aiController,
          minLines: 8,
          maxLines: 18,
          decoration: const InputDecoration(
            labelText: 'Legal command / director brief',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _asking ? null : () => unawaited(_askJarvis()),
          icon: _asking
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: const Text('Run JARVIS Legal Analysis'),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(_aiAnswer),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Legal safety: this system supports research, organization, drafting, and decision support. It does not create an attorney-client relationship and should not replace licensed counsel where representation or legal advice is required.',
        ),
      ],
    );
  }
}

class _AccessLockedPage extends StatelessWidget {
  const _AccessLockedPage({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.lock_rounded, size: 60),
              const SizedBox(height: 14),
              Text(
                'Subscription required',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text('Current role: $role'),
              const SizedBox(height: 8),
              const Text(
                'Chairman accounts are permanently exempt from subscription billing.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
