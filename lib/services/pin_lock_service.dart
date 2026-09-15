import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Result of a PIN unlock attempt.
class PinUnlockResult {
  final bool ok;
  final String? email;
  final String? password;
  final int attemptsLeft;
  final bool wiped;
  final String? message;

  const PinUnlockResult({
    required this.ok,
    this.email,
    this.password,
    this.attemptsLeft = 0,
    this.wiped = false,
    this.message,
  });
}

/// A numeric PIN that unlocks a session already established on this device.
///
/// WHAT THIS IS NOT: the PIN does not authenticate to Supabase and is not a
/// password. Nothing here is compiled into the app — a PIN baked into the
/// bundle would be readable by anyone who opened the published JavaScript,
/// and would hand them whatever access the account has.
///
/// WHAT IT IS: the same shape as [BiometricService] — sign in once with a
/// real email and password, the credentials go into secure storage, and a
/// short local secret releases them afterwards. The PIN travels nowhere.
///
/// STRENGTH, honestly:
///   * On Android and iOS, flutter_secure_storage is backed by
///     EncryptedSharedPreferences and the Keychain, so the OS protects the
///     stored credentials and the PIN is a reasonable second factor.
///   * On WEB there is no keystore. Storage falls back to the browser, and
///     four digits is 10,000 guesses. Treat it as a convenience lock on a
///     machine you already control, never as a security boundary.
///
/// Two things blunt offline guessing: the verifier is salted and stretched
/// over many SHA-256 rounds, and [maxAttempts] failures wipe the stored
/// credentials so the only way back in is a full login.
class PinLockService {
  PinLockService._();
  static final PinLockService instance = PinLockService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kSalt     = 'pin_salt';
  static const _kVerifier = 'pin_verifier';
  static const _kEmail    = 'pin_email';
  static const _kPassword = 'pin_password';
  static const _kFailures = 'pin_failures';

  /// Failures before the stored credentials are destroyed.
  static const int maxAttempts = 5;

  /// PIN length the keypad enforces.
  static const int pinLength = 4;

  /// SHA-256 rounds. Four digits is only 10,000 possibilities, so the cost of
  /// a single guess is the only thing standing between a copied storage blob
  /// and the PIN. ~120k rounds puts a full sweep in the tens of minutes
  /// rather than under a second, while costing one unlock about 100 ms.
  static const int _rounds = 120000;

  String _stretch(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt|$pin');
    for (var i = 0; i < _rounds; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Encode(bytes);
  }

  String _newSalt() {
    final r = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  /// True when a PIN has been set on this device.
  Future<bool> isEnabled() async {
    try {
      return await _storage.read(key: _kVerifier) != null;
    } catch (_) {
      return false;
    }
  }

  /// Stores the PIN verifier and the credentials it releases.
  ///
  /// The caller must have just signed in successfully with these credentials —
  /// this method does not check them.
  Future<void> enable({
    required String pin,
    required String email,
    required String password,
  }) async {
    final salt = _newSalt();
    await _storage.write(key: _kSalt,     value: salt);
    await _storage.write(key: _kVerifier, value: _stretch(pin, salt));
    await _storage.write(key: _kEmail,    value: email);
    await _storage.write(key: _kPassword, value: password);
    await _storage.write(key: _kFailures, value: '0');
  }

  /// Removes the PIN and everything it released. Safe to call when unset.
  Future<void> disable() async {
    for (final k in [_kSalt, _kVerifier, _kEmail, _kPassword, _kFailures]) {
      try {
        await _storage.delete(key: k);
      } catch (e) {
        debugPrint('PinLockService.disable: $k -> $e');
      }
    }
  }

  Future<int> _failures() async =>
      int.tryParse(await _storage.read(key: _kFailures) ?? '0') ?? 0;

  /// Attempts left before the credentials are wiped.
  Future<int> attemptsLeft() async => maxAttempts - await _failures();

  /// Verifies [pin] and returns the credentials it releases.
  Future<PinUnlockResult> unlock(String pin) async {
    final verifier = await _storage.read(key: _kVerifier);
    final salt     = await _storage.read(key: _kSalt);
    if (verifier == null || salt == null) {
      return const PinUnlockResult(
          ok: false, message: 'No PIN is set on this device.');
    }

    if (_stretch(pin, salt) != verifier) {
      final failures = await _failures() + 1;
      if (failures >= maxAttempts) {
        await disable();
        return const PinUnlockResult(
          ok: false,
          wiped: true,
          message: 'Too many wrong attempts. The PIN has been removed — '
              'sign in with your email and password.',
        );
      }
      await _storage.write(key: _kFailures, value: '$failures');
      return PinUnlockResult(
        ok: false,
        attemptsLeft: maxAttempts - failures,
        message: 'Wrong PIN. ${maxAttempts - failures} attempts left.',
      );
    }

    await _storage.write(key: _kFailures, value: '0');
    return PinUnlockResult(
      ok: true,
      email: await _storage.read(key: _kEmail),
      password: await _storage.read(key: _kPassword),
      attemptsLeft: maxAttempts,
    );
  }
}
