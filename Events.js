// Todos and anniversaries for the lunar clock, as pure data functions.
//
// One JSON file holds both. A todo belongs to a single date. An anniversary
// repeats every year on a month and day — either a Gregorian one or a lunar
// one, because a lunar birthday drifts across the Gregorian calendar and only
// the lunar date stays put. Either way the record keeps the date it started,
// which is what lets the panel count the years.
//
// This lives apart from Model.js on purpose: Model.js is kept byte-identical
// to the built-in clock so a future upstream sync stays a clean diff. Everything
// here is locale- and Qt-free too, so the file format, the day lookups, and the
// editing operations are unit tested under node without the panel.

var EVENTS_VERSION = 1
var EVENT_TEXT_LIMIT = 200
var CALENDAR_SOLAR = "solar"
var CALENDAR_LUNAR = "lunar"

function emptyEvents() {
  return { version: EVENTS_VERSION, todos: [], anniversaries: [] }
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

// Stable "yyyy-MM-dd" identity for a day, matching the grid's own keys.
function eventDateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

// Trimmed and bounded, because this text is typed by hand and lands in a
// one-line row.
function eventText(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  return text.length > EVENT_TEXT_LIMIT ? text.slice(0, EVENT_TEXT_LIMIT) : text
}

// Ids only have to be unique within one file, so time plus randomness is
// enough and avoids keeping a counter that would need persisting itself.
function newEventId(prefix) {
  return String(prefix || "e") + Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

// "yyyy-MM-dd" back to its parts. The month is zero-based to match Date and
// the calendar grid; the key itself counts months from one.
function keyParts(key) {
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key === undefined || key === null ? "" : key))
  if (!match) return null
  var month = parseInt(match[2], 10) - 1
  var day = parseInt(match[3], 10)
  if (month < 0 || month > 11 || day < 1 || day > 31) return null
  return { year: parseInt(match[1], 10), month: month, day: day }
}

function dateFromKey(key) {
  var parts = keyParts(key)
  return parts ? new Date(parts.year, parts.month, parts.day) : null
}

// Typed date, as opposed to a stored one. keyParts above is deliberately
// strict because it validates the file format; a person typing into a field
// writes 2026-1-5 as readily as 2026-01-05, and rejecting that for a missing
// zero is hostile. Accepts yyyy-M-d, yyyy/M/d, yyyy.M.d and the same without
// the year (M-d), which then borrows `fallbackYear`. Returns the same shape as
// keyParts, or null.
function parseDateInput(text, fallbackYear) {
  var raw = String(text === undefined || text === null ? "" : text).replace(/^\s+|\s+$/g, "")
  if (raw === "") return null

  var match = /^(\d{4})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{1,2})$/.exec(raw)
  if (match) return validParts(parseInt(match[1], 10), parseInt(match[2], 10), parseInt(match[3], 10))

  var shortMatch = /^(\d{1,2})\s*[-/.]\s*(\d{1,2})$/.exec(raw)
  if (shortMatch) {
    var year = Math.round(Number(fallbackYear))
    if (!isFinite(year)) return null
    return validParts(year, parseInt(shortMatch[1], 10), parseInt(shortMatch[2], 10))
  }

  return null
}

// One-based month in, zero-based month out, and February 30 rejected rather
// than rolled into March the way Date would.
function validParts(year, month, day) {
  if (!isFinite(year) || year < 1 || year > 9999) return null
  if (!isFinite(month) || month < 1 || month > 12) return null
  if (!isFinite(day) || day < 1 || day > 31) return null
  var check = new Date(year, month - 1, day)
  if (check.getFullYear() !== year || check.getMonth() !== month - 1 || check.getDate() !== day) return null
  return { year: year, month: month - 1, day: day }
}

// Drops anything that cannot be rendered rather than letting one hand-edited
// entry take the whole file down with it.
function normalizeEvents(value) {
  var out = emptyEvents()
  if (!value || typeof value !== "object") return out

  var todos = Array.isArray(value.todos) ? value.todos : []
  for (var i = 0; i < todos.length; i++) {
    var todo = todos[i]
    if (!todo || typeof todo !== "object") continue
    var todoDate = String(todo.date || "")
    var todoText = eventText(todo.text)
    if (!keyParts(todoDate) || todoText === "") continue
    out.todos.push({
      id: String(todo.id || newEventId("t")),
      date: todoDate,
      text: todoText,
      done: todo.done === true
    })
  }

  var anniversaries = Array.isArray(value.anniversaries) ? value.anniversaries : []
  for (var j = 0; j < anniversaries.length; j++) {
    var anniversary = anniversaries[j]
    if (!anniversary || typeof anniversary !== "object") continue
    var anniversaryText = eventText(anniversary.text)
    if (anniversaryText === "") continue
    var record = normalizeAnniversary(anniversary, anniversaryText)
    if (record) out.anniversaries.push(record)
  }

  return out
}

