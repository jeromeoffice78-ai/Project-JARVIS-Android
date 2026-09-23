import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../chat/jarvis_chat_controller.dart';
import 'jarvis_voice_service.dart';

class JarvisVoiceController {
  static const String _wakePassKey =
      'jarvis.voice.wake_pass';
  static const String defaultWakePass =
      'Hey Jarvis';

  JarvisVoiceController({
    required JarvisVoiceService voiceService,
    required JarvisChatController chatController,
  })  : _voiceService = voiceService,
        _chatController = chatController {
    _finalTranscriptSubscription =
        _voiceService.finalTranscriptStream.listen(
      (String transcript) {
        unawaited(
          _handleFinalTranscript(transcript),
        );
      },
    );

    _chatStateSubscription =
        _chatController.stateStream.listen(
      (JarvisChatState state) {
        unawaited(
          _handleChatState(state),
        );
      },
    );
  }

  final JarvisVoiceService _voiceService;
  final JarvisChatController _chatController;
  final SharedPreferencesAsync _preferences =
      SharedPreferencesAsync();

  final StreamController<bool> _handsFreeController =
      StreamController<bool>.broadcast();

  final StreamController<bool> _spokenRepliesController =
      StreamController<bool>.broadcast();

  final StreamController<bool> _wakeWordController =
      StreamController<bool>.broadcast();

  final StreamController<String> _wakePassController =
      StreamController<String>.broadcast();

  StreamSubscription<String>?
      _finalTranscriptSubscription;

  StreamSubscription<JarvisChatState>?
      _chatStateSubscription;

  bool _handsFree = false;
  bool _spokenReplies = true;
  bool _wakeWordMode = false;
  String _wakePass = defaultWakePass;
  bool _disposed = false;

  String? _voiceRequestId;
  String? _lastSpokenRequestId;

  int _conversationGeneration = 0;

  bool get handsFree => _handsFree;
  bool get spokenReplies => _spokenReplies;
  bool get wakeWordMode => _wakeWordMode;
  String get wakePass => _wakePass;

  Stream<bool> get handsFreeStream =>
      _handsFreeController.stream;

  Stream<bool> get spokenRepliesStream =>
      _spokenRepliesController.stream;

  Stream<bool> get wakeWordStream =>
      _wakeWordController.stream;

  Stream<String> get wakePassStream =>
      _wakePassController.stream;

  Future<bool> initialize() async {
    if (_disposed) {
      return false;
    }

    await _loadWakePass();
    return _voiceService.initialize();
  }

  Future<void> _loadWakePass() async {
    final String? stored =
        await _preferences.getString(
      _wakePassKey,
    );

    final String value =
        stored?.trim().isNotEmpty == true
            ? stored!.trim()
            : defaultWakePass;

    _wakePass = value;

    if (!_wakePassController.isClosed) {
      _wakePassController.add(value);
    }
  }

  Future<void> setWakePass(
    String value,
  ) async {
    final String normalized =
        value.trim();

    if (normalized.length < 3) {
      throw ArgumentError(
        'Wake pass must be at least 3 characters.',
      );
    }

    _wakePass = normalized;

    await _preferences.setString(
      _wakePassKey,
      normalized,
    );

    if (!_wakePassController.isClosed) {
      _wakePassController.add(
        normalized,
      );
    }
  }

  Future<void> startPushToTalk() async {
    if (_disposed) {
      return;
    }

    _conversationGeneration++;

    await _voiceService.stopSpeaking();
    await _voiceService.startListening();
  }

  Future<void> stopPushToTalk() async {
    if (_disposed) {
      return;
    }

    await _voiceService.stopListening();
  }

  Future<void> startHandsFreeConversation() async {
    if (_disposed) {
      return;
    }

    _conversationGeneration++;

    _wakeWordMode = false;
    _emitWakeWord();

    _handsFree = true;
    _emitHandsFree();

    await _voiceService.stopSpeaking();
    await _voiceService.startListening();
  }

  Future<void> stopHandsFreeConversation() async {
    if (_disposed) {
      return;
    }

    _conversationGeneration++;

    _handsFree = false;
    _emitHandsFree();

    await _voiceService.cancelListening();
    await _voiceService.stopSpeaking();
  }

  Future<void> startWakeWordMode() async {
    if (_disposed) {
      return;
    }

    await _loadWakePass();
    _conversationGeneration++;

    _handsFree = false;
    _emitHandsFree();

    _wakeWordMode = true;
    _emitWakeWord();

    await _voiceService.stopSpeaking();
    await _voiceService.startListening();
  }

  Future<void> stopWakeWordMode() async {
    if (_disposed) {
      return;
    }

    _conversationGeneration++;

    _wakeWordMode = false;
    _emitWakeWord();

    await _voiceService.cancelListening();
  }

  Future<void> interruptAndListen() async {
    if (_disposed) {
      return;
    }

    _conversationGeneration++;

    await _voiceService.stopSpeaking();
    await _voiceService.startListening();
  }

