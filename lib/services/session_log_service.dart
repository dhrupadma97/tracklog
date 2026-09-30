import 'package:flutter/foundation.dart';

/// Announces that the session register has changed.
///
/// A [ChangeNotifier] for the same reason `MusterService` is one: the screen
/// that writes a change is never the screen that shows it. Session History
/// loads in `initState` and had nothing telling it to look again, so an entry
/// saved in Manual Entry stayed invisible there.
///
/// Leaving the tab and coming back did not help either — the shell keeps each
/// branch alive, so the screen is not rebuilt and `initState` does not run a
/// second time. Only a browser reload, a change of programme or the scope
/// picker refetched. A session logged at 14:58 was still missing from History
/// at 18:24, which reads as data lost rather than a stale page.
///
/// Mirrors `ProjectManager` and `MusterService` deliberately: one singleton,
/// listeners attached in `initState` and dropped in `dispose`.
class SessionLogService extends ChangeNotifier {
  SessionLogService._();
  static SessionLogService? _instance;
  static SessionLogService get instance => _instance ??= SessionLogService._();

  /// Sessions, or the service lines hanging off them, have changed.
  ///
  /// Called by whoever wrote the change and only once the write has come back
  /// successful. Firing it before that would have listeners read the table
  /// back before the row is in it, and report the same staleness this exists
  /// to remove.
  void changed() => notifyListeners();
}
