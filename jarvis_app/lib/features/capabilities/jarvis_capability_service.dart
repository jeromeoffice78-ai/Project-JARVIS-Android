import 'dart:collection';
import 'dart:convert';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:health/health.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import 'jarvis_action_approval_service.dart';
import '../devices/jarvis_cloud_device_network.dart';
import '../printer/jarvis_print_router.dart';

class JarvisCapabilityResult {
  const JarvisCapabilityResult({
    required this.ok,
    this.result = const <String, dynamic>{},
    this.error,
  });

  final bool ok;
  final Map<String, dynamic> result;
  final String? error;
}

class JarvisCapabilityService {
  JarvisCapabilityService({
    required JarvisActionApprovalService approvalService,
    required JarvisPrintRouter printRouter,
    required JarvisCloudDeviceNetwork deviceNetwork,
    http.Client? httpClient,
  })  : _approvalService = approvalService,
        _printRouter = printRouter,
        _deviceNetwork = deviceNetwork,
        _httpClient = httpClient ?? http.Client() {
    tz_data.initializeTimeZones();
  }

  static const String _smartHomeWebhookKey =
      'jarvis.smart_home.webhook';

  final JarvisActionApprovalService _approvalService;
  final JarvisPrintRouter _printRouter;
  final JarvisCloudDeviceNetwork _deviceNetwork;
  final http.Client _httpClient;
  final DeviceCalendarPlugin _calendar =
      DeviceCalendarPlugin();
  final Health _health = Health();
  final SharedPreferencesAsync _preferences =
      SharedPreferencesAsync();

  Future<JarvisCapabilityResult> execute({
    required String requestId,
    required String callId,
    required String action,
    required Map<String, dynamic> parameters,
  }) async {
    try {
      switch (action) {
        case 'get_current_location':
          return _currentLocation();

        case 'open_navigation':
          return _openNavigation(parameters);

        case 'call_number':
          return _callNumber(parameters);

        case 'compose_sms':
          return _composeSms(parameters);

        case 'compose_email':
          return _composeEmail(parameters);

        case 'create_calendar_event':
          return _createCalendarEvent(
            requestId: requestId,
            callId: callId,
            parameters: parameters,
          );

        case 'get_health_summary':
          return _healthSummary();

        case 'trigger_smart_home_action':
          return _triggerSmartHome(
            requestId: requestId,
            callId: callId,
            parameters: parameters,
          );

        case 'open_web_url':
          return _openWebUrl(parameters);

        case 'create_and_print_document':
          return _createAndPrintDocument(parameters);

        case 'list_cloud_devices':
          return _listCloudDevices();

        case 'send_cloud_device_command':
          return _sendCloudDeviceCommand(
            parameters,
          );

        case 'broadcast_cloud_device_command':
          return _broadcastCloudDeviceCommand(
            parameters,
          );

        case 'handoff_jarvis_device':
          return _handoffJarvisDevice(
            parameters,
          );

        default:
          return JarvisCapabilityResult(
            ok: false,
            error:
                'Unsupported Jarvis capability: $action',
          );
      }
    } on Object catch (error) {
      return JarvisCapabilityResult(
        ok: false,
        error:
            'Capability execution failed: ${error.runtimeType}: $error',
      );
    }
  }