// A Gregorian record keeps its start date; a lunar one keeps the lunar date
// plus the Gregorian date it started on, so the panel can still sort and count
// from the start year without converting on every keystroke. A record that
// cannot be resolved one way is tried the other before being dropped, because
// the file is hand-editable and a slightly wrong field should not lose the
// entry.
function normalizeAnniversary(anniversary, label) {
  var startYear = Math.round(Number(anniversary.year))

  if (anniversary.calendar === CALENDAR_LUNAR) {
    var lunar = anniversary.lunar
    if (!lunar || typeof lunar !== "object") return null

    var month = Math.round(Number(lunar.month))
    var day = Math.round(Number(lunar.day))
    var year = isFinite(startYear) && startYear >= 1 && startYear <= 9999
      ? startYear
      : Math.round(Number(lunar.year))
    var isLeap = lunar.isLeap === true
    if (!isFinite(year) || year < 1 || year > 9999) return null
    if (month < 1 || month > 12 || day < 1 || day > 30) return null

    return {
      id: String(anniversary.id || newEventId("a")),
      calendar: CALENDAR_LUNAR,
      year: year,
      lunar: { year: year, month: month, day: day, isLeap: isLeap },
      date: String(anniversary.date || ""),
      text: label,
      yearly: anniversary.yearly !== false
    }
  }

  var anniversaryDate = String(anniversary.date || "")
  if (!keyParts(anniversaryDate) || label === "") return null

  return {
    id: String(anniversary.id || newEventId("a")),
    calendar: CALENDAR_SOLAR,
    date: anniversaryDate,
    text: label,
    yearly: anniversary.yearly !== false
  }
}

function parseEvents(text) {
  var raw = String(text === undefined || text === null ? "" : text).replace(/^\s+|\s+$/g, "")
  if (raw === "") return emptyEvents()
  var parsed = null
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    return emptyEvents()
  }
  return normalizeEvents(parsed)
}

function serializeEvents(events) {
  return JSON.stringify(normalizeEvents(events), null, 2) + "\n"
}

// A shallow copy: the edit operations replace array entries rather than
// mutating them, so the old snapshot stays intact for QML bindings.
function copyEvents(events) {
  var source = normalizeEvents(events)
  return {
    version: EVENTS_VERSION,
    todos: source.todos.slice(),
    anniversaries: source.anniversaries.slice()
  }
}

function addTodo(events, key, text, id) {
  var next = copyEvents(events)
  var label = eventText(text)
  if (!keyParts(key) || label === "") return next
  next.todos.push({
    id: String(id || newEventId("t")),
    date: String(key),
    text: label,
    done: false
  })
  return next
}

function setTodoDone(events, id, done) {
  var next = copyEvents(events)
  for (var i = 0; i < next.todos.length; i++) {
    if (next.todos[i].id !== String(id)) continue
    next.todos[i] = {
      id: next.todos[i].id,
      date: next.todos[i].date,
      text: next.todos[i].text,
      done: done === true
    }
  }
  return next
}

function removeTodo(events, id) {
  var next = copyEvents(events)
  next.todos = next.todos.filter(function(todo) { return todo.id !== String(id) })
  return next
}

// `startYear` is the year the anniversary began; the month and day come from
// the clicked day. A yearly anniversary keeps that start year so the panel
// can say how many years it has been.
function addAnniversary(events, key, text, startYear, yearly, id) {
  var next = copyEvents(events)
  var parts = keyParts(key)
  var label = eventText(text)
  if (!parts || label === "") return next

  var year = Math.round(Number(startYear))
  if (!isFinite(year) || year < 1 || year > 9999) year = parts.year

  next.anniversaries.push({
    id: String(id || newEventId("a")),
    calendar: CALENDAR_SOLAR,
    date: eventDateKey(year, parts.month, parts.day),
    text: label,
    yearly: yearly !== false
  })
  return next
}

// The same thing anchored on a lunar date instead. `lunarMonth` and `lunarDay`
// are one-based and `isLeap` picks the 闰 month; `startYear` is the lunar year
// the occasion began in. `date` keeps the Gregorian day that lunar date landed
// on in its first year, which is what the file shows at a glance.
function addLunarAnniversary(events, text, startYear, lunarMonth, lunarDay, isLeap, yearly, id) {
  var next = copyEvents(events)
  var label = eventText(text)
  var year = Math.round(Number(startYear))
  var month = Math.round(Number(lunarMonth))
  var day = Math.round(Number(lunarDay))

  if (label === "") return next
  if (!isFinite(year) || year < 1 || year > 9999) return next
  if (month < 1 || month > 12 || day < 1 || day > 30) return next

  next.anniversaries.push({
    id: String(id || newEventId("a")),
    calendar: CALENDAR_LUNAR,
    year: year,
    lunar: { year: year, month: month, day: day, isLeap: isLeap === true },
    date: "",
    text: label,
    yearly: yearly !== false
  })
  return next
}

function removeAnniversary(events, id) {
  var next = copyEvents(events)
  next.anniversaries = next.anniversaries.filter(function(item) {
    return item.id !== String(id)
  })
  return next
}

