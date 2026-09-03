import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum JarvisVoiceState {
  inactive,
  unavailable,
  initializing,
  idle,
  listening,
  speaking,
  error,
}

class JarvisVoiceService {
  JarvisVoiceService();

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  final StreamController<JarvisVoiceState> _stateController =
      StreamController<JarvisVoiceState>.broadcast();

  final StreamController<String> _transcriptController =
      StreamController<String>.broadcast();

  final StreamController<String> _finalTranscriptController =
      StreamController<String>.broadcast();

  final StreamController<double> _soundLevelController =
      StreamController<double>.broadcast();

  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

  AudioSession? _audioSession;

  JarvisVoiceState _state = JarvisVoiceState.inactive;
  String _currentTranscript = '';
  bool _initialized = false;
  bool _disposed = false;
  bool _finalSentForListen = false;

  Stream<JarvisVoiceState> get stateStream => _stateController.stream;
  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<String> get finalTranscriptStream =>
      _finalTranscriptController.stream;
  Stream<double> get soundLevelStream => _soundLevelController.stream;
  Stream<String?> get errorStream => _errorController.stream;

  JarvisVoiceState get state => _state;
  String get currentTranscript => _currentTranscript;
  bool get isListening => _speech.isListening;
  bool get isInitialized => _initialized;

  Future<bool> initialize() async {
    if (_disposed) {
      throw StateError('JarvisVoiceService has been disposed.');
    }

    if (_initialized) {
      return true;
    }

    _setState(JarvisVoiceState.initializing);
    _emitError(null);

    try {
      final AudioSession session = await AudioSession.instance;
      _audioSession = session;

      await session.configure(
        const AudioSessionConfiguration.speech(),
      );

      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(0.95);
      await _tts.setVolume(1.0);

      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS) {
        await _tts.setSharedInstance(true);

        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          <IosTextToSpeechAudioCategoryOptions>[
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ],
          IosTextToSpeechAudioMode.voiceChat,
        );
      }

      _tts.setStartHandler(() {
        if (!_disposed) {
          _setState(JarvisVoiceState.speaking);
        }
      });

      _tts.setCompletionHandler(() {
        if (!_disposed) {
          _setState(JarvisVoiceState.idle);
        }
      });

      _tts.setCancelHandler(() {
        if (!_disposed) {
          _setState(JarvisVoiceState.idle);
        }
      });

      _tts.setErrorHandler((dynamic message) {
        if (_disposed) {
          return;
        }

        _emitError(
          'Text-to-speech error: $message',
        );
        _setState(JarvisVoiceState.error);
      });