  void setSpokenReplies(
    bool enabled,
  ) {
    if (_disposed ||
        _spokenReplies == enabled) {
      return;
    }

    _spokenReplies = enabled;

    if (!_spokenRepliesController.isClosed) {
      _spokenRepliesController.add(enabled);
    }
  }

  void setHandsFree(
    bool enabled,
  ) {
    if (_disposed ||
        _handsFree == enabled) {
      return;
    }

    if (enabled) {
      unawaited(
        startHandsFreeConversation(),
      );
    } else {
      unawaited(
        stopHandsFreeConversation(),
      );
    }
  }

  void setWakeWordMode(
    bool enabled,
  ) {
    if (_disposed ||
        _wakeWordMode == enabled) {
      return;
    }

    if (enabled) {
      unawaited(
        startWakeWordMode(),
      );
    } else {
      unawaited(
        stopWakeWordMode(),
      );
    }
  }

  String? submitVoiceCommand(
    String text,
  ) {
    if (_disposed) {
      return null;
    }

    final String normalized =
        text.trim();

    if (normalized.isEmpty) {
      return null;
    }

    final String? requestId =
        _chatController.askJarvis(
      normalized,
    );

    _voiceRequestId = requestId;

    return requestId;
  }

  Future<void> _handleFinalTranscript(
    String transcript,
  ) async {
    final String normalized =
        transcript.trim();

    if (normalized.isEmpty) {
      return;
    }

    if (!_wakeWordMode) {
      submitVoiceCommand(
        normalized,
      );
      return;
    }

    final String lower =
        normalized.toLowerCase();

    final String wakePassLower =
        _wakePass.toLowerCase();

    final int wakeIndex =
        lower.indexOf(
      wakePassLower,
    );

    if (wakeIndex < 0) {
      await _resumeWakeListening();
      return;
    }

    final String command =
        normalized
            .substring(
              wakeIndex +
                  _wakePass.length,
            )
            .trim()
            .replaceFirst(
              RegExp(
                r'^[,.:;!?\-\s]+',
              ),
              '',
            )
            .trim();

    if (command.isEmpty) {
      await _voiceService.speak(
        'Yes?',
      );

      await _resumeWakeListening();
      return;
    }

    submitVoiceCommand(
      command,
    );
  }

  Future<void> _resumeWakeListening() async {
    await Future<void>.delayed(
      const Duration(
        milliseconds: 350,
      ),
    );

    if (_disposed ||
        !_wakeWordMode ||
        _voiceRequestId != null) {
      return;
    }

    await _voiceService.startListening();
  }

  Future<void> _handleChatState(
    JarvisChatState state,
  ) async {
    if (_disposed) {
      return;
    }

    final String? voiceRequestId =
        _voiceRequestId;

    if (voiceRequestId == null ||
        state.requestId != voiceRequestId) {
      return;
    }

    if (state.status ==
        JarvisChatStatus.completed) {
      if (_lastSpokenRequestId ==
          voiceRequestId) {
        return;
      }

      _lastSpokenRequestId =
          voiceRequestId;

      final int generation =
          _conversationGeneration;

      if (_spokenReplies &&
          state.responseText
              .trim()
              .isNotEmpty) {
        await _voiceService.speak(
          state.responseText,
        );
      }

      if (_voiceRequestId ==
          voiceRequestId) {
        _voiceRequestId = null;
      }

      final bool shouldRelisten =
          _handsFree || _wakeWordMode;

      if (_disposed ||
          !shouldRelisten ||
          generation !=
              _conversationGeneration) {
        return;
      }

      await Future<void>.delayed(
        const Duration(
          milliseconds: 450,
        ),
      );

      if (_disposed ||
          !(_handsFree ||
              _wakeWordMode) ||
          generation !=
              _conversationGeneration) {
        return;
      }

      await _voiceService.startListening();
      return;
    }

    if (state.status ==
            JarvisChatStatus.error ||
        state.status ==
            JarvisChatStatus.cancelled) {
      _voiceRequestId = null;

      if (_wakeWordMode) {
        await _resumeWakeListening();
      }
    }
  }

  void _emitWakeWord() {
    if (!_disposed &&
        !_wakeWordController.isClosed) {
      _wakeWordController.add(
        _wakeWordMode,
      );
    }
  }

  void _emitHandsFree() {
    if (!_disposed &&
        !_handsFreeController.isClosed) {
      _handsFreeController.add(
        _handsFree,
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _conversationGeneration++;

    await _finalTranscriptSubscription
        ?.cancel();

    await _chatStateSubscription
        ?.cancel();

    _finalTranscriptSubscription = null;
    _chatStateSubscription = null;

    await Future.wait<void>(
      <Future<void>>[
        _handsFreeController.close(),
        _spokenRepliesController.close(),
        _wakeWordController.close(),
        _wakePassController.close(),
      ],
    );
  }
}
