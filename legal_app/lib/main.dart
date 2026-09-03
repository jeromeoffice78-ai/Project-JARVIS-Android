import 'dart:async';

import 'package:flutter/material.dart';

import 'jarvis_legal_api.dart';
import 'legal_core.dart';

const Color _bg = Color(0xFF05090D);
const Color _panel = Color(0xFF0A1218);
const Color _panel2 = Color(0xFF0E1B22);
const Color _cyan = Color(0xFF38E8FF);
const Color _gold = Color(0xFFFFC857);
const Color _green = Color(0xFF62E6A7);
const Color _muted = Color(0xFF91A6B2);
const Color _border = Color(0xFF183746);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisLegalEnterpriseApp());
}

class JarvisLegalEnterpriseApp extends StatelessWidget {
  const JarvisLegalEnterpriseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _cyan,
      brightness: Brightness.dark,
      surface: _panel,
    ).copyWith(
      primary: _cyan,
      secondary: _gold,
      tertiary: _green,
      surface: _panel,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'JARVIS Legal Enterprise',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: _bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF071016),
          indicatorColor: Color(0x2638E8FF),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _panel2,
          labelStyle: const TextStyle(color: _muted),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _cyan, width: 1.3),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        cardTheme: CardThemeData(
          color: _panel,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: _border),
          ),
        ),
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
      'Chairman command channel ready. Create a matter or enter an issue to activate the legal director team.';
  String _aiAnswer =
      'JARVIS Legal Counsel is standing by for Chairman instructions.';

  bool get _hasAccess => _policy.hasFullAccess(
        role: _role,
        subscriptionActive: _subscriptionActive,
      );

  int get _openMatterCount =>
      _matters.where((LegalMatter m) => m.status == 'Open').length;

  @override
  void initState() {
    super.initState();
    _api = JarvisLegalApi();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<LegalMatter> matters = await _store.load();
    if (!mounted) return;
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
    if (!mounted) return;

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
    _message('Matter routed to ${routed.length} Managing Legal Directors.');
  }

  Future<void> _deleteMatter(LegalMatter matter) async {
    final List<LegalMatter> updated = _matters
        .where((LegalMatter item) => item.id != matter.id)
        .toList(growable: false);
    await _store.save(updated);
    if (!mounted) return;
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
    if (prompt.isEmpty || _asking) return;

    setState(() {
      _asking = true;
      _aiAnswer = 'JARVIS is processing the Chairman legal command...';
    });

    try {
      if (!_api.isConfigured) {
        setState(() {
          _aiAnswer =
              'OFFLINE DIRECTOR SYNTHESIS\n\n$prompt\n\nThe Legal Enterprise is active locally. Live JARVIS analysis activates when the secure backend endpoint is configured.';
        });
        return;
      }

      final String answer = await _api.ask(prompt: prompt, role: _role);
      if (!mounted) return;
      setState(() => _aiAnswer = answer);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _aiAnswer =
            'Live JARVIS connection unavailable. Local Legal Enterprise operations remain active.\n\n$error';
      });
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _goTo(int page) => setState(() => _index = page);

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) return _AccessLockedPage(role: _role);

    final List<Widget> pages = <Widget>[
      _buildDashboardPage(),
      _buildMattersPage(),
      _buildTeamPage(),
      _buildBoardPage(),
      _buildAiPage(),
    ];

    return Scaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTo,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Command',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_copy_outlined),
            selectedIcon: Icon(Icons.folder_copy_rounded),
            label: 'Matters',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree_rounded),
            label: 'Team',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: 'Board',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_alt_outlined),
            selectedIcon: Icon(Icons.psychology_alt_rounded),
            label: 'Counsel',
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      titleSpacing: 16,
      title: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _cyan),
              color: const Color(0x1738E8FF),
            ),
            child: const Icon(Icons.balance_rounded, color: _cyan, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'JARVIS LEGAL ENTERPRISE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                Text(
                  'SUPREME COMMAND SYSTEM',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.5,
                    color: _cyan,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x1462E6A7),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x5562E6A7)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.verified_user_rounded, size: 15, color: _green),
                  SizedBox(width: 5),
                  Text(
                    'CHAIRMAN',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: _green,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: <Widget>[
        _heroCard(),
        const SizedBox(height: 14),
        _sectionTitle('ENTERPRISE STATUS', 'Live Chairman overview'),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _metricCard(
                icon: Icons.folder_open_rounded,
                value: '$_openMatterCount',
                label: 'Open Matters',
                accent: _cyan,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                icon: Icons.account_balance_rounded,
                value: '${legalDirectors.length}',
                label: 'Legal Directors',
                accent: _gold,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                icon: Icons.groups_rounded,
                value: '${enterpriseBoard.length}',
                label: 'Board Seats',
                accent: _green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _sectionTitle('CHAIRMAN ACTIONS', 'Direct enterprise control'),
        const SizedBox(height: 10),
        _actionGrid(),
        const SizedBox(height: 18),
        _sectionTitle('LEGAL INTAKE', 'Create and route a matter'),
        const SizedBox(height: 10),
        _intakeCard(),
        const SizedBox(height: 18),
        _sectionTitle('ACTIVE COMMAND TEAM', 'Five-director operating model'),
        const SizedBox(height: 10),
        ..._assigned.map(_compactDirectorTile),
        const SizedBox(height: 12),
        _briefCard(),
      ],
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF0D2731),
            Color(0xFF081219),
            Color(0xFF1D1710),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x6638E8FF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x2438E8FF),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x1538E8FF),
                  border: Border.all(color: _cyan, width: 1.4),
                ),
                child: const Icon(
                  Icons.chair_alt_rounded,
                  size: 32,
                  color: _cyan,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'CHAIRMAN SUPREME COMMAND CENTER',
                      style: TextStyle(
                        fontSize: 12,
                        color: _cyan,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Jerome Office',
                      style: TextStyle(
                        fontSize: 26,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Founder • Chairman • 100% Ownership • Final Authority',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x0F62E6A7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x4462E6A7)),
            ),
            child: const Row(
              children: <Widget>[
                Icon(Icons.lock_open_rounded, size: 20, color: _green),
                SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'OWNER ACCESS UNLOCKED',
                        style: TextStyle(
                          color: _green,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Permanent Chairman access • Owner access: \$0.00 • No subscription required',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String value,
    required String label,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, color: accent, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _actionGrid() {
    final List<_CommandAction> actions = <_CommandAction>[
      _CommandAction(
        icon: Icons.add_circle_outline_rounded,
        title: 'New Matter',
        subtitle: 'Open legal intake',
        onTap: () => _goTo(0),
      ),
      _CommandAction(
        icon: Icons.folder_special_outlined,
        title: 'Matter Vault',
        subtitle: 'Review secure files',
        onTap: () => _goTo(1),
      ),
      _CommandAction(
        icon: Icons.account_tree_rounded,
        title: 'Legal Team',
        subtitle: '5 director system',
        onTap: () => _goTo(2),
      ),
      _CommandAction(
        icon: Icons.groups_2_outlined,
        title: 'Board Room',
        subtitle: '7-member board',
        onTap: () => _goTo(3),
      ),
      _CommandAction(
        icon: Icons.psychology_alt_outlined,
        title: 'JARVIS Counsel',
        subtitle: 'Run legal analysis',
        onTap: () => _goTo(4),
      ),
      _CommandAction(
        icon: Icons.shield_outlined,
        title: 'Authority',
        subtitle: 'Chairman controls',
        onTap: () => _message('Chairman authority is active and subscription-exempt.'),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.55,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (BuildContext context, int index) {
        final _CommandAction action = actions[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: action.onTap,
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0x1438E8FF),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(action.icon, color: _cyan, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        action.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        action.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _intakeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Matter title',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _jurisdictionController,
              decoration: const InputDecoration(
                labelText: 'Jurisdiction',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _summaryController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Issue / objective / requested result',
                alignLabelWithHint: true,
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 72),
                  child: Icon(Icons.description_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _createMatter,
                    icon: const Icon(Icons.rocket_launch_rounded),
                    label: const Text('CREATE & ROUTE'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Preview director team',
                  onPressed: _routePreview,
                  icon: const Icon(Icons.account_tree_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactDirectorTile(LegalDirector director) {
    final bool active = _assigned.any((LegalDirector d) => d.code == director.code);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: active ? const Color(0x1026D9F1) : _panel,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: active ? const Color(0x6638E8FF) : _border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: active ? const Color(0x1F38E8FF) : _panel2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              active ? Icons.bolt_rounded : Icons.account_balance_outlined,
              color: active ? _cyan : _muted,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  director.title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  director.code,
                  style: TextStyle(
                    color: active ? _cyan : _muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
              ],
            ),
          ),
          Text(
            active ? 'ACTIVE' : 'STANDBY',
            style: TextStyle(
              color: active ? _green : _muted,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _briefCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF071219),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x4438E8FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.terminal_rounded, color: _cyan, size: 18),
              SizedBox(width: 8),
              Text(
                'DIRECTOR OPERATING BRIEF',
                style: TextStyle(
                  fontSize: 11,
                  color: _cyan,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            _directorBrief,
            style: const TextStyle(fontSize: 11.5, height: 1.45, color: Color(0xFFD0DEE5)),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                _aiController.text = _directorBrief;
                _goTo(4);
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 17),
              label: const Text('SEND TO COUNSEL'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMattersPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: <Widget>[
        _pageHeader(
          icon: Icons.folder_special_rounded,
          title: 'SECURE MATTER VAULT',
          subtitle: 'Chairman-controlled legal matter storage',
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_matters.isEmpty)
          _emptyState(
            icon: Icons.folder_open_outlined,
            title: 'No legal matters yet',
            subtitle: 'Create the first matter from the Command screen.',
            button: 'OPEN COMMAND',
            onPressed: () => _goTo(0),
          )
        else
          ..._matters.map(_matterCard),
      ],
    );
  }

  Widget _matterCard(LegalMatter matter) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: _border),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0x1638E8FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.gavel_rounded, color: _cyan, size: 20),
        ),
        title: Text(
          matter.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${matter.jurisdiction} • ${matter.status}',
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: <Widget>[
          const Divider(color: _border),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(matter.summary, style: const TextStyle(height: 1.4)),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: matter.directorCodes
                  .map(
                    (String code) => _miniChip(code, _cyan),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () {
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
                    _goTo(4);
                  },
                  icon: const Icon(Icons.psychology_alt_rounded),
                  label: const Text('OPEN IN COUNSEL'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Delete matter',
                onPressed: () => unawaited(_deleteMatter(matter)),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTeamPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: <Widget>[
        _pageHeader(
          icon: Icons.account_tree_rounded,
          title: 'MANAGING LEGAL DIRECTORS',
          subtitle: 'Five-director autonomous legal operating system',
        ),
        const SizedBox(height: 14),
        ...legalDirectors.asMap().entries.map(
          (MapEntry<int, LegalDirector> entry) => _directorCommandCard(
            number: entry.key + 1,
            director: entry.value,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0x1118B8C9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x4438E8FF)),
          ),
          child: const Text(
            'OPERATING LOOP\nRESEARCH → DIAGNOSE → JURISDICTION → EVIDENCE → DRAFT → STATUTORY QA → CHAIRMAN REVIEW → NEXT ACTION',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.55,
              color: _cyan,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _directorCommandCard({
    required int number,
    required LegalDirector director,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF103945), Color(0xFF0A2028)],
              ),
              border: Border.all(color: const Color(0x5538E8FF)),
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  color: _cyan,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  director.title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  director.code,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  director.mission,
                  style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.4),
                ),
                const SizedBox(height: 8),
                _miniChip('ONLINE', _green),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: <Widget>[
        _pageHeader(
          icon: Icons.groups_2_rounded,
          title: 'EXECUTIVE BOARD ROOM',
          subtitle: 'Seven-member board • Chairman retains final authority',
        ),
        const SizedBox(height: 14),
        _chairmanBoardCard(),
        const SizedBox(height: 10),
        ...enterpriseBoard
            .where((BoardMember member) => !member.isHuman)
            .map(_aiBoardCard),
      ],
    );
  }

  Widget _chairmanBoardCard() {
    final BoardMember chairman =
        enterpriseBoard.firstWhere((BoardMember member) => member.isHuman);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF28200F), Color(0xFF11100B)],
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0x88FFC857)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 55,
            height: 55,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x1AFFC857),
              border: Border.all(color: _gold),
            ),
            child: const Icon(Icons.chair_alt_rounded, color: _gold, size: 28),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'SEAT 01 • CHAIRMAN',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  chairman.name,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  chairman.focus,
                  style: const TextStyle(color: _muted, fontSize: 11, height: 1.35),
                ),
              ],
            ),
          ),
          const Icon(Icons.verified_rounded, color: _gold),
        ],
      ),
    );
  }

  Widget _aiBoardCard(BoardMember member) {
    final int seat = enterpriseBoard.indexOf(member) + 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: const Color(0x1238E8FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.smart_toy_outlined, color: _cyan, size: 23),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'SEAT ${seat.toString().padLeft(2, '0')} • ${member.seat.toUpperCase()}',
                  style: const TextStyle(
                    color: _cyan,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  member.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  member.focus,
                  style: const TextStyle(color: _muted, fontSize: 10.5, height: 1.3),
                ),
              ],
            ),
          ),
          _miniChip('AI', _green),
        ],
      ),
    );
  }

  Widget _buildAiPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: <Widget>[
        _pageHeader(
          icon: Icons.psychology_alt_rounded,
          title: 'JARVIS LEGAL COUNSEL',
          subtitle: _api.isConfigured
              ? 'Secure live backend connected'
              : 'Offline-first legal command channel',
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _api.isConfigured
                ? const Color(0x1062E6A7)
                : const Color(0x10FFC857),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: _api.isConfigured
                  ? const Color(0x4462E6A7)
                  : const Color(0x44FFC857),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                _api.isConfigured
                    ? Icons.cloud_done_outlined
                    : Icons.offline_bolt_outlined,
                color: _api.isConfigured ? _green : _gold,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _api.isConfigured
                      ? 'JARVIS LIVE: legal commands are routed to the configured secure backend.'
                      : 'LOCAL MODE: matter storage, routing, board and director systems remain available without a backend.',
                  style: const TextStyle(fontSize: 11.5, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _aiController,
          minLines: 8,
          maxLines: 18,
          decoration: const InputDecoration(
            labelText: 'Chairman legal command',
            alignLabelWithHint: true,
            prefixIcon: Padding(
              padding: EdgeInsets.only(bottom: 150),
              child: Icon(Icons.keyboard_command_key_rounded),
            ),
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
              : const Icon(Icons.play_arrow_rounded),
          label: const Text('EXECUTE JARVIS LEGAL ANALYSIS'),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFF071219),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0x4438E8FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'JARVIS RESPONSE',
                style: TextStyle(
                  color: _cyan,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                _aiAnswer,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Legal safety: this system supports research, organization, drafting and decision support. Generated legal work should be reviewed by qualified counsel when legal representation or professional advice is required.',
          style: TextStyle(color: _muted, fontSize: 10.5, height: 1.4),
        ),
      ],
    );
  }

  Widget _pageHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: <Widget>[
        Container(
          width: 47,
          height: 47,
          decoration: BoxDecoration(
            color: const Color(0x1438E8FF),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0x4438E8FF)),
          ),
          child: Icon(icon, color: _cyan, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: _muted, fontSize: 10.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ],
          ),
        ),
        Container(width: 28, height: 2, color: _cyan),
      ],
    );
  }

  Widget _miniChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x12000000),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required String button,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 50, color: _muted),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onPressed, child: Text(button)),
        ],
      ),
    );
  }
}

class _CommandAction {
  const _CommandAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
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
          child: Container(
            constraints: const BoxConstraints(maxWidth: 430),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.lock_rounded, size: 60, color: _gold),
                const SizedBox(height: 14),
                Text(
                  'Client subscription required',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('Current role: $role'),
                const SizedBox(height: 8),
                const Text(
                  'Chairman accounts are permanently exempt from subscription billing.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
