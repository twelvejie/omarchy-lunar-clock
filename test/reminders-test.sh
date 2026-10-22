#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const data = requireFromRoot('Reminders.js')
const events = requireFromRoot('Events.js')
const lunar = requireFromRoot('Lunar.js')

// Local mid-month dates only: a month boundary would make these tests depend on
// the host timezone, which is exactly the sort of flake that hides a real bug.
const TODAY = { year: 2026, month: 9, day: 22 } // 2026-10-22

function anniversary(overrides) {
  return Object.assign({ id: 'a1', text: 'Birthday', yearly: true, calendar: 'solar', date: '2015-10-25' }, overrides)
}

function due(list, today, reminded) {
  return data.dueReminders({ version: 1, todos: [], anniversaries: list }, today || TODAY, lunar, reminded || {})
}

// ---- Occurrences -----------------------------------------------------------
assertDeepEqual(data.parseKey('2026-10-22'), { year: 2026, month: 9, day: 22 }, 'a key splits into parts with a zero-based month')
assertEqual(data.parseKey('2026-1-5'), null, 'an unpadded key is not a stored key')
assertEqual(data.parseKey(''), null, 'an empty key is not a date')

assertDeepEqual(
  data.occurrenceIn(anniversary(), 2026, lunar),
  { year: 2026, month: 9, day: 25 },
  'a solar anniversary occurs on its month and day'
)
assertEqual(
  data.occurrenceIn(anniversary({ yearly: false, date: '2015-10-25' }), 2026, lunar),
  null,
  'a one-off does not occur in another year'
)
assertEqual(
  data.occurrenceIn(anniversary({ yearly: false, date: '2026-10-25' }), 2026, lunar) !== null,
  true,
  'a one-off occurs in its own year'
)

// 29 February has no occurrence in a common year rather than being pushed to
// the 28th, which would be a different day.
assertEqual(
  data.occurrenceIn(anniversary({ date: '2016-02-29' }), 2027, lunar),
  null,
  'a leap-day anniversary has no occurrence in a common year'
)
assertEqual(
  data.occurrenceIn(anniversary({ date: '2016-02-29' }), 2028, lunar) !== null,
  true,
  'a leap-day anniversary occurs in a leap year'
)

// ---- Lunar occurrences resolve to the right Gregorian day ------------------
const lunarBirthday = anniversary({
  id: 'L1', calendar: 'lunar', year: 1990,
  lunar: { year: 1990, month: 8, day: 16, isLeap: false }, text: '农历生日'
})
// 农历八月十六 2026 is 2026-09-26, which in this file's zero-based months is 8-26.
assertDeepEqual(
  data.occurrenceIn(lunarBirthday, 2026, lunar),
  { year: 2026, month: 8, day: 26 },
  'a lunar anniversary resolves to its Gregorian day'
)
assertEqual(
  data.occurrenceIn(lunarBirthday, 2025, lunar).day,
  7,
  'the same lunar date lands on a different Gregorian day a year earlier'
)
assertEqual(data.occurrenceIn(lunarBirthday, 2026, null), null, 'without Lunar.js a lunar record has no occurrence')

// ---- Distance --------------------------------------------------------------
assertEqual(data.daysUntil(TODAY, { year: 2026, month: 9, day: 22 }), 0, 'today is zero days away')
assertEqual(data.daysUntil(TODAY, { year: 2026, month: 9, day: 25 }), 3, 'three days ahead')
assertEqual(data.daysUntil(TODAY, { year: 2026, month: 9, day: 20 }), -2, 'two days past is negative')
assertEqual(data.weekdayName({ year: 2026, month: 9, day: 22 }), 'Thursday', 'a known Thursday is named')

// ---- The window ------------------------------------------------------------
// Reminders start a week out. Today is the 22nd, so the 29th is day 7 and the
// 30th is day 8.
assertEqual(due([anniversary({ date: '2015-10-29' })]).length, 1, 'seven days out is inside the window')
assertEqual(due([anniversary({ date: '2015-10-30' })]).length, 0, 'eight days out is outside the window')
assertEqual(due([anniversary({ date: '2015-10-22' })]).length, 1, 'today is inside the window')
assertEqual(due([anniversary({ date: '2015-10-21' })]).length, 0, 'yesterday is not reminded for, it has passed')

