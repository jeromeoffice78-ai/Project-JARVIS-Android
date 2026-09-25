import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/jarvis_chairman_auth.dart';
import '../../core/config/jarvis_config.dart';
import '../../core/protocol/jarvis_protocol.dart';
import 'jarvis_printer_service.dart';

final class JarvisPrintRouteResult {
  const JarvisPrintRouteResult({
    required this.jobId,
    required this.targetDeviceId,
    required this.targetDeviceName,
    required this.printerName,
  });

  final String jobId;
  final String targetDeviceId;
  final String targetDeviceName;
  final String printerName;
}

class JarvisPrintRouter {
  JarvisPrintRouter({
    required JarvisConfig config,
    required JarvisPrinterService printerService,
    http.Client? client,
  })  : _config = config,
        _printerService = printerService,
        _client = client ?? http.Client() {
    unawaited(start());
  }

  static const String _deviceIdKey =
      'jarvis.print.device_id';

  final JarvisConfig _config;
  final JarvisPrinterService _printerService;
  final http.Client _client;
  final SharedPreferencesAsync _preferences =
      SharedPreferencesAsync();

  Timer? _heartbeatTimer;
  Timer? _pollTimer;
  String? _deviceId;
  String? _deviceName;
  bool _started = false;
  bool _disposed = false;
  bool _polling = false;

  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;

  String get _authToken {
    final String session =
        JarvisAuthSession.currentToken;
    return session.isNotEmpty
        ? session
        : _config.clientToken.trim();
  }

  bool get isCloudRoutingConfigured =>
      _authToken.isNotEmpty &&
      _config.printGatewayUrl.trim().isNotEmpty;

