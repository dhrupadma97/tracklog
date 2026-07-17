import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricService {
  BiometricService._privateConstructor();
  static final BiometricService instance = BiometricService._privateConstructor();

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _keyEmail = 'biometric_email';
  static const String _keyPassword = 'biometric_password';
  static const String _keyEnabled = 'biometric_enabled';

  /// Check if the device has biometric hardware and is enrolled
  Future<bool> canAuthenticate() async {
    if (kIsWeb) return false;
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool isDeviceSupported = await _auth.isDeviceSupported();
      if (!canAuthenticateWithBiometrics || !isDeviceSupported) {
        return false;
      }
      final List<BiometricType> availableBiometrics = await _auth.getAvailableBiometrics();
      return availableBiometrics.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking biometrics support: $e');
      return false;
    }
  }

  /// Check if the device hardware supports biometric authentication
  Future<bool> isHardwareSupported() async {
    if (kIsWeb) return false;
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      final bool isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (e) {
      debugPrint('Error checking hardware support: $e');
      return false;
    }
  }

  /// Check if any biometric credentials are enrolled on the device
  Future<bool> hasEnrolledBiometrics() async {
    if (kIsWeb) return false;
    try {
      final List<BiometricType> enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking enrolled biometrics: $e');
      return false;
    }
  }

  /// Check if user has explicitly enabled biometric authentication for this app
  Future<bool> isEnabled() async {
    if (kIsWeb) return false;
    final enabledStr = await _secureStorage.read(key: _keyEnabled);
    return enabledStr == 'true';
  }

  /// Set the biometric authorization setting (enabled or disabled)
  Future<void> setEnabled(bool enabled) async {
    if (kIsWeb) return;
    await _secureStorage.write(key: _keyEnabled, value: enabled.toString());
  }

  /// Triggers the biometric prompt dialog on Android/iOS
  Future<bool> authenticate({String reason = 'Authenticate to unlock TrackLog'}) async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
      return false;
    }
  }

  /// Securely save credentials to Android KeyStore / iOS Keychain
  Future<void> saveCredentials(String email, String password) async {
    if (kIsWeb) return;
    await _secureStorage.write(key: _keyEmail, value: email);
    await _secureStorage.write(key: _keyPassword, value: password);
    await _secureStorage.write(key: _keyEnabled, value: 'true');
  }

  /// Retrieve cached credentials
  Future<Map<String, String>?> getSavedCredentials() async {
    if (kIsWeb) return null;
    final email = await _secureStorage.read(key: _keyEmail);
    final password = await _secureStorage.read(key: _keyPassword);
    if (email != null && password != null) {
      return {'email': email, 'password': password};
    }
    return null;
  }

  /// Securely delete cached credentials
  Future<void> clearCredentials() async {
    if (kIsWeb) return;
    await _secureStorage.delete(key: _keyEmail);
    await _secureStorage.delete(key: _keyPassword);
    await _secureStorage.write(key: _keyEnabled, value: 'false');
  }
}
