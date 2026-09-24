import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

enum JarvisBluetoothConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

final class JarvisBluetoothDeviceState {
  const JarvisBluetoothDeviceState({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.connectionState,
    required this.isKnown,
    required this.isSystemDevice,
    this.error,
  });

  final String deviceId;
  final String name;
  final int? rssi;
  final JarvisBluetoothConnectionState connectionState;
  final bool isKnown;
  final bool isSystemDevice;
  final String? error;

  bool get isConnected =>
      connectionState ==
      JarvisBluetoothConnectionState.connected;
}

final class JarvisBluetoothState {
  const JarvisBluetoothState({
    required this.isSupported,
    required this.isReady,
    required this.isScanning,
    required this.devices,
    this.errorMessage,
  });

  const JarvisBluetoothState.initial()
      : isSupported = true,
        isReady = false,
        isScanning = false,
        devices = const <JarvisBluetoothDeviceState>[],
        errorMessage = null;

  final bool isSupported;
  final bool isReady;
  final bool isScanning;
  final List<JarvisBluetoothDeviceState> devices;
  final String? errorMessage;

  int get connectedCount =>
      devices.where((device) => device.isConnected).length;
}

class JarvisBluetoothManager {
  JarvisBluetoothManager() {
    UniversalBle.queueType = QueueType.perDevice;
    _scanSubscription =
        UniversalBle.scanStream.listen(_handleScanResult);
    _availabilitySubscription =
        UniversalBle.availabilityStream.listen(
      _handleAvailability,
    );
    unawaited(initialize());
  }

  static const String _knownDevicesKey =
      'jarvis.bluetooth.known_devices';

  final SharedPreferencesAsync _preferences =
      SharedPreferencesAsync();

  final StreamController<JarvisBluetoothState>
      _stateController =
      StreamController<JarvisBluetoothState>.broadcast();

  final Map<String, BleDevice> _devices =
      <String, BleDevice>{};
  final Map<String, JarvisBluetoothConnectionState>
      _connections =
      <String, JarvisBluetoothConnectionState>{};
  final Map<String, String> _errors =
      <String, String>{};
  final Map<String, StreamSubscription<bool>>
      _connectionSubscriptions =
      <String, StreamSubscription<bool>>{};
  final Set<String> _knownDeviceIds = <String>{};
  final Set<String> _manualDisconnectIds = <String>{};
  final Map<String, int> _reconnectAttempts = <String, int>{};
  final Map<String, Timer> _reconnectTimers = <String, Timer>{};

  static const int _maxReconnectAttempts = 5;

  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<AvailabilityState>?
      _availabilitySubscription;

  JarvisBluetoothState _state =
      const JarvisBluetoothState.initial();

  bool _disposed = false;
  bool _initialized = false;

  Stream<JarvisBluetoothState> get stateStream =>
      _stateController.stream;

  JarvisBluetoothState get state => _state;

  Future<void> initialize() async {
    if (_disposed || _initialized) {
      return;
    }

    _initialized = true;

    if (kIsWeb) {
      _emit(
        const JarvisBluetoothState(
          isSupported: true,
          isReady: true,
          isScanning: false,
          devices: <JarvisBluetoothDeviceState>[],
        ),
      );
      return;
    }

    try {
      final List<String>? known =
          await _preferences.getStringList(
        _knownDevicesKey,
      );

      if (known != null) {
        _knownDeviceIds.addAll(known);
      }

      await UniversalBle.requestPermissions(
        withAndroidFineLocation: true,
      );

      final AvailabilityState availability =
          await UniversalBle
              .getBluetoothAvailabilityState();

      final bool ready =
          availability == AvailabilityState.poweredOn;

      if (ready) {
        await _loadSystemDevices();
        unawaited(_reconnectKnownDevices());
      }

      _rebuildState(
        ready: ready,
        errorMessage: ready
            ? null
            : 'Bluetooth is not powered on.',
      );
    } on Object catch (error) {
      _rebuildState(
        ready: false,
        errorMessage:
            'Bluetooth initialization failed: $error',
      );
    }
  }

