import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/jarvis_api_service.dart';
import '../../core/network/providers.dart';

enum _FrontierMode {
  reason,
  research,
  code,
  image,
}

class JarvisFrontierScreen
    extends ConsumerStatefulWidget {
  const JarvisFrontierScreen({super.key});

  @override
  ConsumerState<JarvisFrontierScreen>
      createState() =>
          _JarvisFrontierScreenState();
}

class _JarvisFrontierScreenState
    extends ConsumerState<JarvisFrontierScreen> {
  final TextEditingController _promptController =
      TextEditingController();

  _FrontierMode _mode = _FrontierMode.reason;
  bool _loading = false;
  String _answer = '';
  String _model = '';
  String? _error;
  List<Map<String, String>> _sources =
      const <Map<String, String>>[];
  Uint8List? _imageBytes;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  String get _modeName => switch (_mode) {
        _FrontierMode.reason => 'reason',
        _FrontierMode.research => 'research',
        _FrontierMode.code => 'code',
        _FrontierMode.image => 'image',
      };

  Future<void> _run() async {
    final String prompt =
        _promptController.text.trim();
    if (prompt.isEmpty || _loading) {
      return;
    }

    setState(() {
      _loading = true;
      _answer = '';
      _model = '';
      _sources =
          const <Map<String, String>>[];
      _imageBytes = null;
      _error = null;
    });

    try {
      final JarvisApiService api =
          ref.read(jarvisApiServiceProvider);

      if (_mode == _FrontierMode.image) {
        final JarvisGeneratedImage result =
            await api.generateImage(prompt);

        if (!mounted) {
          return;
        }

        setState(() {
          _imageBytes =
              base64Decode(result.base64);
          _model = result.model;
        });
      } else {
        final JarvisFrontierResult result =
            await api.frontierQuery(
          prompt: prompt,
          mode: _modeName,
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _answer = result.answer;
          _model = result.model;
          _sources = result.sources;
        });
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openSource(
    String rawUrl,
  ) async {
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        !(uri.scheme == 'http' ||
            uri.scheme == 'https')) {
      return;
    }

    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'JARVIS Frontier AI',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Frontier Core gives Jarvis advanced reasoning, live web research, sandboxed Python/code execution, and image generation through the server-side AI stack.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_FrontierMode>(
            segments:
                const <ButtonSegment<
                    _FrontierMode>>[
              ButtonSegment<_FrontierMode>(
                value: _FrontierMode.reason,
                icon: Icon(Icons.psychology),
                label: Text('Reason'),
              ),
              ButtonSegment<_FrontierMode>(
                value:
                    _FrontierMode.research,
                icon: Icon(Icons.travel_explore),
                label: Text('Research'),
              ),
              ButtonSegment<_FrontierMode>(
                value: _FrontierMode.code,
                icon: Icon(Icons.code),
                label: Text('Code'),
              ),
              ButtonSegment<_FrontierMode>(
                value: _FrontierMode.image,
                icon: Icon(Icons.image_outlined),
                label: Text('Image'),
              ),
            ],
            selected:
                <_FrontierMode>{_mode},
            onSelectionChanged:
                (Set<_FrontierMode> selected) {
              if (selected.isEmpty) {
                return;
              }

              setState(() {
                _mode = selected.first;
                _answer = '';
                _sources =
                    const <Map<String, String>>[];
                _imageBytes = null;
                _error = null;
              });
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _promptController,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              border:
                  const OutlineInputBorder(),
              labelText: switch (_mode) {
                _FrontierMode.reason =>
                  'Problem or question',
                _FrontierMode.research =>
                  'Research objective',
                _FrontierMode.code =>
                  'Coding / analysis task',
                _FrontierMode.image =>
                  'Describe the image',
              },
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _run,
            icon: Icon(
              switch (_mode) {
                _FrontierMode.reason =>
                  Icons.psychology,
                _FrontierMode.research =>
                  Icons.travel_explore,
                _FrontierMode.code =>
                  Icons.play_circle_outline,
                _FrontierMode.image =>
                  Icons.auto_awesome,
              },
            ),
            label: Text(
              switch (_mode) {
                _FrontierMode.reason =>
                  'Reason',
                _FrontierMode.research =>
                  'Research',
                _FrontierMode.code =>
                  'Run Code Lab',
                _FrontierMode.image =>
                  'Create Image',
              },
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_model.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Model: $_model',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium,
            ),
          ],
          if (_answer.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Jarvis Result',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy',
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: _answer,
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.copy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(_answer),
                  ],
                ),
              ),
            ),
          ],
          if (_sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Research sources',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium,
            ),
            const SizedBox(height: 6),
            ..._sources.map(
              (Map<String, String> source) {
                return Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.link),
                    title: Text(
                      source['title'] ??
                          source['url'] ??
                          'Source',
                    ),
                    subtitle: Text(
                      source['url'] ?? '',
                    ),
                    onTap: () => _openSource(
                      source['url'] ?? '',
                    ),
                  ),
                );
              },
            ),
          ],
          if (_imageBytes != null) ...[
            const SizedBox(height: 16),
            Card(
              clipBehavior:
                  Clip.antiAlias,
              child: Image.memory(
                _imageBytes!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .error,
                ),
                title: const Text(
                  'Frontier tool error',
                ),
                subtitle: Text(_error!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
