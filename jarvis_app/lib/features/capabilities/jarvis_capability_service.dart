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
    http.Client? httpClient,
  })  : _approvalService = approvalService,
        _httpClient = httpClient ?? http.Client() {
    tz_data.initializeTimeZones();
  }

  static const String _smartHomeWebhookKey =
      'jarvis.smart_home.webhook';

  final JarvisActionApprovalService _approvalService;
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