  Future<void> startScan() async {
    _ensureNotDisposed();

    try {
      await UniversalBle.requestPermissions(
        withAndroidFineLocation: true,
      );

      final AvailabilityState availability =
          await UniversalBle
              .getBluetoothAvailabilityState();

      if (availability != AvailabilityState.poweredOn) {
        _rebuildState(
          ready: false,
          errorMessage:
              'Turn on Bluetooth before scanning.',
        );
        return;
      }

      if (await UniversalBle.isScanning()) {
        _rebuildState(
          ready: true,
          scanning: true,
        );
        return;
      }

      _rebuildState(
        ready: true,
        scanning: true,
        errorMessage: null,
      );

      await UniversalBle.startScan();
    } on Object catch (error) {
      _rebuildState(
        scanning: false,
        errorMessage:
            'Bluetooth scan failed: $error',
      );
    }
  }

  Future<void> stopScan() async {
    _ensureNotDisposed();

    try {
      if (await UniversalBle.isScanning()) {
        await UniversalBle.stopScan();
      }
    } on Object {
      // State is still reset even if the platform scan is already gone.
    }

    _rebuildState(scanning: false);
  }

  Future<void> connect(String deviceId) async {
    _ensureNotDisposed();

    final String normalized = deviceId.trim();
    if (normalized.isEmpty) {
      return;
    }

    _manualDisconnectIds.remove(normalized);
    _reconnectTimers.remove(normalized)?.cancel();
    _reconnectAttempts.remove(normalized);

    final bool resumeScan = _state.isScanning;
    if (resumeScan) {
      await stopScan();
    }

    _connections[normalized] =
        JarvisBluetoothConnectionState.connecting;
    _errors.remove(normalized);
    _listenForConnection(normalized);
    _rebuildState();

    try {
      await _connectWithRetry(
        normalized,
        timeout: const Duration(seconds: 25),
      );

      _connections[normalized] =
          JarvisBluetoothConnectionState.connected;

      _knownDeviceIds.add(normalized);
      await _saveKnownDevices();

      _rebuildState();
    } on Object catch (error) {
      _connections[normalized] =
          JarvisBluetoothConnectionState.error;
      _errors[normalized] = error.toString();
      _rebuildState();
    } finally {
      if (resumeScan && !_disposed) {
        unawaited(startScan());
      }
    }
  }

  Future<void> connectMany(
    Iterable<String> deviceIds,
  ) async {
    _ensureNotDisposed();

    final List<String> unique = deviceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (unique.isEmpty) {
      return;
    }

    final bool resumeScan = _state.isScanning;
    if (resumeScan) {
      await stopScan();
    }

    for (final String id in unique) {
      _connections[id] =
          JarvisBluetoothConnectionState.connecting;
      _errors.remove(id);
      _listenForConnection(id);
    }
    _rebuildState();

    await Future.wait(
      unique.map(
        (String id) async {
          try {
            _manualDisconnectIds.remove(id);
            _reconnectTimers.remove(id)?.cancel();
            _reconnectAttempts.remove(id);
            await _connectWithRetry(
              id,
              timeout: const Duration(seconds: 25),
            );
            _connections[id] =
                JarvisBluetoothConnectionState.connected;
            _knownDeviceIds.add(id);
          } on Object catch (error) {
            _connections[id] =
                JarvisBluetoothConnectionState.error;
            _errors[id] = error.toString();
          }
          _rebuildState();
        },
      ),
    );

    await _saveKnownDevices();

    if (resumeScan && !_disposed) {
      unawaited(startScan());
    }
  }

  Future<void> disconnect(String deviceId) async {
    _ensureNotDisposed();

    final String normalized = deviceId.trim();
    if (normalized.isEmpty) {
      return;
    }

    _manualDisconnectIds.add(normalized);
    _reconnectTimers.remove(normalized)?.cancel();
    _reconnectAttempts.remove(normalized);

    try {
      await UniversalBle.disconnect(normalized);
    } on Object catch (error) {
      _errors[normalized] = error.toString();
    }

    _connections[normalized] =
        JarvisBluetoothConnectionState.disconnected;
    _rebuildState();
  }

  Future<void> forget(String deviceId) async {
    _ensureNotDisposed();

    await disconnect(deviceId);
    _knownDeviceIds.remove(deviceId);
    _manualDisconnectIds.remove(deviceId);
    _reconnectTimers.remove(deviceId)?.cancel();
    _reconnectAttempts.remove(deviceId);
    _errors.remove(deviceId);
    await _saveKnownDevices();
    _rebuildState();
  }

