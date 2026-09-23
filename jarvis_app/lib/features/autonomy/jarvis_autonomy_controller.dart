import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/jarvis_api_service.dart';
import '../chat/jarvis_chat_controller.dart';

enum JarvisAutonomyStatus {
  idle,
  running,
  waitingForResponse,
  paused,
  completed,
  error,
}

final class JarvisAutonomyState {
  const JarvisAutonomyState({
    required this.status,
    required this.goal,
    required this.step,
    required this.maxSteps,
    required this.lastResponse,
    this.errorMessage,
  });

  const JarvisAutonomyState.initial()
      : status = JarvisAutonomyStatus.idle,
        goal = '',
        step = 0,
        maxSteps = 8,
        lastResponse = '',
        errorMessage = null;

  final JarvisAutonomyStatus status;
  final String goal;
  final int step;
  final int maxSteps;
  final String lastResponse;
  final String? errorMessage;

  bool get isActive =>
      status == JarvisAutonomyStatus.running ||
      status == JarvisAutonomyStatus.waitingForResponse;
}

final class _AutonomyDirective {
  const _AutonomyDirective({
    required this.status,
    required this.nextAction,
  });

  final String status;
  final String nextAction;
}

class JarvisAutonomyController {
  JarvisAutonomyController({
    required JarvisChatController chatController,
    required JarvisApiService apiService,
  })  : _chatController = chatController,
        _apiService = apiService {
    _chatSubscription = _chatController.stateStream.listen(
      _handleChatState,
    );
    unawaited(_restore());
  }

  static const String _goalKey = 'jarvis.autonomy.goal';
  static const String _stepKey = 'jarvis.autonomy.step';
  static const String _maxStepsKey = 'jarvis.autonomy.max_steps';
  static const String _lastResponseKey =
      'jarvis.autonomy.last_response';

  final JarvisChatController _chatController;
  final JarvisApiService _apiService;
  final SharedPreferencesAsync _preferences =
      SharedPreferencesAsync();

  final StreamController<JarvisAutonomyState> _stateController =
      StreamController<JarvisAutonomyState>.broadcast();

  StreamSubscription<JarvisChatState>? _chatSubscription;
  JarvisAutonomyState _state =
      const JarvisAutonomyState.initial();
  bool _disposed = false;

  Stream<JarvisAutonomyState> get stateStream =>
      _stateController.stream;

  JarvisAutonomyState get state => _state;

  Future<void> startGoal(
    String goal, {
    int maxSteps = 8,
  }) async {
    _ensureNotDisposed();

    final String normalized = goal.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Autonomous goal cannot be empty.');
    }

    final int boundedMax = maxSteps.clamp(1, 20);

    _emit(
      JarvisAutonomyState(
        status: JarvisAutonomyStatus.running,
        goal: normalized,
        step: 0,
        maxSteps: boundedMax,
        lastResponse: '',
      ),
    );

