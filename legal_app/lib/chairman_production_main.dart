import 'dart:async';

import 'package:flutter/material.dart';

import 'chairman_auth.dart';
import 'chairman_board_room.dart';
import 'jarvis_legal_api.dart';
import 'legal_core.dart';
import 'main.dart' show ChairmanCommandCenter;

const Color _bg = Color(0xFF05090D);
const Color _panel = Color(0xFF0A1218);
const Color _cyan = Color(0xFF38E8FF);
const Color _gold = Color(0xFFFFC857);
const Color _green = Color(0xFF62E6A7);
const Color _muted = Color(0xFF91A6B2);
const Color _border = Color(0xFF183746);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisChairmanProductionApp());
}

class JarvisChairmanProductionApp extends StatelessWidget {
  const JarvisChairmanProductionApp({super.key});

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
      home: const ChairmanAuthGate(
        child: ChairmanProductionShell(),
      ),
    );
  }
}

class ChairmanProductionShell extends StatefulWidget {
  const ChairmanProductionShell({super.key});

  @override
  State<ChairmanProductionShell> createState() =>
      _ChairmanProductionShellState();
}

class _ChairmanProductionShellState extends State<ChairmanProductionShell> {
  final LegalMatterStore _matterStore = LegalMatterStore();
  List<LegalMatter> _matters = const <LegalMatter>[];
  bool _boardOpen = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshMatters());
  }

  Future<void> _refreshMatters() async {
    final List<LegalMatter> matters = await _matterStore.load();
    if (!mounted) return;
    setState(() => _matters = matters);
  }

  Future<void> _openBoardRoom() async {
    await _refreshMatters();
    if (!mounted) return;
    setState(() => _boardOpen = true);
  }

  void _openCounselHandoff(String prompt) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChairmanCounselHandoffPage(initialPrompt: prompt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_boardOpen) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back to command center',
            onPressed: () => setState(() => _boardOpen = false),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'CHAIRMAN BOARD ROOM',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
              Text(
                '6 AI DIRECTORS + CHAIRMAN',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.3,
                  color: _cyan,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Refresh matters',
              onPressed: _refreshMatters,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: ChairmanBoardRoom(
            matters: _matters,
            onSendToCounsel: _openCounselHandoff,
          ),
        ),
      );
    }

    return Stack(
      children: <Widget>[
        const ChairmanCommandCenter(),
        Positioned(
          right: 16,
          bottom: 92,
          child: SafeArea(
            child: FloatingActionButton.extended(
              heroTag: 'chairman-board-room',
              onPressed: _openBoardRoom,
              backgroundColor: const Color(0xFF10252E),
              foregroundColor: _cyan,
              icon: const Icon(Icons.groups_rounded),
              label: const Text(
                'BOARD ROOM',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ChairmanCounselHandoffPage extends StatefulWidget {
  const ChairmanCounselHandoffPage({
    required this.initialPrompt,
    super.key,
  });

  final String initialPrompt;

  @override
  State<ChairmanCounselHandoffPage> createState() =>
      _ChairmanCounselHandoffPageState();
}

class _ChairmanCounselHandoffPageState
    extends State<ChairmanCounselHandoffPage> {
  final JarvisLegalApi _api = JarvisLegalApi();
  late final TextEditingController _controller;
  bool _sending = false;
  String _answer = 'Board directive ready for JARVIS Legal Counsel.';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPrompt);
  }

  @override
  void dispose() {
    _controller.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _send() async {
    final String prompt = _controller.text.trim();
    if (prompt.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _answer = 'JARVIS is processing the Chairman board directive...';
    });

    try {
      final String answer = await _api.ask(
        prompt: prompt,
        role: chairmanRole,
      );
      if (!mounted) return;
      setState(() => _answer = answer);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _answer = 'Counsel handoff failed: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BOARD → LEGAL COUNSEL',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text(
              'CHAIRMAN DIRECTIVE HANDOFF',
              style: TextStyle(
                color: _cyan,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Review the board-generated instruction before sending it to the authenticated JARVIS Legal Counsel channel.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              minLines: 7,
              maxLines: 16,
              decoration: const InputDecoration(
                labelText: 'Board directive',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'PROCESSING' : 'SEND TO COUNSEL'),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _answer,
                  style: const TextStyle(height: 1.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