  Future<void> refreshSystemDevices() async {
    _ensureNotDisposed();

    try {
      await _loadSystemDevices();
      _rebuildState();
    } on Object catch (error) {
      _rebuildState(
        errorMessage:
            'Unable to refresh Bluetooth devices: $error',
      );
    }
  }

  Future<void> _loadSystemDevices() async {
    final List<BleDevice> systemDevices =
        await UniversalBle.getSystemDevices();

    for (final BleDevice device in systemDevices) {
      _devices[device.deviceId] = device;
      _connections[device.deviceId] =
          JarvisBluetoothConnectionState.connected;
      _knownDeviceIds.add(device.deviceId);
      _listenForConnection(device.deviceId);
    }

    await _saveKnownDevices();
  }

  Future<void> _reconnectKnownDevices() async {
    for (final String deviceId
        in _knownDeviceIds.toList(growable: false)) {
      if (_connections[deviceId] ==
          JarvisBluetoothConnectionState.connected) {
        continue;
      }

      _connections[deviceId] =
          JarvisBluetoothConnectionState.connecting;
      _listenForConnection(deviceId);
      _rebuildState();

      try {
        await _connectWithRetry(
          deviceId,
          autoConnect: true,
          timeout: const Duration(seconds: 12),
          attempts: 3,
        );
      } on Object catch (error) {
        _connections[deviceId] =
            JarvisBluetoothConnectionState.disconnected;
        _errors[deviceId] =
            'Waiting to reconnect: $error';
      }

      _rebuildState();
    }
  }


  Future<void> _connectWithRetry(
    String deviceId, {
    bool autoConnect = false,
    Duration timeout = const Duration(seconds: 20),
    int attempts = _maxReconnectAttempts,
  }) async {
    Object? lastError;

    for (int attempt = 1; attempt <= attempts; attempt++) {
      try {
        await UniversalBle.connect(
          deviceId,
          autoConnect: autoConnect,
          timeout: timeout,
        );
        _reconnectAttempts.remove(deviceId);
        _errors.remove(deviceId);
        return;
      } on Object catch (error) {
        lastError = error;
        _reconnectAttempts[deviceId] = attempt;
        _errors[deviceId] =
            'Connection attempt $attempt/$attempts failed: $error';
        _rebuildState();

        if (attempt < attempts) {
          await Future<void>.delayed(
            Duration(seconds: 2 * attempt),
          );
        }
      }
    }

    throw StateError(
      'Bluetooth connection failed after $attempts attempts: $lastError',
    );
  }

  void _scheduleReconnect(String deviceId) {
    if (_disposed ||
        _manualDisconnectIds.contains(deviceId) ||
        !_knownDeviceIds.contains(deviceId) ||
        _reconnectTimers.containsKey(deviceId)) {
      return;
    }

    final int previous =
        _reconnectAttempts[deviceId] ?? 0;
    final int next = previous + 1;
    _reconnectAttempts[deviceId] = next;

    final int delaySeconds =
        (next * 3).clamp(3, 30).toInt();

    _errors[deviceId] =
        'Connection lost. Jarvis will retry in ${delaySeconds}s.';
    _rebuildState();

    _reconnectTimers[deviceId] = Timer(
      Duration(seconds: delaySeconds),
      () async {
        _reconnectTimers.remove(deviceId);
        if (_disposed ||
            _manualDisconnectIds.contains(deviceId) ||
            !_knownDeviceIds.contains(deviceId)) {
          return;
        }

        _connections[deviceId] =
            JarvisBluetoothConnectionState.connecting;
        _rebuildState();

        try {
          await _connectWithRetry(
            deviceId,
            autoConnect: true,
            timeout: const Duration(seconds: 15),
            attempts: 2,
          );
          _connections[deviceId] =
              JarvisBluetoothConnectionState.connected;
          _errors.remove(deviceId);
        } on Object catch (error) {
          _connections[deviceId] =
              JarvisBluetoothConnectionState.disconnected;
          _errors[deviceId] =
              'Automatic reconnect failed: $error';
          _scheduleReconnect(deviceId);
        }

        _rebuildState();
      },
    );
  }

