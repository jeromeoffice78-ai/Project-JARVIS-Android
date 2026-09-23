import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class JarvisPrinterDevice {
  const JarvisPrinterDevice({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    required this.manufacturer,
    required this.productName,
    required this.isPrinterClass,
    required this.isHpDevice,
  });

  final String deviceName;
  final int vendorId;
  final int productId;
  final String manufacturer;
  final String productName;
  final bool isPrinterClass;
  final bool isHpDevice;

  factory JarvisPrinterDevice.fromMap(
    Map<dynamic, dynamic> raw,
  ) {
    return JarvisPrinterDevice(
      deviceName:
          raw['deviceName']?.toString() ?? '',
      vendorId:
          (raw['vendorId'] as num?)?.toInt() ?? 0,
      productId:
          (raw['productId'] as num?)?.toInt() ?? 0,
      manufacturer:
          raw['manufacturer']?.toString() ?? '',
      productName:
          raw['productName']?.toString() ?? '',
      isPrinterClass:
          raw['isPrinterClass'] == true,
      isHpDevice:
          raw['isHpDevice'] == true,
    );
  }

  String get displayName {
    if (productName.trim().isNotEmpty) {
      return productName.trim();
    }
    if (isHpDevice) {
      return 'HP USB Printer';
    }
    return 'USB device';
  }
}

class JarvisPrinterService {
  static const MethodChannel _channel =
      MethodChannel('jarvis.printer');

  bool get isSupported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  Future<List<JarvisPrinterDevice>>
      listUsbPrinters() async {
    if (!isSupported) {
      return const <JarvisPrinterDevice>[];
    }

    try {
      final List<dynamic>? raw =
          await _channel.invokeMethod<List<dynamic>>(
        'listUsbPrinters',
      );
      if (raw == null) {
        return const <JarvisPrinterDevice>[];
      }
      return raw
          .whereType<Map>()
          .map(
            (Map item) =>
                JarvisPrinterDevice.fromMap(item),
          )
          .toList(growable: false);
    } on PlatformException {
      return const <JarvisPrinterDevice>[];
    }
  }

  Future<String> getDeviceName() async {
    if (!isSupported) {
      return 'Android device';
    }

    try {
      return await _channel.invokeMethod<String>(
            'getDeviceName',
          ) ??
          'Android device';
    } on PlatformException {
      return 'Android device';
    }
  }

  Future<String?> printTextDocument({
    required String title,
    required String text,
  }) async {
    if (!isSupported) {
      throw StateError(
        'Printing is only available on Android.',
      );
    }

    final String normalizedTitle = title.trim();
    final String normalizedText = text.trim();

    if (normalizedTitle.isEmpty ||
        normalizedText.isEmpty) {
      throw ArgumentError(
        'A printable title and document body are required.',
      );
    }

    return _channel.invokeMethod<String>(
      'printTextDocument',
      <String, dynamic>{
        'title': normalizedTitle,
        'text': normalizedText,
      },
    );
  }

  Future<void> openPrintSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>(
      'openPrintSettings',
    );
  }

  Future<void> printTestPage() async {
    if (!isSupported) {
      throw StateError(
        'Printing is only available on Android.',
      );
    }
    await _channel.invokeMethod<void>(
      'printTestPage',
    );
  }
}
