// Todos and anniversaries for the lunar clock, as pure data functions.
//
// One JSON file holds both. A todo belongs to a single date; an anniversary
// repeats on its month and day every year unless `yearly` is false. The date
// of a yearly anniversary is the date it started (a birth date, a wedding
// date), which is what lets the panel count the years.
//
// This lives apart from Model.js on purpose: Model.js is kept byte-identical
// to the built-in clock so a future upstream sync stays a clean diff. Everything
// here is locale- and Qt-free too, so the file format, the day lookups, and the
// editing operations are unit tested under node without the panel.

var EVENTS_VERSION = 1
var EVENT_TEXT_LIMIT = 200

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
    var anniversaryDate = String(anniversary.date || "")
    var anniversaryText = eventText(anniversary.text)
    if (!keyParts(anniversaryDate) || anniversaryText === "") continue
    out.anniversaries.push({
      id: String(anniversary.id || newEventId("a")),
      date: anniversaryDate,
      text: anniversaryText,
      yearly: anniversary.yearly !== false
    })
  }

  return out
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
    date: eventDateKey(year, parts.month, parts.day),
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

// A yearly anniversary matches on month and day alone, so the same record
// shows up in every year; a one-off has to match the whole date.
function anniversaryFallsOn(anniversary, year, month, day) {
  if (!anniversary) return false
  var parts = keyParts(anniversary.date)
  if (!parts) return false
  if (!anniversary.yearly)
    return parts.year === Number(year) && parts.month === Number(month) && parts.day === Number(day)
  return parts.month === Number(month) && parts.day === Number(day)
}

// Everything pinned to one day, in the shape the panel binds to.
function eventsForDate(events, key) {
  var parts = keyParts(key)
  var out = { todos: [], anniversaries: [] }
  if (!parts) return out

  var source = events && typeof events === "object" ? events : emptyEvents()
  var todos = Array.isArray(source.todos) ? source.todos : []
  var anniversaries = Array.isArray(source.anniversaries) ? source.anniversaries : []

  for (var i = 0; i < todos.length; i++)
    if (todos[i] && todos[i].date === String(key)) out.todos.push(todos[i])

  for (var j = 0; j < anniversaries.length; j++)
    if (anniversaryFallsOn(anniversaries[j], parts.year, parts.month, parts.day))
      out.anniversaries.push(anniversaries[j])

  return out
}

// Just enough for the dot in a day cell: whether the day has either kind of
// entry, and whether a todo is still open.
function dayMarkers(events, key) {
  var day = eventsForDate(events, key)
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
function anniversaryYears(anniversary, year) {
  var parts = keyParts(anniversary && anniversary.date)
  var current = Math.round(Number(year))
  if (!parts || !isFinite(current)) return 0
  var years = current - parts.year
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
    normalizeEvents: normalizeEvents,
    parseEvents: parseEvents,
    serializeEvents: serializeEvents,
    addTodo: addTodo,
    setTodoDone: setTodoDone,
    removeTodo: removeTodo,
    addAnniversary: addAnniversary,
    removeAnniversary: removeAnniversary,
    anniversaryFallsOn: anniversaryFallsOn,
    eventsForDate: eventsForDate,
    dayMarkers: dayMarkers,
    anniversaryYears: anniversaryYears,
    anniversaryLabel: anniversaryLabel
  }
}