function isLunarAnniversary(anniversary) {
  return !!anniversary && anniversary.calendar === CALENDAR_LUNAR
}

// A yearly anniversary matches on month and day alone, so the same record
// shows up in every year; a one-off has to match the whole date.
//
// Lunar records resolve through calendar.dayInfo, which the caller supplies
// (the panel passes Lunar.js, the tests pass their own): this file stays free
// of the lunar tables so it can be tested on its own. `lunar` is the
// {lunarMonth, lunarDay, isLeap} for the day being asked about.
function anniversaryFallsOn(anniversary, year, month, day, lunar) {
  if (!anniversary) return false

  if (isLunarAnniversary(anniversary)) {
    var record = anniversary.lunar
    if (!record || !lunar) return false
    if (record.month !== Number(lunar.lunarMonth)) return false
    if (record.day !== Number(lunar.lunarDay)) return false
    // A birthday kept on a leap month only comes round in years that have
    // that leap month; matching it against the ordinary month would put it
    // on the wrong day in all the other years.
    if (record.isLeap !== (lunar.isLeap === true)) return false
    if (!anniversary.yearly) return Number(year) === Number(anniversary.year)
    return true
  }

  var parts = keyParts(anniversary.date)
  if (!parts) return false
  if (!anniversary.yearly)
    return parts.year === Number(year) && parts.month === Number(month) && parts.day === Number(day)
  return parts.month === Number(month) && parts.day === Number(day)
}

// Everything pinned to one day, in the shape the panel binds to. `lunar` is
// the lunar date of the day being asked about, supplied by the caller, and may
// be null outside the lunar table's range — lunar records then simply do not
// resolve, while Gregorian ones keep working.
function eventsForDate(events, key, lunar) {
  var parts = keyParts(key)
  var out = { todos: [], anniversaries: [] }
  if (!parts) return out

  var source = events && typeof events === "object" ? events : emptyEvents()
  var todos = Array.isArray(source.todos) ? source.todos : []
  var anniversaries = Array.isArray(source.anniversaries) ? source.anniversaries : []

  for (var i = 0; i < todos.length; i++)
    if (todos[i] && todos[i].date === String(key)) out.todos.push(todos[i])

  for (var j = 0; j < anniversaries.length; j++)
    if (anniversaryFallsOn(anniversaries[j], parts.year, parts.month, parts.day, lunar))
      out.anniversaries.push(anniversaries[j])

  return out
}

// Just enough for the dot in a day cell: whether the day has either kind of
// entry, and whether a todo is still open.
function dayMarkers(events, key, lunar) {
  var day = eventsForDate(events, key, lunar)
  var open = false
  for (var i = 0; i < day.todos.length; i++)
    if (!day.todos[i].done) open = true
  return {
    todo: day.todos.length > 0,
    openTodo: open,
    anniversary: day.anniversaries.length > 0
  }
}

// How many years the anniversary has been going in `year`, counted the way
// people say it: the start year itself is zero, the next year is the first.
// For a lunar record the year is the lunar year it started in.
function anniversaryYears(anniversary, year) {
  var current = Math.round(Number(year))
  if (!anniversary || !isFinite(current)) return 0

  var start = isLunarAnniversary(anniversary)
    ? Math.round(Number(anniversary.year))
    : (keyParts(anniversary.date) || {}).year
  if (!isFinite(start)) return 0

  var years = current - start
  return years > 0 ? years : 0
}

// The small label on an anniversary row. "ONCE" for a one-off, the ordinal
// year for a yearly one that has started, and "YEARLY" on its first year.
function anniversaryLabel(anniversary, year) {
  if (!anniversary) return ""
  if (!anniversary.yearly) return "ONCE"
  var years = anniversaryYears(anniversary, year)
  if (years <= 0) return "YEARLY"
  var mod100 = years % 100
  var mod10 = years % 10
  var suffix = "TH"
  if (mod100 < 11 || mod100 > 13) {
    if (mod10 === 1) suffix = "ST"
    else if (mod10 === 2) suffix = "ND"
    else if (mod10 === 3) suffix = "RD"
  }
  return years + suffix
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyEvents: emptyEvents,
    eventDateKey: eventDateKey,
    eventText: eventText,
    newEventId: newEventId,
    keyParts: keyParts,
    dateFromKey: dateFromKey,
    parseDateInput: parseDateInput,
    validParts: validParts,
    normalizeEvents: normalizeEvents,
    parseEvents: parseEvents,
    serializeEvents: serializeEvents,
    addTodo: addTodo,
    setTodoDone: setTodoDone,
    removeTodo: removeTodo,
    addAnniversary: addAnniversary,
    addLunarAnniversary: addLunarAnniversary,
    removeAnniversary: removeAnniversary,
    isLunarAnniversary: isLunarAnniversary,
    anniversaryFallsOn: anniversaryFallsOn,
    eventsForDate: eventsForDate,
    dayMarkers: dayMarkers,
    anniversaryYears: anniversaryYears,
    anniversaryLabel: anniversaryLabel
  }
}
