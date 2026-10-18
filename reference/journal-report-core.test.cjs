'use strict';
process.env.TZ = 'Europe/Kyiv';
const test = require('node:test');
const assert = require('node:assert/strict');
const R = require('./journal-report-core.js');
const minute = 60000;
const hour = 60 * minute;
const at = (key, h = 0, m = 0) => R.dateAt(key, h * 60 + m);
const everyday = { mode: 'everyday', weekStart: 1, cutoff: 0 };
const weekdays = { mode: 'weekdays', weekdays: [1, 2, 3, 4, 5], weekStart: 1, cutoff: 0 };
const complete = (id, start, end, segments = [{ start, end }]) =>
  ({ id, start, end, plannedMs: hour, status: 'complete', segments });

test('clamps focus segments to the range and excludes pauses; partial focus adds time but no cycle', () => {
  const a = complete('a', at('2026-10-17', 8), at('2026-10-17', 10), [
    { start: at('2026-10-17', 8), end: at('2026-10-17', 8, 45) },
    { start: at('2026-10-17', 9, 15), end: at('2026-10-17', 10) }
  ]);
  const b = { ...complete('b', at('2026-10-17', 10), at('2026-10-17', 10, 15)), status: 'partial' };
  const report = R.buildReport([a, b], at('2026-10-17', 8, 30), at('2026-10-17', 11), everyday);
  assert.equal(report.focusMs, 75 * minute);
  assert.equal(report.cycles, 1);
  assert.equal(report.activeDays, 1);
  assert.equal(report.rows.find(row => row.id === 'a').totalFocusMs, 90 * minute);
  assert.equal(report.rows.find(row => row.id === 'a').focusMs, hour);
  assert.equal(report.rows.find(row => row.id === 'b').completionInRange, false);
  assert.deepEqual(report.rows.map(row => row.id), ['b', 'a']);
});

test('an exact completion boundary belongs to the next range without moving its focus time', () => {
  const record = complete('midnight', at('2026-10-16', 23), at('2026-10-17'));
  const first = R.buildReport([record], at('2026-10-16'), at('2026-10-17'), everyday);
  const next = R.buildReport([record], at('2026-10-17'), at('2026-10-18'), everyday);
  assert.equal(first.focusMs, hour);
  assert.equal(first.cycles, 0);
  assert.equal(next.focusMs, 0);
  assert.equal(next.cycles, 1);
  assert.equal(next.rows.length, 1);
  assert.equal(next.rows[0].completionInRange, true);
  assert.equal(next.activeDays, 0);
  assert.equal(first.days.length, 1);
});

test('a shift cutoff groups overnight focus correctly and splits an active segment at the cutoff', () => {
  const cutoff = { ...everyday, cutoff: 240 };
  assert.equal(R.dayKey(at('2026-10-17', 3, 59), 240), '2026-10-16');
  assert.equal(R.dayKey(at('2026-10-17', 4), 240), '2026-10-17');
  const record = complete('overnight', at('2026-10-17', 3, 30), at('2026-10-17', 4, 30));
  const report = R.buildReport([record], at('2026-10-17'), at('2026-10-18'), cutoff);
  assert.deepEqual(report.days.map(day => [day.key, day.focusMs, day.cycles]), [
    ['2026-10-16', 30 * minute, 0], ['2026-10-17', 30 * minute, 1]
  ]);
  assert.equal(report.focusMs, hour);
  assert.equal(report.activeDays, 2);
});

test('local calendar arithmetic crosses Kyiv DST days without assuming 24-hour days', () => {
  assert.equal(R.localKey(at('2026-03-29', 0, 30)), '2026-03-29');
  assert.equal(at('2026-03-30') - at('2026-03-29'), 23 * hour);
  assert.equal(at('2026-10-26') - at('2026-10-25'), 25 * hour);
  assert.equal(R.addDays('2026-03-28', 2), '2026-03-30');
  assert.equal(R.addDays('2026-10-26', -2), '2026-10-24');
  const record = complete('spring', at('2026-03-29'), at('2026-03-30'));
  const report = R.buildReport([record], at('2026-03-28'), at('2026-03-31'), everyday);
  assert.equal(report.focusMs, 23 * hour);
  assert.deepEqual(report.days.map(day => day.focusMs), [0, 23 * hour, 0]);
  assert.deepEqual(report.days.map(day => day.cycles), [0, 0, 1]);
});