  void _listenForConnection(String deviceId) {
    if (_connectionSubscriptions
        .containsKey(deviceId)) {
      return;
    }

    _connectionSubscriptions[deviceId] =
        UniversalBle.connectionStream(deviceId).listen(
      (bool connected) {
        _connections[deviceId] = connected
            ? JarvisBluetoothConnectionState.connected
            : JarvisBluetoothConnectionState.disconnected;

        if (connected) {
          _errors.remove(deviceId);
          _knownDeviceIds.add(deviceId);
          _manualDisconnectIds.remove(deviceId);
          _reconnectAttempts.remove(deviceId);
          _reconnectTimers.remove(deviceId)?.cancel();
          unawaited(_saveKnownDevices());
        } else if (_knownDeviceIds.contains(deviceId) &&
            !_manualDisconnectIds.contains(deviceId)) {
          _scheduleReconnect(deviceId);
        }

        _rebuildState();
      },
      onError: (Object error) {
        _connections[deviceId] =
            JarvisBluetoothConnectionState.error;
        _errors[deviceId] = error.toString();
        _rebuildState();
      },
    );
  }

  void _handleScanResult(BleDevice device) {
    if (_disposed) {
      return;
    }

    _devices[device.deviceId] = device;
    _connections.putIfAbsent(
      device.deviceId,
      () => JarvisBluetoothConnectionState.disconnected,
    );

    _rebuildState();
  }

  void _handleAvailability(
    AvailabilityState availability,
  ) {
    if (_disposed) {
      return;
    }

    final bool ready =
        availability == AvailabilityState.poweredOn;

    _rebuildState(
      ready: ready,
      scanning: ready ? _state.isScanning : false,
      errorMessage:
          ready ? null : 'Bluetooth is not powered on.',
    );
  }

  Future<void> _saveKnownDevices() {
    return _preferences.setStringList(
      _knownDevicesKey,
      _knownDeviceIds.toList(growable: false),
    );
  }

  void _rebuildState({
    bool? ready,
    bool? scanning,
    String? errorMessage,
  }) {
    if (_disposed) {
      return;
    }

    final Set<String> ids = <String>{
      ..._devices.keys,
      ..._knownDeviceIds,
      ..._connections.keys,
    };

    final List<JarvisBluetoothDeviceState> snapshots =
        ids.map((String id) {
      final BleDevice? device = _devices[id];
      final String rawName =
          device?.name?.trim() ?? '';

      return JarvisBluetoothDeviceState(
        deviceId: id,
        name: rawName.isEmpty
            ? 'Bluetooth device'
            : rawName,
        rssi: device?.rssi,
        connectionState:
            _connections[id] ??
            JarvisBluetoothConnectionState.disconnected,
        isKnown: _knownDeviceIds.contains(id),
        isSystemDevice:
            device?.isSystemDevice ?? false,
        error: _errors[id],
      );
    }).toList(growable: false)
      ..sort(
        (
          JarvisBluetoothDeviceState a,
          JarvisBluetoothDeviceState b,
        ) {
          if (a.isConnected != b.isConnected) {
            return a.isConnected ? -1 : 1;
          }
          if (a.isKnown != b.isKnown) {
            return a.isKnown ? -1 : 1;
          }
          return a.name
              .toLowerCase()
              .compareTo(b.name.toLowerCase());
        },
      );

    _emit(
      JarvisBluetoothState(
        isSupported: true,
        isReady: ready ?? _state.isReady,
        isScanning:
            scanning ?? _state.isScanning,
        devices: snapshots,
        errorMessage:
            errorMessage ?? _state.errorMessage,
      ),
    );
  }

  void _emit(JarvisBluetoothState next) {
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
        'JarvisBluetoothManager has been disposed.',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    try {
      if (await UniversalBle.isScanning()) {
        await UniversalBle.stopScan();
      }
    } on Object {
      // Ignore shutdown errors.
    }

    await _scanSubscription?.cancel();
    await _availabilitySubscription?.cancel();

    for (final StreamSubscription<bool> subscription
        in _connectionSubscriptions.values) {
      await subscription.cancel();
    }

    for (final Timer timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
    _connectionSubscriptions.clear();
    await _stateController.close();
  }
}