// A record already in the window still fires once when its date arrives, and a
// record that has passed rolls forward to next year rather than disappearing.
assertEqual(due([anniversary({ date: '2015-10-21' })], { year: 2027, month: 9, day: 18 }).length, 1, 'a passed date comes round again next year')

// ---- One reminder a day ----------------------------------------------------
const one = due([anniversary({ date: '2015-10-25' })])
assertEqual(one.length, 1, 'a record in the window is due')
assertEqual(data.dueReminders({ anniversaries: [anniversary({ date: '2015-10-25' })] }, TODAY, lunar, { a1: '2026-10-22' }).length, 0, 'the same day is not reminded twice')
assertEqual(data.dueReminders({ anniversaries: [anniversary({ date: '2015-10-25' })] }, TODAY, lunar, { a1: '2026-10-21' }).length, 1, 'a new day reminds again')

// Stamping is what makes that work; it also prunes records that no longer exist.
const stamped = data.stampReminded({ anniversaries: [anniversary()] }, one, TODAY, { gone: '2026-10-01' })
assertEqual(stamped.a1, '2026-10-22', 'a due record is stamped with today')
assertEqual('gone' in stamped, false, 'a stamp for a deleted record is dropped')
assertDeepEqual(data.stampReminded({ anniversaries: [] }, [], TODAY, { a1: '2026-10-22' }), {}, 'stamps for deleted records are pruned')

// Restarting the shell mid-day must not repeat: the stamp survives in the file,
// so asking again with it produces nothing.
assertEqual(
  data.dueReminders({ anniversaries: [anniversary()] }, TODAY, lunar, stamped).length,
  0,
  'a restart later the same day does not remind again'
)

// ---- Several at once -------------------------------------------------------
const several = due([
  anniversary({ id: 'b', date: '2015-10-27', text: 'Later' }),
  anniversary({ id: 'c', date: '2015-10-23', text: 'Sooner' })
])
assertEqual(several.length, 2, 'every record in the window is due')
assertEqual(several[0].id, 'c', 'the soonest is first')
assertEqual(several[1].id, 'b', 'the furthest is last')

// ---- The sentence ----------------------------------------------------------
assertEqual(
  data.reminderText({ text: 'Birthday' }, { year: 2026, month: 9, day: 22 }, TODAY, ''),
  'Birthday is today, Thursday',
  'the day itself reads today'
)
assertEqual(
  data.reminderText({ text: 'Birthday' }, { year: 2026, month: 9, day: 23 }, TODAY, ''),
  'Birthday is tomorrow, Friday',
  'one day ahead reads tomorrow'
)
assertEqual(
  data.reminderText({ text: 'Birthday' }, { year: 2026, month: 9, day: 25 }, TODAY, ''),
  'Birthday is in 3 days, Sunday',
  'three days ahead counts the days'
)
// 2026-09-26 is in the past relative to TODAY, so the sentence is built from a
// day that is still ahead: 农历八月十六 in 2027 is 2027-09-15.
assertEqual(
  data.reminderText(lunarBirthday, { year: 2027, month: 8, day: 16 }, { year: 2027, month: 8, day: 13 }, '八月十六'),
  '农历生日 (八月十六) is in 3 days, Thursday',
  'a lunar record carries its lunar date in the sentence'
)

// ---- Robustness ------------------------------------------------------------
assertDeepEqual(due(null), [], 'a missing list has nothing due')
assertDeepEqual(data.dueReminders(null, TODAY, lunar, {}), [], 'a missing store has nothing due')
assertDeepEqual(data.dueReminders({ anniversaries: [anniversary()] }, null, lunar, {}), [], 'without a today nothing is due')
assertDeepEqual(due([anniversary({ id: '' })]), [], 'a record with no id is skipped')
assertDeepEqual(due([{ id: 'x', calendar: 'solar', date: 'nope', text: 'bad', yearly: true }]), [], 'a record with an unparseable date is skipped')

// The window is a named constant, not a magic number in two places.
assertEqual(data.REMIND_DAYS, 7, 'reminders start a week out')
JS
