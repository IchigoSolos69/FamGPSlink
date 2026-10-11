import 'package:flutter/services.dart';

class LocationBridge {
  static const _channel = MethodChannel('com.famgpslink/location');

  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
    await _channel.invokeMapMethod<String, dynamic>('status') ?? {},
  );

  Future<void> foregroundPermission() =>
      _channel.invokeMethod('requestForeground');
  Future<void> backgroundPermission() =>
      _channel.invokeMethod('requestBackground');
  Future<void> openSettings() => _channel.invokeMethod('openSettings');
  Future<void> start(String memberId) =>
      _channel.invokeMethod('start', {'memberId': memberId});
  Future<void> stop() => _channel.invokeMethod('stop');
  Future<Map<String, dynamic>> freshFix() async => Map<String, dynamic>.from(
    await _channel.invokeMapMethod<String, dynamic>('freshFix') ?? {},
  );
}
