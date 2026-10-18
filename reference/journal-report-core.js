/* Deep Work journal reporting. Local calendar dates; no dependencies. */
(function (global) {
  'use strict';

  const DAY_MS = 86400000;
  const MAX_REPORT_DAYS = 100000;

  function validTimestamp(value) {
    return typeof value === 'number' && Number.isFinite(value) &&
      Number.isFinite(new Date(value).getTime());
  }

  function formatParts(year, month, day) {
    if (year < 0 || year > 9999) throw new RangeError('Calendar year must be between 0000 and 9999.');
    return String(year).padStart(4, '0') + '-' + String(month).padStart(2, '0') + '-' +
      String(day).padStart(2, '0');
  }

  function parseKey(key) {
    if (typeof key !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(key)) {
      throw new RangeError('Date must use YYYY-MM-DD.');
    }
    const parts = key.split('-').map(Number);
    const utc = new Date(0);
    utc.setUTCHours(0, 0, 0, 0);
    utc.setUTCFullYear(parts[0], parts[1] - 1, parts[2]);
    if (utc.getUTCFullYear() !== parts[0] || utc.getUTCMonth() + 1 !== parts[1] ||
        utc.getUTCDate() !== parts[2]) {
      throw new RangeError('Date is not a valid calendar day.');
    }
    return { year: parts[0], month: parts[1], day: parts[2], utc };
  }

  function checkCutoff(value) {
    if (!Number.isInteger(value) || value < 0 || value > 1439) {
      throw new RangeError('Day cutoff must be an integer from 0 to 1439 minutes.');
    }
    return value;
  }

  function localKey(timestamp) {
    if (!validTimestamp(timestamp)) throw new RangeError('Timestamp must be a valid number of milliseconds.');
    const date = new Date(timestamp);
    return formatParts(date.getFullYear(), date.getMonth() + 1, date.getDate());
  }

  function dateAt(key, cutoffMinutes = 0) {
    const parts = parseKey(key);
    const cutoff = checkCutoff(cutoffMinutes);
    const date = new Date(0);
    date.setFullYear(parts.year, parts.month - 1, parts.day);
    date.setHours(Math.floor(cutoff / 60), cutoff % 60, 0, 0);
    return date.getTime();
  }

  function addDays(key, count) {
    if (!Number.isSafeInteger(count)) throw new RangeError('Day offset must be a whole number.');
    const date = parseKey(key).utc;
    date.setUTCDate(date.getUTCDate() + count);
    if (!Number.isFinite(date.getTime())) throw new RangeError('Day offset is outside the supported calendar.');
    return formatParts(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate());
  }

  function dayKey(timestamp, cutoffMinutes = 0) {
    const key = localKey(timestamp);
    return timestamp < dateAt(key, cutoffMinutes) ? addDays(key, -1) : key;
  }

  function weekKey(key, weekStart = 1) {
    if (!Number.isInteger(weekStart) || weekStart < 0 || weekStart > 6) {
      throw new RangeError('Week start must be a weekday from 0 (Sunday) to 6 (Saturday).');
    }
    const weekday = parseKey(key).utc.getUTCDay();
    return addDays(key, -((weekday - weekStart + 7) % 7));
  }

  function normalizeSchedule(schedule) {
    const input = schedule && typeof schedule === 'object' ? schedule : {};
    const mode = ['weekdays', 'everyday', 'shifts'].includes(input.mode) ? input.mode : 'weekdays';
    const weekdays = Array.isArray(input.weekdays) ?
      [...new Set(input.weekdays.filter(day => Number.isInteger(day) && day >= 0 && day <= 6))] :
      [1, 2, 3, 4, 5];
    let on = Number.isSafeInteger(input.on) && input.on >= 1 ? input.on : 2;
    let off = Number.isSafeInteger(input.off) && input.off >= 0 ? input.off : 2;
    if (!Number.isSafeInteger(on + off)) { on = 2; off = 2; }
    let anchor = '1970-01-01';
    try { parseKey(input.anchor); anchor = input.anchor; } catch (_) { /* Stable fallback. */ }
    const weekStart = Number.isInteger(input.weekStart) && input.weekStart >= 0 && input.weekStart <= 6 ?
      input.weekStart : 1;
    const cutoff = Number.isInteger(input.cutoff) && input.cutoff >= 0 && input.cutoff <= 1439 ? input.cutoff : 0;
    return { mode, weekdays, on, off, anchor, weekStart, cutoff };
  }

  function scheduledDay(key, schedule) {
    const day = parseKey(key).utc;
    if (schedule.mode === 'everyday') return true;
    if (schedule.mode === 'weekdays') return schedule.weekdays.includes(day.getUTCDay());
    const calendarDays = (day.getTime() - parseKey(schedule.anchor).utc.getTime()) / DAY_MS;
    const period = schedule.on + schedule.off;
    return ((calendarDays % period) + period) % period < schedule.on;
  }

  function isScheduled(key, schedule) {
    return scheduledDay(key, normalizeSchedule(schedule));
  }

  function emptyReport() {
    return {
      focusMs: 0, cycles: 0, activeDays: 0, scheduledDays: 0, workedScheduledDays: 0,
      days: [], buckets: [], rows: []
    };
  }

  /**
   * Reports use [fromMs, toMs). Focus is the sum of valid, non-overlapping active
   * segments supplied by the timer; pauses and breaks have no segments. A complete
   * session counts once on its end timestamp, even if its focus was on a prior day.
   * Day/week boundaries are full local calendar boundaries; totals are range-clipped.
   * local Date rules resolve a missing DST cutoff forward and an ambiguous one earlier.
   */
  function buildReport(records, fromMs, toMs, schedule, group = 'day') {
    const report = emptyReport();
    if (!validTimestamp(fromMs) || !validTimestamp(toMs) || fromMs >= toMs) return report;
    if (group !== 'day' && group !== 'week') throw new RangeError('Report group must be day or week.');
    const normalized = normalizeSchedule(schedule);
    const daysByKey = new Map();
    let key = dayKey(fromMs, normalized.cutoff);
    let start = dateAt(key, normalized.cutoff);

    while (start < toMs) {
      if (report.days.length >= MAX_REPORT_DAYS) {
        throw new RangeError('Report range exceeds 100,000 calendar days.');
      }
      const nextKey = addDays(key, 1);
      const end = dateAt(nextKey, normalized.cutoff);
      if (!(end > start)) throw new RangeError('Reporting days must have increasing local boundaries.');
      if (end > fromMs) {
        const day = { key, start, end, focusMs: 0, cycles: 0, scheduled: scheduledDay(key, normalized) };
        report.days.push(day);
        daysByKey.set(key, day);
      }
      key = nextKey;
      start = end;
    }

    for (const record of Array.isArray(records) ? records : []) {
      if (!record || typeof record !== 'object') continue;
      let focusMs = 0;
      let totalFocusMs = 0;
      for (const segment of Array.isArray(record.segments) ? record.segments : []) {
        if (!segment || !validTimestamp(segment.start) || !validTimestamp(segment.end) || segment.end <= segment.start) continue;
        totalFocusMs += segment.end - segment.start;
        let cursor = Math.max(fromMs, segment.start);
        const clippedEnd = Math.min(toMs, segment.end);
        if (cursor >= clippedEnd) continue;
        focusMs += clippedEnd - cursor;
        while (cursor < clippedEnd) {
          const day = daysByKey.get(dayKey(cursor, normalized.cutoff));
          if (!day) throw new RangeError('Active time falls outside the reporting calendar.');
          const partEnd = Math.min(clippedEnd, day.end);
          if (!(partEnd > cursor)) throw new RangeError('Active time could not advance to the next reporting day.');
          day.focusMs += partEnd - cursor;
          cursor = partEnd;
        }
      }
      const completionInRange = record.status === 'complete' && validTimestamp(record.end) &&
        record.end >= fromMs && record.end < toMs;
      if (completionInRange) {
        const day = daysByKey.get(dayKey(record.end, normalized.cutoff));
        if (day) day.cycles += 1;
        report.cycles += 1;
      }
      if (focusMs > 0 || completionInRange) {
        report.rows.push({ ...record, focusMs, totalFocusMs, completionInRange });
        report.focusMs += focusMs;
      }
    }

    report.rows.sort((left, right) => {
      const leftStart = validTimestamp(left.start) ? left.start : 0;
      const rightStart = validTimestamp(right.start) ? right.start : 0;
      return rightStart - leftStart;
    });
    const bucketsByKey = new Map();
    for (const day of report.days) {
      if (day.focusMs > 0) report.activeDays += 1;
      if (day.scheduled) report.scheduledDays += 1;
      if (day.scheduled && day.focusMs > 0) report.workedScheduledDays += 1;
      const bucketKey = group === 'week' ? weekKey(day.key, normalized.weekStart) : day.key;
      let bucket = bucketsByKey.get(bucketKey);
      if (!bucket) {
        bucket = {
          key: bucketKey,
          start: dateAt(bucketKey, normalized.cutoff),
          end: dateAt(addDays(bucketKey, group === 'week' ? 7 : 1), normalized.cutoff),
          focusMs: 0,
          cycles: 0,
          scheduledDays: 0
        };
        report.buckets.push(bucket);
        bucketsByKey.set(bucketKey, bucket);
      }
      bucket.focusMs += day.focusMs;
      bucket.cycles += day.cycles;
      if (day.scheduled) bucket.scheduledDays += 1;
    }
    return report;
  }

  const api = { localKey, dateAt, addDays, dayKey, weekKey, isScheduled, buildReport };
  if (global) global.DeepWorkReports = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : typeof globalThis !== 'undefined' ? globalThis : this);
