// When to remind, for birthdays and anniversaries.
//
// The rule: once an anniversary is within a week, remind every day until the
// day itself. Reminders are not stored as "sent" flags that accumulate; instead
// the last reminded date is remembered per record, and a record is due when the
// day being asked about is later than that. That makes the whole thing
// idempotent — restarting the shell, or the service firing twice in a minute,
// cannot produce a second notification for the same day.
//
// A record that was already in its window when the file was written (the shell
// was off for a week) still gets exactly one reminder, for today, rather than
// seven at once.

var REMIND_DAYS = 7

// The Gregorian day an anniversary falls on in `year`, whatever calendar it is
// kept on. `lunar` is the panel's Lunar.js, passed in so this file stays free
// of the lunar tables and can be tested without them.
//
// Every month in this file is zero-based, matching Date and the calendar grid.
// Lunar.lunarToSolar returns one-based months (it hands back a calendar date as
// printed), so the minus one here is load-bearing.
function occurrenceIn(anniversary, year, lunar) {
  if (!anniversary) return null

  if (anniversary.calendar === "lunar") {
    var l = anniversary.lunar
    if (!l || !lunar) return null
    var solar = lunar.lunarToSolar(year, l.month, l.day, l.isLeap)
    return solar ? { year: solar.year, month: solar.month - 1, day: solar.day } : null
  }

  var parts = parseKey(anniversary.date)
  if (!parts) return null
  if (!anniversary.yearly && parts.year !== Number(year)) return null
  // The day must exist in the year being asked about: 29 February has no
  // occurrence in a common year, and rather than moving the record to the 28th
  // behind the user's back it simply has none. `parts.month` is already
  // zero-based, so it goes straight to Date.
  var occurringYear = Number(year)
  var check = new Date(occurringYear, parts.month, parts.day)
  if (check.getMonth() !== parts.month || check.getDate() !== parts.day) return null
  return { year: occurringYear, month: parts.month, day: parts.day }
}

function parseKey(key) {
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key === undefined || key === null ? "" : key))
  if (!match) return null
  var month = parseInt(match[2], 10) - 1
  var day = parseInt(match[3], 10)
  if (month < 0 || month > 11 || day < 1 || day > 31) return null
  return { year: parseInt(match[1], 10), month: month, day: day }
}

function dayNumber(year, month, day) {
  return Math.floor(Date.UTC(year, month, day) / 86400000)
}

// Whole days from `today` to `occurrence`, negative when it has passed.
function daysUntil(today, occurrence) {
  if (!today || !occurrence) return null
  return dayNumber(occurrence.year, occurrence.month, occurrence.day)
    - dayNumber(today.year, today.month, today.day)
}

// The occurrence worth telling the user about: this year's if it is still
// ahead or today, otherwise next year's. A record is never "missed" because
// the window closed — it comes back next year.
function nextOccurrence(anniversary, today, lunar) {
  if (!today) return null
  var thisYear = occurrenceIn(anniversary, today.year, lunar)
  if (thisYear && daysUntil(today, thisYear) >= 0) return thisYear
  return occurrenceIn(anniversary, Number(today.year) + 1, lunar)
}

// Monday-based index so "in three days" lands on a weekday name without the
// caller needing a locale.
var WEEKDAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

function weekdayName(occurrence) {
  if (!occurrence) return ""
  var date = new Date(Date.UTC(occurrence.year, occurrence.month, occurrence.day))
  return WEEKDAY_NAMES[date.getUTCDay()]
}

// "birthday on Thursday, 3 days" — the sentence a notification carries.
function reminderText(anniversary, occurrence, today, calendarName) {
  if (!anniversary || !occurrence) return ""
  var days = daysUntil(today, occurrence)
  var when = days === 0 ? "is today" : (days === 1 ? "is tomorrow" : "is in " + days + " days")
  var label = calendarName ? " (" + calendarName + ")" : ""
  return String(anniversary.text || "") + label + " " + when + ", " + weekdayName(occurrence)
}

// Which records need telling today, and what to say.
//
// `reminded` maps record id -> the "yyyy-MM-dd" it was last reminded on. A
// record is due when it has never been reminded, or its last reminder was
// before today, and its next occurrence is within REMIND_DAYS.
//
// `today` is {year, month (zero-based), day} in the user's own timezone — the
// notification is for a person sitting at the machine, so this is deliberately
// local time rather than the Beijing time the lunar tables use internally.
function dueReminders(events, today, lunar, reminded) {
  var out = []
  if (!events || !today) return out
  var anniversaries = Array.isArray(events.anniversaries) ? events.anniversaries : []
  var already = reminded && typeof reminded === "object" ? reminded : {}
  var todayKey = key(yearOf(today), today.month, today.day)

  for (var i = 0; i < anniversaries.length; i++) {
    var record = anniversaries[i]
    if (!record || !record.id) continue

    var last = already[record.id]
    if (last === todayKey) continue

    var occurrence = nextOccurrence(record, today, lunar)
    if (!occurrence) continue
    var days = daysUntil(today, occurrence)
    if (days === null || days < 0 || days > REMIND_DAYS) continue

    out.push({
      id: record.id,
      text: record.text || "",
      occurrence: occurrence,
      days: days,
      dateLabel: pad2(occurrence.month + 1) + "-" + pad2(occurrence.day),
      lunarLabel: lunarLabel(record, lunar),
      calendar: record.calendar === "lunar" ? "lunar" : "solar"
    })
  }

  out.sort(function(a, b) { return a.days - b.days })
  return out
}

function lunarLabel(record, lunar) {
  if (!record || record.calendar !== "lunar" || !record.lunar || !lunar) return ""
  return lunar.lunarMonthDayName(record.lunar.month, record.lunar.day, record.lunar.isLeap)
}

function yearOf(today) {
  return today.year
}

function key(year, month, day) {
  return year + "-" + pad2(month + 1) + "-" + pad2(day)
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

// The new reminder map after today's batch: every record that was due is
// stamped with today, so a restart later in the day cannot repeat it. Entries
// for records that no longer exist are dropped so the file does not grow
// forever as anniversaries are deleted.
function stampReminded(events, due, today, reminded) {
  var next = {}
  var existing = reminded && typeof reminded === "object" ? reminded : {}
  var alive = {}
  var anniversaries = events && Array.isArray(events.anniversaries) ? events.anniversaries : []
  for (var i = 0; i < anniversaries.length; i++)
    if (anniversaries[i] && anniversaries[i].id) alive[anniversaries[i].id] = true

  for (var id in existing)
    if (alive[id]) next[id] = existing[id]

  var todayKey = key(yearOf(today), today.month, today.day)
  for (var j = 0; j < (due || []).length; j++)
    if (due[j] && due[j].id) next[due[j].id] = todayKey

  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    REMIND_DAYS: REMIND_DAYS,
    occurrenceIn: occurrenceIn,
    parseKey: parseKey,
    daysUntil: daysUntil,
    nextOccurrence: nextOccurrence,
    weekdayName: weekdayName,
    reminderText: reminderText,
    dueReminders: dueReminders,
    stampReminded: stampReminded,
    lunarLabel: lunarLabel
  }
}
