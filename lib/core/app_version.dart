import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersion {
  static String _version = '1.0.0';
  static String _buildNumber = '1';

  static Future<void> initialize() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version.isNotEmpty ? info.version : '1.0.0';
      _buildNumber = info.buildNumber.isNotEmpty ? info.buildNumber : '1';
    } catch (e) {
      debugPrint('Failed to load package info: $e');
    }
  }

  static String get version => _version;
  static String get buildNumber => _buildNumber;
  static String get display => '$version+$buildNumber';
}
