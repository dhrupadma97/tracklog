import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

/// Turning a composed report into something you can look at, and into a draft
/// Outlook will open with a Send button.
class EmailDraft {
  const EmailDraft._();

  /// Opens the rendered mail in a new browser tab so it can be read exactly as
  /// the recipient will see it.
  ///
  /// Returns null on success, or why it could not open.
  static String? openHtmlPreview(String htmlBody, {String? title}) {
    if (!kIsWeb) {
      return 'Preview opens in a browser tab — use the web app';
    }
    try {
      final page = '<!doctype html><html><head><meta charset="utf-8">'
          '<title>${_escape(title ?? 'Report preview')}</title>'
          '<style>body{margin:0;padding:28px;background:#f2f4f8;}'
          '.sheet{background:#fff;max-width:820px;margin:0 auto;padding:30px;'
          'border-radius:8px;box-shadow:0 1px 5px rgba(0,0,0,.12);}</style>'
          '</head><body><div class="sheet">$htmlBody</div></body></html>';

      final blob = html.Blob([page], 'text/html;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');
      // The blob has to outlive the tab opening; revoking immediately would
      // race the new window and leave it blank.
      Future.delayed(
          const Duration(minutes: 5), () => html.Url.revokeObjectUrl(url));
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Opens a new Outlook mail with the recipients and subject already set, and
  /// puts the formatted report on the clipboard so it pastes into the body.
  ///
  /// The body cannot be pre-filled with formatting: `mailto:` carries plain
  /// text only, and injecting HTML into a compose window needs an Outlook
  /// add-in or Graph API. So the mail opens with a readable plain-text summary
  /// already in it, and one paste replaces it with the full formatted version.
  ///
  /// Returns null on success, or why it failed.
  static Future<String?> composeInOutlook({
    required String to,
    required List<String> cc,
    required String subject,
    required String htmlBody,
    required String plainBody,
  }) async {
    if (!kIsWeb) {
      return 'Composing in Outlook works from the web app';
    }
    try {
      final copied = _copyRichText(htmlBody);

      // Keep the mailto under what Windows will accept on a command line —
      // beyond roughly 2,000 characters Outlook silently drops the body.
      var body = plainBody;
      const limit = 1600;
      if (body.length > limit) {
        body = '${body.substring(0, limit)}\n\n'
            '[…full report is on your clipboard — press Ctrl+V to paste it]';
      }

      final uri = Uri(
        scheme: 'mailto',
        path: to,
        queryParameters: {
          if (cc.isNotEmpty) 'cc': cc.join(','),
          'subject': subject,
          'body': body,
        },
      );

      html.window.location.href = uri.toString();

      return copied
          ? null
          : 'Outlook opened, but the formatted version could not be copied — '
              'your browser blocked clipboard access';
    } catch (e) {
      return '$e';
    }
  }

  /// Copies [htmlBody] as rich text via a hidden contenteditable selection, so
  /// pasting into Outlook keeps the tables and colours rather than arriving as
  /// a wall of markup.
  static bool _copyRichText(String htmlBody) {
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

  /// Builds an RFC-822 message and hands it to the OS.
  ///
  /// The `X-Unsent: 1` header is the important part: Outlook opens a .eml
  /// carrying it as an editable draft with a Send button, rather than as a
  /// received message. So the mail can be reviewed, edited and sent by hand
  /// from the real mail client, with the HTML intact.
  ///
  /// Returns null on success, or why it failed.
  static Future<String?> openInOutlook({
    required String to,
    required List<String> cc,
    required String subject,
    required String htmlBody,
    String fileName = 'management-update',
  }) async {
    try {
      final eml = _buildEml(
        to: to,
        cc: cc,
        subject: subject,
        htmlBody: htmlBody,
      );
      final bytes = Uint8List.fromList(utf8.encode(eml));
      final safeName = '${fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}'
          '.eml';

      if (kIsWeb) {
        final blob = html.Blob([bytes], 'message/rfc822');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', safeName)
          ..click();
        // Give the browser a moment to start the download before revoking.
        Future.delayed(const Duration(seconds: 20),
            () => html.Url.revokeObjectUrl(url));
        return null;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes);
      final result = await OpenFile.open(file.path);
      return result.type == ResultType.done ? null : result.message;
    } catch (e) {
      return '$e';
    }
  }

  // ── MIME ───────────────────────────────────────────────────────────────────

  static String _buildEml({
    required String to,
    required List<String> cc,
    required String subject,
    required String htmlBody,
  }) {
    // Base64 for both subject and body so the rupee sign, em dashes and any
    // other non-ASCII survive whatever the mail client does with them.
    final encodedSubject =
        '=?UTF-8?B?${base64.encode(utf8.encode(subject))}?=';
    final encodedBody = _wrap76(base64.encode(utf8.encode(htmlBody)));

    final headers = <String>[
      'To: $to',
      if (cc.isNotEmpty) 'Cc: ${cc.join(', ')}',
      'Subject: $encodedSubject',
      'X-Unsent: 1', // opens as an editable draft in Outlook
      'MIME-Version: 1.0',
      'Content-Type: text/html; charset=UTF-8',
      'Content-Transfer-Encoding: base64',
    ];

    return '${headers.join('\r\n')}\r\n\r\n$encodedBody\r\n';
  }

  /// Base64 in a MIME body must be wrapped; long single lines get mangled.
  static String _wrap76(String s) {
    final out = StringBuffer();
    for (var i = 0; i < s.length; i += 76) {
      out.write(s.substring(i, i + 76 > s.length ? s.length : i + 76));
      out.write('\r\n');
    }
    return out.toString().trimRight();
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
