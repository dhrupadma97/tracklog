/// Rich-text clipboard copy, picked per platform at compile time.
///
/// `dart:html` only exists on the web, and `universal_html` cannot stand in
/// here because its `Range` class is an empty stub. A conditional export
/// keeps the web build working while letting the VM — and therefore
/// `flutter test` — compile at all.
library;

export 'rich_clipboard_stub.dart'
    if (dart.library.html) 'rich_clipboard_web.dart';
