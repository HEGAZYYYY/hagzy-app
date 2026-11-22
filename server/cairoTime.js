// Africa/Cairo wall-clock timezone parsing utilities
const CAIRO_TZ = 'Africa/Cairo';

function cairoOffsetMinutes(instantUtc) {
  try {
    const dtf = new Intl.DateTimeFormat('en-US', {
      timeZone: CAIRO_TZ,
      hour12: false,
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
    });
    const parts = {};
    for (const p of dtf.formatToParts(instantUtc)) parts[p.type] = p.value;
    const asUtc = Date.UTC(
      Number(parts.year), Number(parts.month) - 1, Number(parts.day),
      Number(parts.hour) % 24, Number(parts.minute), Number(parts.second)
    );
    return Math.round((asUtc - instantUtc.getTime()) / 60000);
  } catch (_) {
    return 120; // fallback: standard-time Cairo offset (UTC+2)
  }
}

function parseClientTimestamp(raw) {
  const s = String(raw ?? '').trim();
  if (!s) return new Date(NaN);
  const hasExplicitOffset = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(s);
  if (hasExplicitOffset) return new Date(s);
  // Naive wall time -> Cairo local time (two passes to survive DST edges).
  const normalized = s.includes('T') ? s : s.replace(' ', 'T');
  const wallAsUtc = new Date(`${normalized}Z`);
  if (isNaN(wallAsUtc.getTime())) return new Date(s); // caller rejects via isNaN
  const off1 = cairoOffsetMinutes(wallAsUtc);
  const off2 = cairoOffsetMinutes(new Date(wallAsUtc.getTime() - off1 * 60000));
  return new Date(wallAsUtc.getTime() - off2 * 60000);
}

module.exports = {
  CAIRO_TZ,
  cairoOffsetMinutes,
  parseClientTimestamp,
};
