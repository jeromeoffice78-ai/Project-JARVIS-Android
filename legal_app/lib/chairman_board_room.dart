import 'dart:async';

import 'package:flutter/material.dart';

import 'board_core.dart';
import 'legal_core.dart';

const Color _boardPanel = Color(0xFF0A1218);
const Color _boardPanel2 = Color(0xFF0E1B22);
const Color _boardCyan = Color(0xFF38E8FF);
const Color _boardGold = Color(0xFFFFC857);
const Color _boardGreen = Color(0xFF62E6A7);
const Color _boardRed = Color(0xFFFF7272);
const Color _boardMuted = Color(0xFF91A6B2);
const Color _boardBorder = Color(0xFF183746);

class ChairmanBoardRoom extends StatefulWidget {
  const ChairmanBoardRoom({
    required this.matters,
    required this.onSendToCounsel,
    super.key,
  });

  final List<LegalMatter> matters;
  final ValueChanged<String> onSendToCounsel;

  @override
  State<ChairmanBoardRoom> createState() => _ChairmanBoardRoomState();
}

class _ChairmanBoardRoomState extends State<ChairmanBoardRoom> {
  final ChairmanDirectiveStore _store = ChairmanDirectiveStore();
  final BoardBriefingEngine _engine = const BoardBriefingEngine();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _instructionController = TextEditingController();

