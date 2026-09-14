/// Which session statuses count as work done.
///
/// Manual entry offers three: Completed, Warning and Active. Every billing and
/// reporting query filtered on `session_status = 'completed'` alone — ten call
/// sites, each with its own copy of the string — so a session saved as Warning
/// vanished from the Analyser, the PO tracker, the invoice totals, the manager
/// report and the e-mail reports at once, with nothing anywhere saying a row
/// had been dropped. The track was booked and NATRAX billed for it either way.
///
/// Warning is a completed session carrying a note of concern, not an
/// incomplete one, so it belongs in the totals. Active is a session still
/// running: its duration and cost are not final, and counting it would bill
/// time that has not been used yet.
///
/// One list, so the rule cannot drift between the screen a figure is read on
/// and the report it is mailed in.
const List<String> kBillableSessionStatuses = ['completed', 'warning'];

/// A session that is finished but flagged. Worth calling out where a view can
/// show it, since the flag was put there deliberately.
const String kWarningSessionStatus = 'warning';
