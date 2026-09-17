/// Rich-text clipboard copy — the non-web implementation.
///
/// There is no DOM selection to copy through off the web, and no caller off
/// the web either: [EmailDraft] only reaches for this from a browser. Returns
/// false so the caller falls back to plain text.
bool copyRichHtml(String htmlBody) => false;