  List<ChairmanDirective> _directives = <ChairmanDirective>[];
  DirectivePriority _priority = DirectivePriority.normal;
  BoardBrief? _brief;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ChairmanBoardRoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.matters != widget.matters) {
      _generateBrief();
    }
  }

  Future<void> _load() async {
    final List<ChairmanDirective> directives = await _store.load();
    if (!mounted) return;
    setState(() {
      _directives = directives;
      _loading = false;
      _brief = _engine.build(
        matters: widget.matters,
        directives: directives,
      );
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _instructionController.dispose();
    super.dispose();
  }

  void _generateBrief() {
    if (!mounted) return;
    setState(() {
      _brief = _engine.build(
        matters: widget.matters,
        directives: _directives,
      );
    });
  }

  Future<void> _addDirective() async {
    final String title = _titleController.text.trim();
    final String instruction = _instructionController.text.trim();
    if (title.isEmpty || instruction.isEmpty) {
      _message('Directive title and instruction are required.');
      return;
    }

    final ChairmanDirective directive = ChairmanDirective(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      instruction: instruction,
      createdAt: DateTime.now(),
      priority: _priority,
    );
    final List<ChairmanDirective> updated = <ChairmanDirective>[
      directive,
      ..._directives,
    ];
    await _store.save(updated);
    if (!mounted) return;
    setState(() {
      _directives = updated;
      _titleController.clear();
      _instructionController.clear();
      _priority = DirectivePriority.normal;
      _brief = _engine.build(matters: widget.matters, directives: updated);
    });
    _message('Chairman directive issued.');
  }

  Future<void> _setStatus(
    ChairmanDirective directive,
    DirectiveStatus status,
  ) async {
    final List<ChairmanDirective> updated = _directives
        .map(
          (ChairmanDirective item) => item.id == directive.id
              ? item.copyWith(status: status)
              : item,
        )
        .toList(growable: false);
    await _store.save(updated);
    if (!mounted) return;
    setState(() {
      _directives = updated;
      _brief = _engine.build(matters: widget.matters, directives: updated);
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  int get _activeCount => _directives
      .where((ChairmanDirective d) => d.status == DirectiveStatus.active)
      .length;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _briefingPanel(),
        const SizedBox(height: 12),
        _directiveComposer(),
        const SizedBox(height: 12),
        if (_directives.isNotEmpty) ...<Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'CHAIRMAN DIRECTIVE LOG',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              _chip('$_activeCount ACTIVE', _boardGreen),
            ],
          ),
          const SizedBox(height: 8),
          ..._directives.take(12).map(_directiveCard),
        ],
      ],
    );
  }

  Widget _briefingPanel() {
    final BoardBrief brief = _brief ??
        _engine.build(matters: widget.matters, directives: _directives);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF071219),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x6638E8FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_rounded, color: _boardCyan, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI BOARD DAILY BRIEFING',
                  style: TextStyle(
                    color: _boardCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              _BoardLiveBadge(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            brief.executiveSummary,
            style: const TextStyle(fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 12),
          _briefRow('AEGIS', brief.governanceRisk, _boardGold),
          _briefRow('LEX', brief.legalOperations, _boardCyan),
          _briefRow('VERITAS', brief.evidenceIntegrity, _boardGreen),
          _briefRow('ATLAS', brief.growthStrategy, _boardCyan),
          _briefRow('SENTINEL', brief.securityCompliance, _boardGold),
          _briefRow('MERIDIAN', brief.financeRevenue, _boardGreen),
          const SizedBox(height: 10),
          const Text(
            'CHAIRMAN ACTION QUEUE',
            style: TextStyle(
              color: _boardGold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          ...brief.chairmanActions.map(
            (String action) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.arrow_right_rounded,
                      size: 16,
                      color: _boardGold,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      action,
                      style: const TextStyle(fontSize: 11.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _generateBrief,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('REFRESH BRIEF'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => widget.onSendToCounsel(brief.toPrompt()),
                  icon: const Icon(Icons.psychology_alt_rounded),
                  label: const Text('SEND TO COUNSEL'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _briefRow(String name, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 65,
            child: Text(
              name,
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFD0DEE5),
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _directiveComposer() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _boardPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _boardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'ISSUE CHAIRMAN DIRECTIVE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Directive title',
              prefixIcon: Icon(Icons.flag_outlined),
            ),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: _instructionController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Instruction / expected result',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 9),
          DropdownButtonFormField<DirectivePriority>(
            initialValue: _priority,
            decoration: const InputDecoration(
              labelText: 'Priority',
              prefixIcon: Icon(Icons.priority_high_rounded),
            ),
            items: DirectivePriority.values
                .map(
                  (DirectivePriority priority) => DropdownMenuItem<DirectivePriority>(
                    value: priority,
                    child: Text(priority.name.toUpperCase()),
                  ),
                )
                .toList(growable: false),
            onChanged: (DirectivePriority? value) {
              if (value != null) setState(() => _priority = value);
            },
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => unawaited(_addDirective()),
            icon: const Icon(Icons.send_rounded),
            label: const Text('ISSUE DIRECTIVE'),
          ),
        ],
      ),
    );
  }

  Widget _directiveCard(ChairmanDirective directive) {
    final Color priorityColor = switch (directive.priority) {
      DirectivePriority.normal => _boardCyan,
      DirectivePriority.high => _boardGold,
      DirectivePriority.critical => _boardRed,
    };
    final bool active = directive.status == DirectiveStatus.active;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: active ? _boardPanel : _boardPanel2,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: active ? _boardBorder : const Color(0xFF1B252B),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  directive.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    decoration: active ? null : TextDecoration.lineThrough,
                  ),
                ),
              ),
              _chip(directive.priority.name.toUpperCase(), priorityColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            directive.instruction,
            style: const TextStyle(color: _boardMuted, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _chip(directive.status.name.toUpperCase(), active ? _boardGreen : _boardMuted),
              const Spacer(),
              if (active)
                TextButton.icon(
                  onPressed: () => unawaited(
                    _setStatus(directive, DirectiveStatus.completed),
                  ),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                  label: const Text('COMPLETE'),
                )
              else
                TextButton.icon(
                  onPressed: () => unawaited(
                    _setStatus(directive, DirectiveStatus.active),
                  ),
                  icon: const Icon(Icons.restart_alt_rounded, size: 17),
                  label: const Text('REOPEN'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
        color: const Color(0x10000000),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BoardLiveBadge extends StatelessWidget {
  const _BoardLiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x1462E6A7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x5562E6A7)),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: _boardGreen,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
