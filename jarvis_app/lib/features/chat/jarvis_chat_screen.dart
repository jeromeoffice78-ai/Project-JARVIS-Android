import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/providers.dart';
import 'jarvis_chat_controller.dart';

class JarvisChatScreen extends ConsumerStatefulWidget {
  const JarvisChatScreen({super.key});

  @override
  ConsumerState<JarvisChatScreen> createState() =>
      _JarvisChatScreenState();
}

class _JarvisChatScreenState
    extends ConsumerState<JarvisChatScreen> {
  final TextEditingController _input =
      TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scroll =
      ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _input.text.trim();

    if (text.isEmpty) {
      return;
    }

    final controller =
        ref.read(jarvisChatControllerProvider);

    final String? requestId =
        controller.askJarvis(text);

    if (requestId != null) {
      _input.clear();
      _focusNode.requestFocus();
    }
  }

  void _readAloud(String message) {
    unawaited(
      ref.read(jarvisVoiceServiceProvider).speak(message).then((_) {
        if (!mounted) return;
        final String? diagnostic =
            ref.read(jarvisVoiceServiceProvider).lastError;
        if (diagnostic?.isNotEmpty == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(diagnostic!)),
          );
        }
      }),
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (!_scroll.hasClients) {
          return;
        }

        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration:
              const Duration(milliseconds: 140),
          curve: Curves.easeOut,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final JarvisChatController controller =
        ref.watch(jarvisChatControllerProvider);

    return StreamBuilder<JarvisChatState>(
      stream: controller.stateStream,
      initialData: controller.state,
      builder: (context, snapshot) {
        final JarvisChatState state =
            snapshot.data ??
                const JarvisChatState.initial();
        final List<JarvisChatTurn> turns = controller.conversation;
        if (turns.isNotEmpty || state.responseText.isNotEmpty) {
          _scrollToEnd();
        }

        return Column(
          children: <Widget>[
            if (turns.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: state.isGenerating
                        ? null
                        : () {
                            controller.clearConversation();
                            setState(() {});
                          },
                    icon: const Icon(Icons.add_comment_outlined, size: 18),
                    label: const Text('NEW CHAT'),
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(18),
                children: <Widget>[
                  if (turns.isEmpty &&
                      state.responseText.isEmpty &&
                      state.status == JarvisChatStatus.idle)
                    const _WelcomeCard(),
                  ...turns.map(
                    (JarvisChatTurn turn) => turn.role == 'user'
                        ? _UserMessageBubble(text: turn.content)
                        : _ResponseCard(
                            text: turn.content,
                            onReadAloud: () => _readAloud(turn.content),
                          ),
                  ),
                  if (state.status == JarvisChatStatus.thinking)
                    const _ThinkingCard(),
                  if (state.responseText.isNotEmpty &&
                      (state.isGenerating ||
                          state.status == JarvisChatStatus.error ||
                          state.status == JarvisChatStatus.cancelled))
                    _ResponseCard(text: state.responseText),
                  if (state.errorMessage != null)
                    _ErrorCard(
                      message: state.errorMessage!,
                      retryable: state.retryable,
                    ),
                ],
              ),
            ),
            if (state.isGenerating)
              const LinearProgressIndicator(
                minHeight: 2,
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction:
                            TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        decoration:
                            const InputDecoration(
                          hintText:
                              'Speak or type to Jarvis...',
                          prefixIcon:
                              Icon(Icons.mic_none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ValueListenableBuilder<
                        TextEditingValue>(
                      valueListenable: _input,
                      builder: (
                        context,
                        value,
                        child,
                      ) {
                        if (state.isGenerating) {
                          return IconButton.filled(
                            tooltip: 'Stop response',
                            onPressed: controller
                                .cancelCurrentResponse,
                            icon:
                                const Icon(Icons.stop),
                          );
                        }

                        return IconButton.filled(
                          tooltip: 'Send',
                          onPressed:
                              value.text.trim().isEmpty
                                  ? null
                                  : _submit,
                          icon: const Icon(
                            Icons.arrow_upward,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.auto_awesome,
              size: 54,
              color:
                  Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'JARVIS ONLINE',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Ask a question, trigger a device action, '
              'or use persistent memory.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingCard extends StatelessWidget {
  const _ThinkingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 12),
            Text('Jarvis is processing...'),
          ],
        ),
      ),
    );
  }
}

class _UserMessageBubble extends StatelessWidget {
  const _UserMessageBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              text,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResponseCard extends StatelessWidget {
  const _ResponseCard({
    required this.text,
    this.onReadAloud,
  });

  final String text;
  final VoidCallback? onReadAloud;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SelectableText(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(height: 1.55),
            ),
            if (onReadAloud != null) ...<Widget>[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: onReadAloud,
                  icon: const Icon(Icons.volume_up_outlined),
                  label: const Text('READ ALOUD'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.retryable,
  });

  final String message;
  final bool retryable;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orangeAccent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                retryable
                    ? '$message\nYou can retry.'
                    : message,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
