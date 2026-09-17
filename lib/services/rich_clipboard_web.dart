// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Copies [htmlBody] as RICH text, so pasting into Outlook keeps the tables
/// and colours rather than arriving as a wall of markup.
///
/// Uses `dart:html` directly rather than `universal_html`, whose `Range` is an
/// empty stub with no `selectNodeContents`. That one missing method stopped
/// the whole test suite compiling — `widget_test.dart` imports main.dart,
/// which reaches this file — so no widget test could run at all.
bool copyRichHtml(String htmlBody) {
  html.DivElement? holder;
  try {
    holder = html.DivElement()
      ..innerHtml = htmlBody
      ..contentEditable = 'true'
      // Off-screen rather than display:none — a hidden element cannot be
      // selected, and an unselectable one cannot be copied.
      ..style.position = 'fixed'
      ..style.left = '-99999px'
      ..style.top = '0'
      ..style.opacity = '0';
    html.document.body!.append(holder);

    final range = html.document.createRange()..selectNodeContents(holder);
    final selection = html.window.getSelection();
    if (selection == null) return false;
    selection
      ..removeAllRanges()
      ..addRange(range);

    final ok = html.document.execCommand('copy');
    selection.removeAllRanges();
    return ok;
  } catch (_) {
    return false;
  } finally {
    holder?.remove();
  }
}
