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
import '../music/jarvis_music_service.dart';
import '../phone/jarvis_phone_service.dart';
import '../system/jarvis_device_repair_service.dart';
import '../system_control/jarvis_system_control_service.dart';
import '../vision/jarvis_vision_service.dart';
import '../voice/jarvis_voice_service.dart';
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
    required JarvisMusicService musicService,
    required JarvisVisionService visionService,
    required JarvisVoiceService voiceService,
    required JarvisPhoneService phoneService,
    required JarvisSystemControlService systemControlService,
    required JarvisDeviceRepairService deviceRepairService,
    http.Client? httpClient,
  })  : _approvalService = approvalService,
        _printRouter = printRouter,
        _deviceNetwork = deviceNetwork,
        _musicService = musicService,
        _visionService = visionService,
        _voiceService = voiceService,
        _phoneService = phoneService,
        _systemControlService = systemControlService,
        _deviceRepairService = deviceRepairService,
        _httpClient = httpClient ?? http.Client() {
    tz_data.initializeTimeZones();
  }

  static const String _smartHomeWebhookKey =
      'jarvis.smart_home.webhook';

  final JarvisActionApprovalService _approvalService;
  final JarvisPrintRouter _printRouter;
  final JarvisCloudDeviceNetwork _deviceNetwork;
  final JarvisMusicService _musicService;
  final JarvisVisionService _visionService;
  final JarvisVoiceService _voiceService;
  final JarvisPhoneService _phoneService;
  final JarvisSystemControlService _systemControlService;
  final JarvisDeviceRepairService _deviceRepairService;
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

        case 'play_music':
          return _playMusic(parameters);

        case 'pause_music':
          return _pauseMusic();

        case 'resume_music':
          return _resumeMusic();

        case 'vision_refresh':
          return _refreshVision();

        case 'speak_text':
          return _speakText(parameters);

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

        case 'phone_active_call':
          return _phoneActiveCall();

        case 'phone_answer_call':
          return _phoneControl(
            'answer',
          );

        case 'phone_reject_call':
          return _phoneControl(
            'reject',
          );

        case 'phone_end_call':
          return _phoneControl(
            'end',
          );

        case 'phone_set_mute':
          return _phoneSetMute(parameters);

        case 'phone_set_speaker':
          return _phoneSetSpeaker(parameters);

        case 'system_global_action':
          return _systemGlobalAction(
            parameters,
          );

        case 'system_type_text':
          return _systemTypeText(
            requestId: requestId,
            callId: callId,
            parameters: parameters,
          );

        case 'system_launch_app':
          return _systemLaunchApp(
            parameters,
          );

        case 'system_tap':
          return _systemTap(
            requestId: requestId,
            callId: callId,
            parameters: parameters,
          );

        case 'system_swipe':
          return _systemSwipe(
            requestId: requestId,
            callId: callId,
            parameters: parameters,
          );

        case 'device_diagnose':
          return _deviceDiagnose();

        case 'device_malware_scan':
          return _deviceMalwareScan();

        case 'device_repair':
          return _deviceRepair(parameters);

        case 'device_remove_suspicious_app':
          return _deviceRemoveSuspiciousApp(
            requestId: requestId,
            callId: callId,
            parameters: parameters,
          );

        case 'device_verify_app_removed':
          return _deviceVerifyAppRemoved(
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

  Future<JarvisCapabilityResult> _playMusic(
    Map<String, dynamic> parameters,
  ) async {
    final String query =
        parameters['query']?.toString().trim() ?? '';

    if (query.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error: 'Music query is empty.',
      );
    }

    final track =
        await _musicService.searchAndPlay(query);

    return JarvisCapabilityResult(
      ok: true,
      result: <String, dynamic>{
        'title': track.title,
        'author': track.author,
        'provider': track.provider,
        'video_id': track.videoId,
        'playing': true,
      },
    );
  }

  Future<JarvisCapabilityResult>
      _pauseMusic() async {
    await _musicService.pause();

    return const JarvisCapabilityResult(
      ok: true,
      result: <String, dynamic>{
        'paused': true,
      },
    );
  }

  Future<JarvisCapabilityResult>
      _resumeMusic() async {
    await _musicService.play();

    return const JarvisCapabilityResult(
      ok: true,
      result: <String, dynamic>{
        'playing': true,
      },
    );
  }

  Future<JarvisCapabilityResult>
      _refreshVision() async {
    if (!_visionService.isActive) {
      await _visionService.start();
    } else {
      await _visionService.refreshFrameNow();
    }

    return JarvisCapabilityResult(
      ok: _visionService.isActive,
      result: <String, dynamic>{
        'vision_active':
            _visionService.isActive,
        'frame_refreshed': true,
      },
      error: _visionService.isActive
          ? null
          : 'Camera vision did not become active.',
    );
  }

  Future<JarvisCapabilityResult> _speakText(
    Map<String, dynamic> parameters,
  ) async {
    final String text =
        parameters['text']?.toString().trim() ?? '';

    if (text.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error: 'Speech text is empty.',
      );
    }

    await _voiceService.speak(text);

    return JarvisCapabilityResult(
      ok: true,
      result: <String, dynamic>{
        'spoken': true,
        'text': text,
      },
    );
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

    if (commandId.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Cloud command could not be queued.',
      );
    }

    final JarvisCloudCommandResult
        verification =
        await _deviceNetwork.waitForCommand(
      commandId,
      timeout: const Duration(seconds: 25),
    );

    final bool completed =
        verification.completed;

    final String status = verification.timedOut
        ? 'pending_unverified'
        : verification.status;

    return JarvisCapabilityResult(
      ok: completed,
      result: <String, dynamic>{
        'command_id': commandId,
        'target_device_id':
            target.deviceId,
        'target_device_name':
            target.deviceName,
        'action': action,
        'status': status,
        'verified': verification.isTerminal &&
            !verification.timedOut,
        'target_result':
            verification.result,
      },
      error: completed
          ? null
          : verification.timedOut
              ? 'The target device accepted the command but did not report completion before the verification timeout.'
              : verification.error ??
                  'The target device reported that the command did not complete.',
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

    if (ids.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'No other online Jarvis devices were available for the broadcast.',
      );
    }

    final List<JarvisCloudCommandResult>
        verifications = await Future.wait(
      ids.map(
        (String id) =>
            _deviceNetwork.waitForCommand(
          id,
          timeout:
              const Duration(seconds: 25),
        ),
      ),
    );

    final int completedCount =
        verifications
            .where(
              (JarvisCloudCommandResult item) =>
                  item.completed,
            )
            .length;

    final int timedOutCount =
        verifications
            .where(
              (JarvisCloudCommandResult item) =>
                  item.timedOut,
            )
            .length;

    final List<Map<String, dynamic>>
        outcomes = verifications
            .map(
              (JarvisCloudCommandResult item) =>
                  <String, dynamic>{
                'command_id':
                    item.commandId,
                'status': item.timedOut
                    ? 'pending_unverified'
                    : item.status,
                'verified':
                    item.isTerminal &&
                        !item.timedOut,
                'result': item.result,
                if (item.error != null)
                  'error': item.error,
              },
            )
            .toList(growable: false);

    final bool allCompleted =
        completedCount == ids.length;

    return JarvisCapabilityResult(
      ok: allCompleted,
      result: <String, dynamic>{
        'action': action,
        'command_ids': ids,
        'target_count': ids.length,
        'completed_count':
            completedCount,
        'pending_unverified_count':
            timedOutCount,
        'outcomes': outcomes,
      },
      error: allCompleted
          ? null
          : 'One or more target devices did not verify successful completion.',
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

    if (commandId.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Jarvis handoff could not be queued.',
      );
    }

    final JarvisCloudCommandResult
        verification =
        await _deviceNetwork.waitForCommand(
      commandId,
      timeout: const Duration(seconds: 20),
    );

    final bool completed =
        verification.completed;

    return JarvisCapabilityResult(
      ok: completed,
      result: <String, dynamic>{
        'command_id': commandId,
        'target_device_id':
            target.deviceId,
        'target_device_name':
            target.deviceName,
        'status': verification.timedOut
            ? 'handoff_pending_unverified'
            : verification.status,
        'verified': verification.isTerminal &&
            !verification.timedOut,
        'target_result':
            verification.result,
      },
      error: completed
          ? null
          : verification.timedOut
              ? 'Jarvis handoff was queued, but the target device did not verify arrival before the timeout.'
              : verification.error ??
                  'The target device did not verify the Jarvis handoff.',
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

  Future<JarvisCapabilityResult>
      _phoneActiveCall() async {
    final JarvisActiveCall? call =
        await _phoneService.getActiveCall();

    if (call == null) {
      return const JarvisCapabilityResult(
        ok: true,
        result: <String, dynamic>{
          'active_call': false,
        },
      );
    }

    return JarvisCapabilityResult(
      ok: true,
      result: <String, dynamic>{
        'active_call': true,
        'phone_number': call.phoneNumber,
        'state': call.state,
        'incoming': call.isIncoming,
        'muted': call.isMuted,
        'audio_route': call.audioRoute,
      },
    );
  }

  Future<JarvisCapabilityResult> _phoneControl(
    String action,
  ) async {
    final bool ok = switch (action) {
      'answer' =>
        await _phoneService.answerActiveCall(),
      'reject' =>
        await _phoneService.rejectActiveCall(),
      'end' =>
        await _phoneService.disconnectActiveCall(),
      _ => false,
    };

    return JarvisCapabilityResult(
      ok: ok,
      result: <String, dynamic>{
        'action': action,
        'completed': ok,
      },
      error: ok
          ? null
          : 'Android could not complete the call action.',
    );
  }

  Future<JarvisCapabilityResult>
      _phoneSetMute(
    Map<String, dynamic> parameters,
  ) async {
    final bool muted =
        parameters['muted'] == true;
    final bool ok =
        await _phoneService.setMuted(muted);

    return JarvisCapabilityResult(
      ok: ok,
      result: <String, dynamic>{
        'muted': muted,
      },
      error: ok
          ? null
          : 'Android could not change call mute state.',
    );
  }

  Future<JarvisCapabilityResult>
      _phoneSetSpeaker(
    Map<String, dynamic> parameters,
  ) async {
    final bool enabled =
        parameters['enabled'] == true;
    final bool ok =
        await _phoneService.setSpeaker(
      enabled,
    );

    return JarvisCapabilityResult(
      ok: ok,
      result: <String, dynamic>{
        'speaker': enabled,
      },
      error: ok
          ? null
          : 'Android could not change call audio route.',
    );
  }

  Future<JarvisCapabilityResult>
      _systemGlobalAction(
    Map<String, dynamic> parameters,
  ) async {
    final String action =
        parameters['action']
                ?.toString()
                .trim() ??
            '';

    final bool ok =
        await _systemControlService
            .performGlobalAction(action);

    return JarvisCapabilityResult(
      ok: ok,
      result: <String, dynamic>{
        'action': action,
      },
      error: ok
          ? null
          : 'Android system action was unavailable.',
    );
  }

  Future<JarvisCapabilityResult>
      _systemTypeText({
    required String requestId,
    required String callId,
    required Map<String, dynamic> parameters,
  }) async {
    final String text =
        parameters['text']
                ?.toString() ??
            '';

    if (text.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error: 'Text input is empty.',
      );
    }

    final bool approved =
        await _approvalService.request(
      JarvisActionApprovalRequest(
        id: '$requestId:$callId',
        title:
            'Let Jarvis type into the focused field?',
        description: text,
        action: 'system_type_text',
        parameters: parameters,
      ),
    );

    if (!approved) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Text entry was not approved.',
      );
    }

    final bool ok =
        await _systemControlService
            .typeIntoFocusedField(text);

    return JarvisCapabilityResult(
      ok: ok,
      result: <String, dynamic>{
        'typed': ok,
        'character_count': text.length,
      },
      error: ok
          ? null
          : 'No editable focused field was available.',
    );
  }

  Future<JarvisCapabilityResult>
      _systemLaunchApp(
    Map<String, dynamic> parameters,
  ) async {
    final String packageName =
        parameters['package_name']
                ?.toString()
                .trim() ??
            '';

    if (packageName.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Android package name is empty.',
      );
    }

    final bool ok =
        await _systemControlService
            .launchAppPackage(packageName);

    return JarvisCapabilityResult(
      ok: ok,
      result: <String, dynamic>{
        'package_name': packageName,
        'opened': ok,
      },
      error: ok
          ? null
          : 'Android could not launch that package.',
    );
  }

  Future<JarvisCapabilityResult> _systemTap({
    required String requestId,
    required String callId,
    required Map<String, dynamic> parameters,
  }) async {
    final double? x =
        (parameters['x'] as num?)?.toDouble();
    final double? y =
        (parameters['y'] as num?)?.toDouble();

    if (x == null || y == null || x < 0 || y < 0) {
      return const JarvisCapabilityResult(
        ok: false,
        error: 'Tap coordinates are invalid.',
      );
    }

    final bool approved =
        await _approvalService.request(
      JarvisActionApprovalRequest(
        id: '$requestId:$callId',
        title: 'Let Jarvis tap the screen?',
        description:
            'Tap at screen coordinates (${x.toStringAsFixed(0)}, ${y.toStringAsFixed(0)}).',
        action: 'system_tap',
        parameters: parameters,
      ),
    );

    if (!approved) {
      return const JarvisCapabilityResult(
        ok: false,
        error: 'Screen tap was not approved.',
      );
    }

    final bool ok =
        await _systemControlService.tap(x: x, y: y);

    return JarvisCapabilityResult(
      ok: ok,
      result: <String, dynamic>{
        'x': x,
        'y': y,
        'tapped': ok,
      },
      error: ok
          ? null
          : 'Android could not perform the tap.',
    );
  }

  Future<JarvisCapabilityResult> _systemSwipe({
    required String requestId,
    required String callId,
    required Map<String, dynamic> parameters,
  }) async {
    final double? startX =
        (parameters['start_x'] as num?)?.toDouble();
    final double? startY =
        (parameters['start_y'] as num?)?.toDouble();
    final double? endX =
        (parameters['end_x'] as num?)?.toDouble();
    final double? endY =
        (parameters['end_y'] as num?)?.toDouble();
    final int durationMs =
        (((parameters['duration_ms'] as num?)
                    ?.toInt() ??
                350)
            .clamp(100, 5000))
            .toInt();

    if (<double?>[startX, startY, endX, endY]
            .any((double? value) => value == null || value < 0)) {
      return const JarvisCapabilityResult(
        ok: false,
        error: 'Swipe coordinates are invalid.',
      );
    }

    final bool approved =
        await _approvalService.request(
      JarvisActionApprovalRequest(
        id: '$requestId:$callId',
        title: 'Let Jarvis swipe the screen?',
        description:
            'Swipe from (${startX!.toStringAsFixed(0)}, ${startY!.toStringAsFixed(0)}) to (${endX!.toStringAsFixed(0)}, ${endY!.toStringAsFixed(0)}).',
        action: 'system_swipe',
        parameters: parameters,
      ),
    );

    if (!approved) {
      return const JarvisCapabilityResult(
        ok: false,
        error: 'Screen swipe was not approved.',
      );
    }

    final bool ok =
        await _systemControlService.swipe(
      startX: startX!,
      startY: startY!,
      endX: endX!,
      endY: endY!,
      durationMs: durationMs,
    );

    return JarvisCapabilityResult(
      ok: ok,
      result: <String, dynamic>{
        'start_x': startX,
        'start_y': startY,
        'end_x': endX,
        'end_y': endY,
        'duration_ms': durationMs,
        'swiped': ok,
      },
      error: ok
          ? null
          : 'Android could not perform the swipe.',
    );
  }

  Future<JarvisCapabilityResult>
      _deviceDiagnose() async {
    final Map<String, dynamic> diagnosis =
        await _deviceRepairService.diagnose();

    return JarvisCapabilityResult(
      ok: diagnosis['error'] == null,
      result: diagnosis,
      error: diagnosis['error']
          ?.toString(),
    );
  }

  Future<JarvisCapabilityResult>
      _deviceMalwareScan() async {
    final Map<String, dynamic> summary =
        await _deviceRepairService
            .malwareSummary();

    return JarvisCapabilityResult(
      ok: true,
      result: summary,
    );
  }

  Future<JarvisCapabilityResult>
      _deviceRepair(
    Map<String, dynamic> parameters,
  ) async {
    final String target =
        parameters['target']
                ?.toString()
                .trim()
                .toLowerCase() ??
            '';

    if (target.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Device repair target is empty.',
      );
    }

    final Map<String, dynamic> result =
        await _deviceRepairService
            .repairTarget(target);

    return JarvisCapabilityResult(
      ok: result['ok'] == true,
      result: result,
      error: result['ok'] == true
          ? null
          : result['error']
                  ?.toString() ??
              'JARVIS could not start that repair.',
    );
  }

  Future<JarvisCapabilityResult>
      _deviceRemoveSuspiciousApp({
    required String requestId,
    required String callId,
    required Map<String, dynamic> parameters,
  }) async {
    final String packageName =
        parameters['package_name']
                ?.toString()
                .trim() ??
            '';

    if (packageName.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Android package name is empty.',
      );
    }

    final bool installed =
        await _deviceRepairService
            .isPackageInstalled(
      packageName,
    );

    if (!installed) {
      return JarvisCapabilityResult(
        ok: true,
        result: <String, dynamic>{
          'package_name': packageName,
          'installed': false,
          'removed': true,
          'verification':
              'Package is not installed.',
        },
      );
    }

    final bool approved =
        await _approvalService.request(
      JarvisActionApprovalRequest(
        id: '$requestId:$callId',
        title:
            'Remove suspicious Android app?',
        description:
            'JARVIS will open Android\'s uninstall confirmation for $packageName. '
            'Android requires your final confirmation.',
        action:
            'device_remove_suspicious_app',
        parameters: parameters,
      ),
    );

    if (!approved) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Suspicious-app removal was not approved.',
      );
    }

    final bool opened =
        await _deviceRepairService
            .requestUninstall(
      packageName,
    );

    return JarvisCapabilityResult(
      ok: opened,
      result: <String, dynamic>{
        'package_name': packageName,
        'uninstall_prompt_opened':
            opened,
        'removed': false,
        'requires_android_confirmation':
            true,
        'verification_required':
            true,
      },
      error: opened
          ? null
          : 'Android could not open the uninstall confirmation.',
    );
  }

  Future<JarvisCapabilityResult>
      _deviceVerifyAppRemoved(
    Map<String, dynamic> parameters,
  ) async {
    final String packageName =
        parameters['package_name']
                ?.toString()
                .trim() ??
            '';

    if (packageName.isEmpty) {
      return const JarvisCapabilityResult(
        ok: false,
        error:
            'Android package name is empty.',
      );
    }

    final bool installed =
        await _deviceRepairService
            .isPackageInstalled(
      packageName,
    );

    return JarvisCapabilityResult(
      ok: true,
      result: <String, dynamic>{
        'package_name': packageName,
        'installed': installed,
        'removed': !installed,
      },
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