    await _persist();
    await _dispatchStep(
      initial: true,
      nextAction: normalized,
    );
  }

  Future<void> pause() async {
    _ensureNotDisposed();

    if (_chatController.state.isGenerating) {
      _chatController.cancelCurrentResponse();
    }

    _emit(
      JarvisAutonomyState(
        status: JarvisAutonomyStatus.paused,
        goal: _state.goal,
        step: _state.step,
        maxSteps: _state.maxSteps,
        lastResponse: _state.lastResponse,
      ),
    );

    await _persist();
  }

  Future<void> resume() async {
    _ensureNotDisposed();

    if (_state.goal.trim().isEmpty) {
      return;
    }

    _emit(
      JarvisAutonomyState(
        status: JarvisAutonomyStatus.running,
        goal: _state.goal,
        step: _state.step,
        maxSteps: _state.maxSteps,
        lastResponse: _state.lastResponse,
      ),
    );

    await _dispatchStep(
      initial: _state.step == 0,
      nextAction: _state.goal,
    );
  }

  Future<void> stop() async {
    _ensureNotDisposed();

    if (_chatController.state.isGenerating) {
      _chatController.cancelCurrentResponse();
    }

    _emit(const JarvisAutonomyState.initial());
    await _clearPersisted();
  }

  void _handleChatState(JarvisChatState chatState) {
    if (_disposed ||
        _state.status !=
            JarvisAutonomyStatus.waitingForResponse) {
      return;
    }

    if (chatState.status == JarvisChatStatus.completed) {
      unawaited(
        _handleCompletedResponse(chatState.responseText),
      );
      return;
    }

    if (chatState.status == JarvisChatStatus.error) {
      _emit(
        JarvisAutonomyState(
          status: JarvisAutonomyStatus.error,
          goal: _state.goal,
          step: _state.step,
          maxSteps: _state.maxSteps,
          lastResponse: _state.lastResponse,
          errorMessage:
              chatState.errorMessage ??
              'Jarvis autonomy step failed.',
        ),
      );
      unawaited(_persist());
    }
  }

  Future<void> _handleCompletedResponse(
    String response,
  ) async {
    final _AutonomyDirective? directive =
        _parseDirective(response);

    final JarvisAutonomyState base =
        JarvisAutonomyState(
      status: JarvisAutonomyStatus.running,
      goal: _state.goal,
      step: _state.step,
      maxSteps: _state.maxSteps,
      lastResponse: response,
    );

    _emit(base);
    await _persist();

    if (directive == null) {
      _emit(
        JarvisAutonomyState(
          status: JarvisAutonomyStatus.paused,
          goal: base.goal,
          step: base.step,
          maxSteps: base.maxSteps,
          lastResponse: response,
          errorMessage:
              'Autonomy paused because the response did not include a valid execution directive.',
        ),
      );
      await _persist();
      return;
    }

    switch (directive.status) {
      case 'DONE':
        _emit(
          JarvisAutonomyState(
            status: JarvisAutonomyStatus.completed,
            goal: base.goal,
            step: base.step,
            maxSteps: base.maxSteps,
            lastResponse: response,
          ),
        );
        await _persist();

        try {
          await _apiService.saveMemory(
            text:
                'Autonomous goal completed: ${base.goal}\nResult: $response',
            kind: 'autonomy_result',
            importance: 0.8,
          );
        } on Object {
          // Completion remains valid if remote memory is unavailable.
        }
        return;

      case 'BLOCKED':
        _emit(
          JarvisAutonomyState(
            status: JarvisAutonomyStatus.paused,
            goal: base.goal,
            step: base.step,
            maxSteps: base.maxSteps,
            lastResponse: response,
            errorMessage:
                'Jarvis needs user input or approval before continuing.',
          ),
        );
        await _persist();
        return;

      case 'CONTINUE':
        if (base.step >= base.maxSteps) {
          _emit(
            JarvisAutonomyState(
              status: JarvisAutonomyStatus.paused,
              goal: base.goal,
              step: base.step,
              maxSteps: base.maxSteps,
              lastResponse: response,
              errorMessage:
                  'Autonomy reached the configured step limit.',
            ),
          );
          await _persist();
          return;
        }

        await Future<void>.delayed(
          const Duration(milliseconds: 450),
        );

        await _dispatchStep(
          initial: false,
          nextAction: directive.nextAction,
        );
        return;
    }
  }

  Future<void> _dispatchStep({
    required bool initial,
    required String nextAction,
  }) async {
    if (_disposed ||
        _state.status == JarvisAutonomyStatus.paused) {
      return;
    }

    if (_state.step >= _state.maxSteps) {
      return;
    }

    final int nextStep = _state.step + 1;

    final String prompt = _buildAutonomyPrompt(
      goal: _state.goal,
      step: nextStep,
      maxSteps: _state.maxSteps,
      previousResponse:
          initial ? '' : _state.lastResponse,
      nextAction: nextAction,
    );

    _emit(
      JarvisAutonomyState(
        status: JarvisAutonomyStatus.waitingForResponse,
        goal: _state.goal,
        step: nextStep,
        maxSteps: _state.maxSteps,
        lastResponse: _state.lastResponse,
      ),
    );
    await _persist();

    final String? requestId =
        _chatController.askJarvis(prompt);

    if (requestId == null) {
      _emit(
        JarvisAutonomyState(
          status: JarvisAutonomyStatus.error,
          goal: _state.goal,
          step: nextStep,
          maxSteps: _state.maxSteps,
          lastResponse: _state.lastResponse,
          errorMessage:
              'Jarvis could not start the autonomous step.',
        ),
      );
      await _persist();
    }
  }

  String _buildAutonomyPrompt({
    required String goal,
    required int step,
    required int maxSteps,
    required String previousResponse,
    required String nextAction,
  }) {
    final String previous = previousResponse.trim().isEmpty
        ? 'None. This is the first execution step.'
        : previousResponse;

    return '''
JARVIS AUTONOMOUS EXECUTION MODE

Primary goal:
$goal

Execution step: $step of $maxSteps

Next action to pursue:
$nextAction

Previous step result:
$previous

Work toward the primary goal using the tools and device capabilities actually available to you. Perform low-risk reversible actions when the required tool is available. For consequential actions, use the existing approval flow instead of bypassing it. Never claim an external action succeeded unless a tool or device result confirms success. Do not invent capabilities, permissions, account access, device connections, or results.

At the end of this step output exactly these two control lines:
AUTONOMY_STATUS: CONTINUE
NEXT_ACTION: <the next concrete action>

Use AUTONOMY_STATUS: DONE when the goal is actually complete.
Use AUTONOMY_STATUS: BLOCKED when user input, permission, authentication, or approval is required.
''';
  }

  _AutonomyDirective? _parseDirective(String response) {
    final RegExp statusPattern = RegExp(
      r'AUTONOMY_STATUS\s*:\s*(CONTINUE|DONE|BLOCKED)',
      caseSensitive: false,
    );

    final RegExp nextPattern = RegExp(
      r'NEXT_ACTION\s*:\s*(.+)',
      caseSensitive: false,
    );

    final RegExpMatch? statusMatch =
        statusPattern.firstMatch(response);

    if (statusMatch == null) {
      return null;
    }

    final String status =
        statusMatch.group(1)!.toUpperCase();

    final RegExpMatch? nextMatch =
        nextPattern.firstMatch(response);

    final String nextAction =
        nextMatch?.group(1)?.trim() ?? '';

    if (status == 'CONTINUE' &&
        nextAction.isEmpty) {
      return null;
    }

    return _AutonomyDirective(
      status: status,
      nextAction: nextAction,
    );
  }

  Future<void> _restore() async {
    final String? goal =
        await _preferences.getString(_goalKey);

    if (_disposed ||
        goal == null ||
        goal.trim().isEmpty) {
      return;
    }

    final int step =
        await _preferences.getInt(_stepKey) ?? 0;
    final int maxSteps =
        await _preferences.getInt(_maxStepsKey) ?? 8;
    final String lastResponse =
        await _preferences.getString(
              _lastResponseKey,
            ) ??
            '';

    _emit(
      JarvisAutonomyState(
        status: JarvisAutonomyStatus.paused,
        goal: goal,
        step: step,
        maxSteps: maxSteps,
        lastResponse: lastResponse,
        errorMessage:
            'A previous autonomous goal is ready to resume.',
      ),
    );
  }

  Future<void> _persist() async {
    if (_state.goal.trim().isEmpty) {
      await _clearPersisted();
      return;
    }

    await _preferences.setString(
      _goalKey,
      _state.goal,
    );
    await _preferences.setInt(
      _stepKey,
      _state.step,
    );
    await _preferences.setInt(
      _maxStepsKey,
      _state.maxSteps,
    );
    await _preferences.setString(
      _lastResponseKey,
      _state.lastResponse,
    );
  }

  Future<void> _clearPersisted() async {
    await _preferences.remove(_goalKey);
    await _preferences.remove(_stepKey);
    await _preferences.remove(_maxStepsKey);
    await _preferences.remove(_lastResponseKey);
  }

  void _emit(JarvisAutonomyState next) {
    if (_disposed) {
      return;
    }

    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'JarvisAutonomyController has been disposed.',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await _chatSubscription?.cancel();
    _chatSubscription = null;
    await _stateController.close();
  }
}
