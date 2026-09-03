import 'dart:async';

class JarvisActionApprovalRequest {
  const JarvisActionApprovalRequest({
    required this.id,
    required this.title,
    required this.description,
    required this.action,
    required this.parameters,
  });

  final String id;
  final String title;
  final String description;
  final String action;
  final Map<String, dynamic> parameters;
}

class JarvisActionApprovalService {
  final StreamController<JarvisActionApprovalRequest>
      _requestController =
      StreamController<JarvisActionApprovalRequest>.broadcast();

  final Map<String, Completer<bool>> _pending =
      <String, Completer<bool>>{};

  Stream<JarvisActionApprovalRequest> get requests =>
      _requestController.stream;

  Future<bool> request(
    JarvisActionApprovalRequest request,
  ) async {
    final Completer<bool>? previous =
        _pending.remove(request.id);

    if (previous != null && !previous.isCompleted) {
      previous.complete(false);
    }

    final Completer<bool> completer =
        Completer<bool>();

    _pending[request.id] = completer;
    _requestController.add(request);

    try {
      return await completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => false,
      );
    } finally {
      _pending.remove(request.id);
    }
  }

  void resolve(
    String id,
    bool approved,
  ) {
    final Completer<bool>? completer =
        _pending.remove(id);

    if (completer == null ||
        completer.isCompleted) {
      return;
    }

    completer.complete(approved);
  }

  Future<void> dispose() async {
    for (final Completer<bool> completer
        in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }

    _pending.clear();
    await _requestController.close();
  }
}