  Future<JarvisCapabilityResult> _currentLocation() async {
    final bool serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Location services are disabled on the device.',
      );
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission =
          await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission ==
            LocationPermission.deniedForever) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Location permission was not granted.',
      );
    }

    final Position position =
        await Geolocator.getCurrentPosition(
      locationSettings:
          const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );

    return JarvisCapabilityResult(
      ok: true,
      result: <String, dynamic>{
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy_meters':
            position.accuracy,
        'altitude_meters':
            position.altitude,
        'speed_mps': position.speed,
        'timestamp':
            position.timestamp.toIso8601String(),
      },
    );
  }

  Future<JarvisCapabilityResult> _openNavigation(
    Map<String, dynamic> parameters,
  ) async {
    final String destination =
        parameters['destination']
                ?.toString()
                .trim() ??
            '';

    if (destination.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error: 'Navigation destination is empty.',
      );
    }

    final Uri uri = Uri.https(
      'www.google.com',
      '/maps/dir/',
      <String, String>{
        'api': '1',
        'destination': destination,
      },
    );

    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    return JarvisCapabilityResult(
      ok: launched,
      result: <String, dynamic>{
        'destination': destination,
        'opened_external_navigation':
            launched,
      },
      error: launched
          ? null
          : 'Unable to open navigation.',
    );
  }

  Future<JarvisCapabilityResult> _callNumber(
    Map<String, dynamic> parameters,
  ) async {
    final String number =
        parameters['phone_number']
                ?.toString()
                .trim() ??
            '';

    if (number.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error: 'Phone number is empty.',
      );
    }

    final Uri uri = Uri(
      scheme: 'tel',
      path: number,
    );

    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    return JarvisCapabilityResult(
      ok: launched,
      result: <String, dynamic>{
        'phone_number': number,
        'dialer_opened': launched,
        'final_call_requires_user_action':
            true,
      },
      error: launched
          ? null
          : 'Unable to open the phone dialer.',
    );
  }

  Future<JarvisCapabilityResult> _composeSms(
    Map<String, dynamic> parameters,
  ) async {
    final String number =
        parameters['phone_number']
                ?.toString()
                .trim() ??
            '';

    final String message =
        parameters['message']
                ?.toString()
                .trim() ??
            '';

    if (number.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error: 'SMS recipient is empty.',
      );
    }

    final Uri uri = Uri(
      scheme: 'sms',
      path: number,
      queryParameters: message.isEmpty
          ? null
          : <String, String>{
              'body': message,
            },
    );

    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    return JarvisCapabilityResult(
      ok: launched,
      result: <String, dynamic>{
        'phone_number': number,
        'composer_opened': launched,
        'final_send_requires_user_action':
            true,
      },
      error: launched
          ? null
          : 'Unable to open the SMS composer.',
    );
  }

  Future<JarvisCapabilityResult> _composeEmail(
    Map<String, dynamic> parameters,
  ) async {
    final String to =
        parameters['to']?.toString().trim() ??
            '';

    final String subject =
        parameters['subject']
                ?.toString()
                .trim() ??
            '';

    final String body =
        parameters['body']?.toString() ?? '';

    if (to.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error: 'Email recipient is empty.',
      );
    }

    final Uri uri = Uri(
      scheme: 'mailto',
      path: to,
      queryParameters: <String, String>{
        if (subject.isNotEmpty)
          'subject': subject,
        if (body.isNotEmpty)
          'body': body,
      },
    );

    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    return JarvisCapabilityResult(
      ok: launched,
      result: <String, dynamic>{
        'recipient': to,
        'composer_opened': launched,
        'final_send_requires_user_action':
            true,
      },
      error: launched
          ? null
          : 'Unable to open the email composer.',
    );
  }

  Future<JarvisCapabilityResult> _createCalendarEvent({
    required String requestId,
    required String callId,
    required Map<String, dynamic> parameters,
  }) async {
    final String title =
        parameters['title']?.toString().trim() ??
            '';

    final DateTime? start =
        DateTime.tryParse(
      parameters['start_iso']?.toString() ??
          '',
    );

    final DateTime? end =
        DateTime.tryParse(
      parameters['end_iso']?.toString() ?? '',
    );

    final String notes =
        parameters['notes']?.toString() ?? '';

    if (title.isEmpty ||
        start == null ||
        end == null ||
        !end.isAfter(start)) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Calendar event parameters are invalid.',
      );
    }

    final bool approved =
        await _approvalService.request(
      JarvisActionApprovalRequest(
        id: '$requestId:$callId',
        title: 'Add calendar event?',
        description:
            '$title\n${start.toLocal()} → ${end.toLocal()}',
        action: 'create_calendar_event',
        parameters: parameters,
      ),
    );

    if (!approved) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Calendar event was not approved by the user.',
      );
    }

    final Result<bool> permissionResult =
        await _calendar.requestPermissions();

    if (!permissionResult.isSuccess ||
        permissionResult.data != true) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Calendar permission was not granted.',
      );
    }

    final Result<UnmodifiableListView<Calendar>>
        calendars =
        await _calendar.retrieveCalendars();

    final List<Calendar> writable =
        (calendars.data ?? UnmodifiableListView<Calendar>(
          const <Calendar>[],
        ))
            .where(
              (Calendar calendar) =>
                  calendar.isReadOnly != true,
            )
            .toList(growable: false);

    if (writable.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'No writable device calendar is available.',
      );
    }

    final Calendar calendar =
        writable.first;

    final Event event = Event(
      calendar.id,
      title: title,
      description: notes,
      start: tz.TZDateTime.from(
        start.toUtc(),
        tz.UTC,
      ),
      end: tz.TZDateTime.from(
        end.toUtc(),
        tz.UTC,
      ),
    );

    final Result<String>? result =
        await _calendar.createOrUpdateEvent(
      event,
    );

    final bool ok =
        result?.isSuccess == true &&
            result?.data != null;

    return JarvisCapabilityResult(
      ok: ok,
      result: <String, dynamic>{
        'calendar_name': calendar.name,
        'event_id': result?.data,
        'title': title,
      },
      error: ok
          ? null
          : 'Calendar event could not be created.',
    );
  }

  Future<JarvisCapabilityResult> _healthSummary() async {
    if (kIsWeb) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Health data is unavailable on the web.',
      );
    }

    await _health.configure();

    if (defaultTargetPlatform ==
        TargetPlatform.android) {
      final PermissionStatus activityPermission =
          await Permission.activityRecognition.request();

      if (!activityPermission.isGranted) {
        return const JarvisCapabilityResult(
          ok: false,
          error:
              'Activity recognition permission was not granted.',
        );
      }
    }

    final List<HealthDataType> types =
        <HealthDataType>[
      HealthDataType.STEPS,
      HealthDataType.HEART_RATE,
      HealthDataType.RESTING_HEART_RATE,
      HealthDataType.BLOOD_OXYGEN,
      HealthDataType.SLEEP_ASLEEP,
    ];

    final bool authorized =
        await _health.requestAuthorization(
      types,
    );

    if (!authorized) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Health access was not authorized.',
      );
    }

    final DateTime now = DateTime.now();
    final DateTime midnight =
        DateTime(
      now.year,
      now.month,
      now.day,
    );

    final int? steps =
        await _health.getTotalStepsInInterval(
      midnight,
      now,
    );

    final List<HealthDataPoint> points =
        await _health.getHealthDataFromTypes(
      types: <HealthDataType>[
        HealthDataType.HEART_RATE,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.BLOOD_OXYGEN,
        HealthDataType.SLEEP_ASLEEP,
      ],
      startTime:
          now.subtract(
        const Duration(hours: 24),
      ),
      endTime: now,
    );

    points.sort(
      (HealthDataPoint a, HealthDataPoint b) =>
          b.dateTo.compareTo(a.dateTo),
    );

    return JarvisCapabilityResult(
      ok: true,
      result: <String, dynamic>{
        'steps_today': steps ?? 0,
        'recent_samples': points
            .take(20)
            .map(
              (HealthDataPoint point) =>
                  point.toJson(),
            )
            .toList(growable: false),
        'source':
            defaultTargetPlatform ==
                    TargetPlatform.android
                ? 'Health Connect'
                : 'Apple Health',
      },
    );
  }

  Future<void> saveSmartHomeWebhook(
    String webhook,
  ) async {
    final String normalized =
        webhook.trim();

    if (normalized.isEmpty) {
      await _preferences.remove(
        _smartHomeWebhookKey,
      );
      return;
    }

    final Uri? uri =
        Uri.tryParse(normalized);

    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' &&
            uri.scheme != 'http')) {
      throw ArgumentError(
        'Smart-home webhook must be an HTTP or HTTPS URL.',
      );
    }

    await _preferences.setString(
      _smartHomeWebhookKey,
      normalized,
    );
  }

  Future<String?> getSmartHomeWebhook() {
    return _preferences.getString(
      _smartHomeWebhookKey,
    );
  }

  Future<JarvisCapabilityResult> _triggerSmartHome({
    required String requestId,
    required String callId,
    required Map<String, dynamic> parameters,
  }) async {
    final String actionName =
        parameters['action_name']
                ?.toString()
                .trim() ??
            '';

    if (actionName.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Smart-home action name is empty.',
      );
    }

    final String? webhook =
        await getSmartHomeWebhook();

    if (webhook == null ||
        webhook.trim().isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'No smart-home webhook is configured.',
      );
    }

    final bool approved =
        await _approvalService.request(
      JarvisActionApprovalRequest(
        id: '$requestId:$callId',
        title:
            'Run smart-home action?',
        description: actionName,
        action:
            'trigger_smart_home_action',
        parameters: parameters,
      ),
    );

    if (!approved) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Smart-home action was not approved by the user.',
      );
    }

    final http.Response response =
        await _httpClient
            .post(
              Uri.parse(webhook),
              headers:
                  const <String, String>{
                'content-type':
                    'application/json',
              },
              body: jsonEncode(
                <String, dynamic>{
                  'action':
                      actionName,
                  'parameters':
                      parameters,
                  'source':
                      'project_jarvis',
                },
              ),
            )
            .timeout(
              const Duration(
                seconds: 12,
              ),
            );

    final bool ok =
        response.statusCode >= 200 &&
            response.statusCode < 300;

    return JarvisCapabilityResult(
      ok: ok,
      result: <String, dynamic>{
        'action_name': actionName,
        'http_status':
            response.statusCode,
      },
      error: ok
          ? null
          : 'Smart-home webhook returned HTTP ${response.statusCode}.',
    );
  }

  Future<JarvisCapabilityResult> _createAndPrintDocument(
    Map<String, dynamic> parameters,
  ) async {
    final String title =
        parameters['title']?.toString().trim() ??
            'Jarvis Document';

    final String body =
        parameters['document_text']
                ?.toString()
                .trim() ??
            parameters['body']
                ?.toString()
                .trim() ??
            '';

    final int copies =
        ((parameters['copies'] as num?)
                    ?.toInt()
                    .clamp(1, 99) ??
                1)
            .toInt();

    if (body.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'The generated document has no printable content.',
      );
    }

    try {
      final JarvisPrintRouteResult route =
          await _printRouter.queueDocument(
        title: title.isEmpty
            ? 'Jarvis Document'
            : title,
        text: body,
        copies: copies,
      );

      return JarvisCapabilityResult(
        ok: true,
        result: <String, dynamic>{
          'job_id': route.jobId,
          'target_device_id':
              route.targetDeviceId,
          'target_device_name':
              route.targetDeviceName,
          'printer_name': route.printerName,
          'status': 'queued',
          'verification':
              'The job was routed to a live printer-host device. Physical printing is confirmed separately by Android/printer status.',
        },
      );
    } on Object catch (error) {
      return JarvisCapabilityResult(
        ok: false,
        error:
            'Jarvis could not route the document to an available printer: $error',
      );
    }
  }

  Future<JarvisCapabilityResult>
      _listCloudDevices() async {
    await _deviceNetwork.refreshDevices();

    final List<Map<String, dynamic>> devices =
        _deviceNetwork.state.devices
            .map(
              (JarvisCloudDevice device) =>
                  <String, dynamic>{
                'device_id': device.deviceId,
                'device_name':
                    device.deviceName,
                'online': device.online,
                'foreground':
                    device.foreground,
                'active_avatar':
                    device.activeAvatar,
                'capabilities':
                    device.capabilities,
              },
            )
            .toList(growable: false);

    return JarvisCapabilityResult(
      ok: true,
      result: <String, dynamic>{
        'this_device_id':
            _deviceNetwork.state.deviceId,
        'devices': devices,
      },
    );
  }

  Future<JarvisCapabilityResult>
      _sendCloudDeviceCommand(
    Map<String, dynamic> parameters,
  ) async {
    final JarvisCloudDevice? target =
        await _resolveCloudDevice(
      parameters,
    );

    if (target == null) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'No unique online Jarvis device matched the requested target.',
      );
    }

    final String action =
        parameters['action']
                ?.toString()
                .trim() ??
            '';

    final Map<String, dynamic> commandParams =
        parameters['parameters'] is Map
            ? Map<String, dynamic>.from(
                parameters['parameters'] as Map,
              )
            : const <String, dynamic>{};

    if (action.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Cloud device command action is empty.',
      );
    }

    final String commandId =
        await _deviceNetwork.sendCommand(
      targetDeviceId: target.deviceId,
      action: action,
      parameters: commandParams,
    );

    return JarvisCapabilityResult(
      ok: commandId.isNotEmpty,
      result: <String, dynamic>{
        'command_id': commandId,
        'target_device_id':
            target.deviceId,
        'target_device_name':
            target.deviceName,
        'action': action,
        'status': 'queued',
      },
      error: commandId.isEmpty
          ? 'Cloud command could not be queued.'
          : null,
    );
  }

  Future<JarvisCapabilityResult>
      _broadcastCloudDeviceCommand(
    Map<String, dynamic> parameters,
  ) async {
    final String action =
        parameters['action']
                ?.toString()
                .trim() ??
            '';

    final Map<String, dynamic> commandParams =
        parameters['parameters'] is Map
            ? Map<String, dynamic>.from(
                parameters['parameters'] as Map,
              )
            : const <String, dynamic>{};

    if (action.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Cloud broadcast action is empty.',
      );
    }

    final List<String> ids =
        await _deviceNetwork.broadcastCommand(
      action: action,
      parameters: commandParams,
    );

    return JarvisCapabilityResult(
      ok: true,
      result: <String, dynamic>{
        'action': action,
        'command_ids': ids,
        'queued_count': ids.length,
      },
    );
  }

  Future<JarvisCapabilityResult>
      _handoffJarvisDevice(
    Map<String, dynamic> parameters,
  ) async {
    final JarvisCloudDevice? target =
        await _resolveCloudDevice(
      parameters,
    );

    if (target == null) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'No unique online Jarvis device matched the requested handoff target.',
      );
    }

    final String commandId =
        await _deviceNetwork.handoffJarvisTo(
      target.deviceId,
    );

    return JarvisCapabilityResult(
      ok: commandId.isNotEmpty,
      result: <String, dynamic>{
        'command_id': commandId,
        'target_device_id':
            target.deviceId,
        'target_device_name':
            target.deviceName,
        'status': 'handoff_queued',
      },
      error: commandId.isEmpty
          ? 'Jarvis handoff could not be queued.'
          : null,
    );
  }

  Future<JarvisCloudDevice?>
      _resolveCloudDevice(
    Map<String, dynamic> parameters,
  ) async {
    await _deviceNetwork.refreshDevices();

    final String requestedId =
        parameters['target_device_id']
                ?.toString()
                .trim() ??
            '';

    final String requestedName =
        parameters['target_device_name']
                ?.toString()
                .trim()
                .toLowerCase() ??
            '';

    final List<JarvisCloudDevice> online =
        _deviceNetwork.state.devices
            .where(
              (JarvisCloudDevice device) =>
                  device.online,
            )
            .toList(growable: false);

    if (requestedId.isNotEmpty) {
      final List<JarvisCloudDevice> matches =
          online
              .where(
                (JarvisCloudDevice device) =>
                    device.deviceId ==
                    requestedId,
              )
              .toList(growable: false);
      return matches.length == 1
          ? matches.single
          : null;
    }

    if (requestedName.isEmpty) {
      return null;
    }

    final List<JarvisCloudDevice> exact =
        online
            .where(
              (JarvisCloudDevice device) =>
                  device.deviceName
                      .toLowerCase() ==
                  requestedName,
            )
            .toList(growable: false);

    if (exact.length == 1) {
      return exact.single;
    }

    final List<JarvisCloudDevice> partial =
        online
            .where(
              (JarvisCloudDevice device) =>
                  device.deviceName
                      .toLowerCase()
                      .contains(
                        requestedName,
                      ),
            )
            .toList(growable: false);

    return partial.length == 1
        ? partial.single
        : null;
  }

  Future<JarvisCapabilityResult> _openWebUrl(
    Map<String, dynamic> parameters,
  ) async {
    final String rawUrl =
        parameters['url']?.toString().trim() ??
            '';

    final Uri? uri =
        Uri.tryParse(rawUrl);

    if (uri == null ||
        !(uri.scheme == 'https' ||
            uri.scheme == 'http')) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Only HTTP/HTTPS URLs can be opened.',
      );
    }

    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    return JarvisCapabilityResult(
      ok: launched,
      result: <String, dynamic>{
        'url': rawUrl,
        'opened': launched,
      },
      error: launched
          ? null
          : 'Unable to open URL.',
    );
  }

  void dispose() {
    _httpClient.close();
  }
}
