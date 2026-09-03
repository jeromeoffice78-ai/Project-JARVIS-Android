import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';

class JarvisMemoryScreen extends ConsumerStatefulWidget {
  const JarvisMemoryScreen({super.key});

  @override
  ConsumerState<JarvisMemoryScreen> createState() =>
      _JarvisMemoryScreenState();
}

class _JarvisMemoryScreenState
    extends ConsumerState<JarvisMemoryScreen> {
  final TextEditingController _memory =
      TextEditingController();
  final TextEditingController _query =
      TextEditingController();

  bool _busy = false;
  String _result = '';

  @override
  void dispose() {
    _memory.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _memory.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() => _busy = true);

    try {
      final id = await ref
          .read(jarvisApiServiceProvider)
          .saveMemory(text: text);

      setState(() {
        _result = 'Saved memory: $id';
        _memory.clear();
      });
    } on Object catch (error) {
      setState(() {
        _result = 'Memory save failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) {
      return;
    }

    setState(() => _busy = true);

    try {
      final context = await ref
          .read(jarvisApiServiceProvider)
          .queryMemory(query);

      setState(() {
        _result = context.isEmpty
            ? 'No relevant persistent memory found.'
            : context;
      });
    } on Object catch (error) {
      setState(() {
        _result = 'Memory lookup failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: <Widget>[
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.psychology,
                  ),
                  title: Text(
                    'Persistent Memory',
                  ),
                  subtitle: Text(
                    'Store durable facts and retrieve '
                    'them semantically.',
                  ),
                ),
                TextField(
                  controller: _memory,
                  minLines: 2,
                  maxLines: 5,
                  decoration:
                      const InputDecoration(
                    labelText: 'Memory to save',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Memory'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _query,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Search persistent memory',
                    prefixIcon:
                        Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _search,
                  icon: const Icon(
                    Icons.travel_explore,
                  ),
                  label:
                      const Text('Retrieve Context'),
                ),
              ],
            ),
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 18),
          const LinearProgressIndicator(),
        ],
        if (_result.isNotEmpty) ...[
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: SelectableText(_result),
            ),
          ),
        ],
      ],
    );
  }
}
