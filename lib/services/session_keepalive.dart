import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

import 'supabase_service.dart';

/// Keeps the Supabase access token alive across long idle stretches.
///
/// `autoRefreshToken` schedules its renewal on a Dart `Timer`, which the
/// browser throttles in a background tab and suspends outright while the
/// machine sleeps. A tab left open overnight therefore wakes holding a dead
/// access token: `currentUser` is still populated from local storage so
/// nothing looks signed out, but every PostgREST call answers 401 - and a
/// screen that swallows those errors just renders empty.
///
/// This watches for the app coming back to the foreground and renews the
/// token before the screens query again.
class SessionKeepalive with WidgetsBindingObserver {
  static SessionKeepalive? _instance;
  static SessionKeepalive get instance => _instance ??= SessionKeepalive._();
  SessionKeepalive._();

  /// Renew this far ahead of the real expiry, so a query fired straight
  /// after a resume is not racing it.
  static const Duration _expiryGuard = Duration(minutes: 5);

  /// Ignore a resume landing this soon after the previous one. The lifecycle
  /// observer and the web visibility listener both report the same tab
  /// switch, and either can fire twice.
  static const Duration _debounce = Duration(seconds: 10);

  final StreamController<void> _refreshed = StreamController<void>.broadcast();

  /// Fires once a resume has put a usable token back in place. Screens that
  /// load their data once in `initState` can listen and reload, rather than
  /// stranding the user on whatever the expired token left on screen.
  Stream<void> get onSessionRefreshed => _refreshed.stream;

  bool _started = false;
  bool _refreshing = false;
  DateTime? _lastAttempt;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    // Flutter web does translate `visibilitychange` into lifecycle states,
    // but only once the engine is scheduling frames again. Reading the
    // document directly gets the renewal under way a beat earlier.
    if (kIsWeb) {
      html.document.onVisibilityChange.listen((_) {
        if (html.document.visibilityState == 'visible') _onResumed();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResumed();
  }

  void _onResumed() {
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < _debounce) return;
    _lastAttempt = DateTime.now();
    unawaited(refreshIfStale());
  }

  /// Renews the session when the access token has expired or is about to.
  /// Returns true when a usable token is in place afterwards.
  Future<bool> refreshIfStale() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      // Inside the try: main() tolerates a failed Supabase.initialize, and
      // reaching for the client after that throws.
      final auth = SupabaseService.instance.client.auth;
      final session = auth.currentSession;
      if (session == null) return false;
      if (!_isStale(session)) return true;

      await auth.refreshSession();
      if (!_refreshed.isClosed) _refreshed.add(null);
      return true;
    } on AuthException catch (e) {
      // The refresh token itself is spent or revoked, so there is nothing
      // left to renew. Sign out so the session stops reading as valid - the
      // router's refreshListenable then routes to login instead of leaving
      // the user parked on a shell that cannot load anything.
      debugPrint('Session refresh rejected, signing out: ${e.message}');
      await SupabaseService.instance.client.auth.signOut();
      return false;
    } catch (e) {
      // Offline, or the auth endpoint is unreachable. Leave the session
      // alone and let the next resume try again.
      debugPrint('Session refresh failed: $e');
      return false;
    } finally {
      _refreshing = false;
    }
  }

  bool _isStale(Session session) {
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return true;
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    return DateTime.now().isAfter(expiry.subtract(_expiryGuard));
  }
}