      final bool available = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: (error) {
          if (_disposed) {
            return;
          }

          _emitError(
            'Speech recognition error: ${error.errorMsg}',
          );

          if (error.permanent) {
            _setState(JarvisVoiceState.unavailable);
          } else if (_state == JarvisVoiceState.listening) {
            _setState(JarvisVoiceState.error);
          }
        },
        debugLogging: false,
      );

      if (!available) {
        _setState(JarvisVoiceState.unavailable);
        _emitError(
          'Speech recognition is unavailable or microphone '
          'permission was not granted.',
        );
        return false;
      }

      _initialized = true;
      _setState(JarvisVoiceState.idle);

      return true;
    } on Object catch (error) {
      _emitError(
        'Voice initialization failed: $error',
      );
      _setState(JarvisVoiceState.error);
      return false;
    }
  }

  Future<void> startListening({
    String? localeId,
  }) async {
    if (_disposed) {
      return;
    }

    if (!_initialized) {
      final bool ready = await initialize();

      if (!ready) {
        return;
      }
    }

    await stopSpeaking();

    if (_speech.isListening) {
      await _speech.cancel();
    }

    _currentTranscript = '';
    _finalSentForListen = false;
    _emitTranscript('');
    _emitError(null);

    _setState(JarvisVoiceState.listening);

    try {
      await _speech.listen(
        onResult: _handleSpeechResult,
        onSoundLevelChange: (double level) {
          if (!_disposed &&
              !_soundLevelController.isClosed) {
            _soundLevelController.add(level);
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          onDevice: false,
          listenMode: ListenMode.dictation,
          autoPunctuation: true,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 30),
          localeId: localeId,
        ),
      );
    } on Object catch (error) {
      _emitError(
        'Unable to start listening: $error',
      );
      _setState(JarvisVoiceState.error);
    }
  }

  Future<void> stopListening({
    bool submitRecognizedWords = true,
  }) async {
    if (_disposed) {
      return;
    }

    if (_speech.isListening) {
      if (submitRecognizedWords) {
        await _speech.stop();
      } else {
        await _speech.cancel();
      }
    }

    if (submitRecognizedWords) {
      _emitFinalTranscriptIfNeeded();
    }

    if (_state == JarvisVoiceState.listening) {
      _setState(JarvisVoiceState.idle);
    }
  }

  Future<void> cancelListening() async {
    await stopListening(
      submitRecognizedWords: false,
    );
  }

  Future<void> speak(
    String text,
  ) async {
    if (_disposed) {
      return;
    }

    final String normalized = text.trim();

    if (normalized.isEmpty) {
      return;
    }

    if (!_initialized) {
      final bool ready = await initialize();

      if (!ready) {
        return;
      }
    }

    if (_speech.isListening) {
      await _speech.cancel();
    }

    await _tts.stop();

    _setState(JarvisVoiceState.speaking);
    _emitError(null);

    try {
      await _tts.speak(
        normalized,
        focus: true,
      );

      if (!_disposed &&
          _state == JarvisVoiceState.speaking) {
        _setState(JarvisVoiceState.idle);
      }
    } on Object catch (error) {
      _emitError(
        'Jarvis voice playback failed: $error',
      );
      _setState(JarvisVoiceState.error);
    }
  }

  Future<void> stopSpeaking() async {
    if (_disposed) {
      return;
    }

    try {
      await _tts.stop();
    } on Object {
      // Best-effort interruption.
    }

    if (_state == JarvisVoiceState.speaking) {
      _setState(JarvisVoiceState.idle);
    }
  }

  Future<List<String>> audioDeviceSummary() async {
    final AudioSession session =
        _audioSession ?? await AudioSession.instance;

    _audioSession = session;

    final Set<AudioDevice> devices =
        await session.getDevices();

    final List<AudioDevice> sorted =
        devices.toList(growable: false)
          ..sort(
            (AudioDevice a, AudioDevice b) =>
                a.name.compareTo(b.name),
          );

    return sorted
        .map(
          (AudioDevice device) {
            final String roles = <String>[
              if (device.isInput) 'input',
              if (device.isOutput) 'output',
            ].join('/');

            return '${device.name} '
                '[${device.type.name}; $roles]';
          },
        )
        .toList(growable: false);
  }

  void _handleSpeechResult(
    SpeechRecognitionResult result,
  ) {
    if (_disposed) {
      return;
    }

    _currentTranscript =
        result.recognizedWords.trim();

    _emitTranscript(
      _currentTranscript,
    );

    if (result.finalResult) {
      _emitFinalTranscriptIfNeeded();
    }
  }

  void _handleSpeechStatus(
    String status,
  ) {
    if (_disposed) {
      return;
    }

    if (status == SpeechToText.listeningStatus) {
      _setState(JarvisVoiceState.listening);
      return;
    }

    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _emitFinalTranscriptIfNeeded();

      if (_state == JarvisVoiceState.listening) {
        _setState(JarvisVoiceState.idle);
      }
    }
  }

  void _emitFinalTranscriptIfNeeded() {
    if (_disposed || _finalSentForListen) {
      return;
    }

    final String finalText =
        _currentTranscript.trim();

    if (finalText.isEmpty) {
      return;
    }

    _finalSentForListen = true;

    if (!_finalTranscriptController.isClosed) {
      _finalTranscriptController.add(
        finalText,
      );
    }
  }

  void _emitTranscript(
    String text,
  ) {
    if (!_disposed &&
        !_transcriptController.isClosed) {
      _transcriptController.add(text);
    }
  }

  void _emitError(
    String? message,
  ) {
    if (!_disposed &&
        !_errorController.isClosed) {
      _errorController.add(message);
    }
  }

  void _setState(
    JarvisVoiceState state,
  ) {
    if (_disposed ||
        _stateController.isClosed ||
        _state == state) {
      return;
    }

    _state = state;
    _stateController.add(state);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    await cancelListening();
    await stopSpeaking();

    _disposed = true;

    await Future.wait<void>(
      <Future<void>>[
        _stateController.close(),
        _transcriptController.close(),
        _finalTranscriptController.close(),
        _soundLevelController.close(),
        _errorController.close(),
      ],
    );
  }
}