test('weekly grouping agrees with daily totals, contains empty buckets, and respects week start', () => {
  const records = [
    complete('monday', at('2026-10-12', 9), at('2026-10-12', 10)),
    complete('sunday', at('2026-10-18', 9), at('2026-10-18', 10)),
    complete('nextMonday', at('2026-10-19', 9), at('2026-10-19', 10))
  ];
  const daily = R.buildReport(records, at('2026-10-12'), at('2026-11-02'), weekdays, 'day');
  const weekly = R.buildReport(records, at('2026-10-12'), at('2026-11-02'), weekdays, 'week');
  assert.equal(weekly.focusMs, daily.focusMs);
  assert.equal(weekly.cycles, daily.cycles);
  assert.equal(weekly.scheduledDays, 15);
  assert.equal(weekly.workedScheduledDays, 2);
  assert.equal(weekly.activeDays, 3);
  assert.deepEqual(weekly.buckets.map(bucket => [bucket.key, bucket.focusMs, bucket.cycles, bucket.scheduledDays]), [
    ['2026-10-12', 2 * hour, 2, 5], ['2026-10-19', hour, 1, 5], ['2026-10-26', 0, 0, 5]
  ]);
  assert.equal(R.weekKey('2026-10-18', 0), '2026-10-18');
  assert.equal(R.weekKey('2026-10-18', 1), '2026-10-12');
});

test('arbitrary weekdays label workdays without excluding focus performed on other days', () => {
  const custom = { ...weekdays, weekdays: [0, 2, 4] };
  const record = complete('saturday', at('2026-10-17', 9), at('2026-10-17', 10));
  assert.equal(R.isScheduled('2026-10-18', custom), true);
  assert.equal(R.isScheduled('2026-10-17', custom), false);
  const report = R.buildReport([record], at('2026-10-12'), at('2026-10-19'), custom);
  assert.equal(report.focusMs, hour);
  assert.equal(report.cycles, 1);
  assert.equal(report.scheduledDays, 3);
  assert.equal(report.workedScheduledDays, 0);
  assert.equal(report.activeDays, 1);
});

test('rotating shifts use calendar days through DST and apply consistently before the anchor', () => {
  const schedule = { mode: 'shifts', on: 2, off: 2, anchor: '2026-03-28' };
  assert.deepEqual(Array.from({ length: 12 }, (_, index) =>
    R.isScheduled(R.addDays('2026-03-24', index), schedule)),
  [true, true, false, false, true, true, false, false, true, true, false, false]);
  assert.equal(R.isScheduled('2026-03-27', schedule), false);
  assert.equal(R.isScheduled('2026-03-25', schedule), true);
  assert.equal(R.isScheduled('2026-03-29', schedule), true);
  assert.equal(R.isScheduled('2026-03-30', schedule), false);
  assert.equal(R.isScheduled('2026-03-30', { ...schedule, off: 0 }), true);
});

test('partial ranges count only overlapping report days and preserve empty dates', () => {
  const report = R.buildReport([], at('2026-10-16', 22), at('2026-10-19'), weekdays, 'week');
  assert.equal(report.days.length, 3);
  assert.equal(report.scheduledDays, 1);
  assert.equal(report.buckets.length, 1);
  assert.equal(report.buckets[0].scheduledDays, 1);
  assert.equal(report.buckets[0].start, at('2026-10-12'));
  assert.equal(report.buckets[0].end, at('2026-10-19'));
});

test('live focus is reportable without a completed cycle, and input objects are not mutated', () => {
  const record = { ...complete('live', at('2026-10-17', 10), at('2026-10-17', 10, 5)), status: 'live' };
  const before = JSON.stringify(record);
  const report = R.buildReport([record], at('2026-10-17'), at('2026-10-18'), everyday);
  assert.equal(report.focusMs, 5 * minute);
  assert.equal(report.cycles, 0);
  assert.equal(report.rows[0].status, 'live');
  assert.equal(JSON.stringify(record), before);
});

test('invalid ranges fail safely; malformed calendar keys and unsupported groups have clear errors', () => {
  for (const [from, to] of [[NaN, Date.now()], [0, Infinity], [3, 2], [2, 2], ['0', 2]]) {
    assert.deepEqual(R.buildReport([], from, to, everyday), {
      focusMs: 0, cycles: 0, activeDays: 0, scheduledDays: 0, workedScheduledDays: 0,
      days: [], buckets: [], rows: []
    });
  }
  assert.throws(() => R.dateAt('2026-02-30'), /valid calendar/);
  assert.throws(() => R.dateAt('2026-10-17', NaN), /cutoff/);
  assert.throws(() => R.weekKey('2026-10-17', 7), /Week start/);
  assert.throws(() => R.addDays('2026-10-17', Infinity), /whole number/);
  assert.throws(() => R.buildReport([], at('2026-10-17'), at('2026-10-18'), everyday, 'year'), /group/);
  const malformed = [{ id: 'bad', status: 'complete', end: NaN,
    segments: [{ start: NaN, end: 50 }, { start: 30, end: 20 }, null] }];
  assert.equal(R.buildReport(malformed, at('2026-10-17'), at('2026-10-18'),
    { mode: 'shifts', on: NaN, off: -1, anchor: 'bad', cutoff: Infinity }).focusMs, 0);
});