  // A signed production install may open in local mode before Google
  // authentication. Starting again after sign-in must activate routing.
  Future<void> start() async {
    if (_disposed) return;

    if (!_started) {
      _started = true;
      _deviceId = await _loadOrCreateDeviceId();
      _deviceName = await _printerService.getDeviceName();
    }

    if (!isCloudRoutingConfigured ||
        _deviceId == null ||
        _deviceId!.isEmpty) {
      return;
    }

    if (_heartbeatTimer != null) return;

    await refreshHeartbeat();
    await pollForAssignedJobs();

    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(refreshHeartbeat()),
    );
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(pollForAssignedJobs()),
    );
  }

  Future<JarvisPrintRouteResult> queueDocument({
    required String title,
    required String text,
    int copies = 1,
    String mimeType = 'text/plain',
  }) async {
    _ensureReady();

    final String normalizedTitle = title.trim();
    final String normalizedText = text.trim();

    if (normalizedTitle.isEmpty) {
      throw ArgumentError(
        'Document title cannot be empty.',
      );
    }

    if (normalizedText.isEmpty) {
      throw ArgumentError(
        'Document content cannot be empty.',
      );
    }

    final Map<String, dynamic> payload =
        await _post(<String, dynamic>{
      'operation': 'queue_print',
      'requested_from_device_id': _deviceId,
      'document_title': normalizedTitle,
      'document_text': normalizedText,
      'mime_type': mimeType,
      'copies': copies.clamp(1, 99),
    });

    final Map<String, dynamic> job =
        _asMap(payload['job']);
    final Map<String, dynamic> selectedDevice =
        _asMap(payload['selected_device']);

    return JarvisPrintRouteResult(
      jobId: job['id']?.toString() ?? '',
      targetDeviceId:
          selectedDevice['device_id']
                  ?.toString() ??
              '',
      targetDeviceName:
          selectedDevice['device_name']
                  ?.toString() ??
              'Android device',
      printerName:
          selectedDevice['printer_name']
                  ?.toString() ??
              'Printer',
    );
  }

  Future<void> refreshHeartbeat() async {
    if (_disposed ||
        !isCloudRoutingConfigured ||
        _deviceId == null) {
      return;
    }

    try {
      final List<JarvisPrinterDevice> printers =
          await _printerService.listUsbPrinters();

      final JarvisPrinterDevice? activePrinter =
          printers
              .where(
                (JarvisPrinterDevice device) =>
                    device.isPrinterClass ||
                    device.isHpDevice,
              )
              .firstOrNull;

      await _post(<String, dynamic>{
        'operation': 'heartbeat',
        'device_id': _deviceId,
        'device_name':
            _deviceName ?? 'Android device',
        'app_version': '1.2.0',
        'printer_ready':
            activePrinter != null,
        'printer_id':
            activePrinter?.deviceName,
        'printer_name':
            activePrinter?.displayName,
        'printer_transport':
            activePrinter == null
                ? null
                : 'usb_otg',
        'capabilities': <String, dynamic>{
          'text_print': true,
          'android_print_framework': true,
          'usb_printer_detection': true,
          'hp_usb_printer':
              activePrinter?.isHpDevice ?? false,
        },
      });
    } on Object {
      // Heartbeat failure should never crash Jarvis.
    }
  }

  Future<void> pollForAssignedJobs() async {
    if (_disposed ||
        _polling ||
        !isCloudRoutingConfigured ||
        _deviceId == null) {
      return;
    }

    _polling = true;

    try {
      final List<JarvisPrinterDevice> printers =
          await _printerService.listUsbPrinters();

      final bool printerReady = printers.any(
        (JarvisPrinterDevice device) =>
            device.isPrinterClass ||
            device.isHpDevice,
      );

      if (!printerReady) {
        return;
      }

      final Map<String, dynamic> payload =
          await _post(<String, dynamic>{
        'operation': 'claim_jobs',
        'device_id': _deviceId,
      });

      final Object? rawJobs = payload['jobs'];
      if (rawJobs is! List) {
        return;
      }

      for (final Object? raw in rawJobs) {
        if (raw is! Map) {
          continue;
        }

        final Map<String, dynamic> job =
            Map<String, dynamic>.from(raw);
        await _executeJob(job);
      }
    } on Object {
      // Polling retries automatically on the next interval.
    } finally {
      _polling = false;
    }
  }

  Future<void> _executeJob(
    Map<String, dynamic> job,
  ) async {
    final String jobId =
        job['id']?.toString() ?? '';
    final String title =
        job['document_title']?.toString() ??
        'Jarvis Document';
    final String text =
        job['document_text']?.toString() ??
        '';

    if (jobId.isEmpty || text.trim().isEmpty) {
      if (jobId.isNotEmpty) {
        await _updateJob(
          jobId,
          'failed',
          error:
              'The queued print job has no printable text.',
        );
      }
      return;
    }

    try {
      await _updateJob(jobId, 'printing');

      final String? androidPrintJobId =
          await _printerService.printTextDocument(
        title: title,
        text: text,
      );

      await _updateJob(
        jobId,
        'submitted',
        error: androidPrintJobId == null
            ? null
            : 'Android print job: ${androidPrintJobId}',
      );
    } on Object catch (error) {
      await _updateJob(
        jobId,
        'failed',
        error: error.toString(),
      );
    }
  }

  Future<void> _updateJob(
    String jobId,
    String status, {
    String? error,
  }) async {
    await _post(<String, dynamic>{
      'operation': 'update_job',
      'device_id': _deviceId,
      'job_id': jobId,
      'status': status,
      if (error != null) 'error': error,
    });
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> body,
  ) async {
    final http.Response response =
        await _client
            .post(
              Uri.parse(
                _config.printGatewayUrl,
              ),
              headers: <String, String>{
                'content-type':
                    'application/json',
                'authorization':
                    'Bearer $_authToken',
              },
              body: jsonEncode(body),
            )
            .timeout(
              const Duration(seconds: 15),
            );

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }

    final Map<String, dynamic> payload =
        decoded is Map
            ? Map<String, dynamic>.from(
                decoded,
              )
            : <String, dynamic>{};

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw StateError(
        payload['error']?.toString() ??
            'Print coordinator failed with HTTP ${response.statusCode}.',
      );
    }

    return payload;
  }

  Future<String> _loadOrCreateDeviceId() async {
    final String? existing =
        await _preferences.getString(
      _deviceIdKey,
    );

    if (existing != null &&
        existing.trim().isNotEmpty) {
      return existing.trim();
    }

    final String generated =
        generateUuidV4();

    await _preferences.setString(
      _deviceIdKey,
      generated,
    );

    return generated;
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  void _ensureReady() {
    if (_disposed) {
      throw StateError(
        'JarvisPrintRouter has been disposed.',
      );
    }

    if (!isCloudRoutingConfigured) {
      throw StateError(
        'Cross-device printing is not configured in this build.',
      );
    }

    if (_deviceId == null) {
      throw StateError(
        'Jarvis printer routing is still initializing.',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _heartbeatTimer?.cancel();
    _pollTimer?.cancel();
    _heartbeatTimer = null;
    _pollTimer = null;
    _client.close();
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
