/// Date-time ISO 8601 helpers that keep server-side parsing unambiguous.
///
/// Dart's [DateTime.toIso8601String] omits the UTC offset for local
/// date-times (e.g. `2027-01-15T18:30:00.000`). The Node API runs in UTC on
/// Render, so a naive string used to be parsed as UTC and every Cairo
/// booking shifted by two hours. [iso8601WithOffset] always appends the
/// device's offset; [parseIso8601AsLocal] normalizes parsed instants back to
/// device-local time for display.
library;

/// Serializes [dt] as ISO 8601 with an explicit UTC offset.
String iso8601WithOffset(DateTime dt) {
  if (dt.isUtc) return dt.toIso8601String();
  final offset = dt.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hh = offset.inHours.abs().toString().padLeft(2, '0');
  final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${dt.toIso8601String()}$sign$hh:$mm';
}

/// Parses an ISO 8601 string (server sends UTC `...Z`) as device-local time
/// so formatted output matches what the user picked.
DateTime parseIso8601AsLocal(String raw) => DateTime.parse(raw).toLocal();
