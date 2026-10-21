#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const data = requireFromRoot('Events.js')

// ---- File format -----------------------------------------------------------
assertDeepEqual(
  data.emptyEvents(),
  { version: 1, todos: [], anniversaries: [] },
  'an empty file has both lists'
)

assertDeepEqual(data.parseEvents(''), data.emptyEvents(), 'a missing file parses as empty')
assertDeepEqual(data.parseEvents('   '), data.emptyEvents(), 'a blank file parses as empty')
assertDeepEqual(data.parseEvents('{not json'), data.emptyEvents(), 'malformed JSON parses as empty')
assertDeepEqual(data.parseEvents('[]'), data.emptyEvents(), 'a JSON array is not a store')

const events = data.addTodo(
  data.addAnniversary(data.emptyEvents(), '2026-10-21', '生日', 1990, true, 'a1'),
  '2026-10-21', '买牛奶', 't1'
)
const roundTrip = data.parseEvents(data.serializeEvents(events))
assertDeepEqual(roundTrip, events, 'a serialized store parses back unchanged')
assert(
  data.serializeEvents(events).endsWith('\n'),
  'the serialized store ends with a newline'
)

// ---- Normalization ---------------------------------------------------------
const normalized = data.normalizeEvents({
  todos: [
    { id: 't1', date: '2026-10-21', text: '  买菜  ', done: 1 },
    { id: 't2', date: '2026-13-01', text: 'bad month' },
    { id: 't3', date: '2026-10-22', text: '   ' },
    null,
    'nope'
  ],
  anniversaries: [
    { date: '2015-10-18', text: '结婚纪念日' },
    { date: '2015-10-18', text: '一年一次', yearly: true },
    { date: '2015-10-18', text: '只此一次', yearly: false },
    { date: '2015-10-18' }
  ]
})
assertEqual(normalized.todos.length, 1, 'todos with a bad date or blank text are dropped')
assertEqual(normalized.todos[0].text, '买菜', 'todo text is trimmed')
assertEqual(normalized.todos[0].done, false, 'only a literal true is done')
assertEqual(normalized.anniversaries.length, 3, 'anniversaries without text are dropped')
assertEqual(normalized.anniversaries[0].yearly, true, 'yearly defaults to true')
assertEqual(normalized.anniversaries[2].yearly, false, 'yearly false survives')
assert(
  normalized.anniversaries[0].id.length > 1,
  'a record with no id gets one'
)

const longText = 'x'.repeat(500)
const shortened = data.normalizeEvents({ todos: [{ date: '2026-10-21', text: longText }] })
assertEqual(shortened.todos[0].text.length, 200, 'text is capped at the row-safe length')
assertEqual(data.eventText('  a  '), 'a', 'eventText trims')

// ---- Date keys -------------------------------------------------------------
assertDeepEqual(data.keyParts('2026-10-21'), { year: 2026, month: 9, day: 21 }, 'a key splits into date parts')
assertEqual(data.keyParts('2026-13-01'), null, 'month 13 is not a date')
assertEqual(data.keyParts('2026-02-32'), null, 'day 32 is not a date')
assertEqual(data.keyParts('2026-2-01'), null, 'unpadded keys are not accepted')
assertEqual(data.keyParts(''), null, 'an empty key is not a date')
assertEqual(data.dateFromKey('2026-10-21').getDate(), 21, 'a key converts to a local date')
assertEqual(data.dateFromKey('nope'), null, 'a bad key converts to null')
assertEqual(data.eventDateKey(2026, 9, 21), '2026-10-21', 'a zero-based month composes a padded key')
assertEqual(data.eventDateKey(2026, 0, 1), '2026-01-01', 'January composes 01')

// ---- Todos -----------------------------------------------------------------
const base = data.emptyEvents()
const withTodo = data.addTodo(base, '2026-10-21', '  买菜  ', 't1')
assertEqual(base.todos.length, 0, 'addTodo does not mutate the input')
assertEqual(withTodo.todos.length, 1, 'addTodo appends one todo')
assertEqual(withTodo.todos[0].text, '买菜', 'addTodo trims the text')
assertDeepEqual(
  data.addTodo(base, '2026-10-21', '   ', 't2'),
  base,
  'addTodo ignores blank text'
)
assertDeepEqual(
  data.addTodo(base, 'not-a-date', 'text', 't3'),
  base,
  'addTodo ignores a bad date'
)

const done = data.setTodoDone(withTodo, 't1', true)
assertEqual(withTodo.todos[0].done, false, 'setTodoDone does not mutate the input')
assertEqual(done.todos[0].done, true, 'setTodoDone marks the todo done')
assertDeepEqual(
  data.setTodoDone(done, 'missing', false),
  done,
  'setTodoDone ignores an unknown id'
)

const removed = data.removeTodo(withTodo, 't1')
assertEqual(withTodo.todos.length, 1, 'removeTodo does not mutate the input')
assertEqual(removed.todos.length, 0, 'removeTodo drops the todo')
assertDeepEqual(data.removeTodo(withTodo, 'missing'), withTodo, 'removeTodo ignores an unknown id')

// ---- Anniversaries ---------------------------------------------------------
const withAnniversary = data.addAnniversary(base, '2026-10-21', '生日', 1990, true, 'a1')
assertEqual(base.anniversaries.length, 0, 'addAnniversary does not mutate the input')
assertEqual(withAnniversary.anniversaries[0].date, '1990-10-21', 'the start year and the clicked day compose the date')
assertEqual(withAnniversary.anniversaries[0].yearly, true, 'a yearly anniversary stays yearly')

const oneOff = data.addAnniversary(base, '2026-10-21', '毕业', 2026, false, 'a2')
assertEqual(oneOff.anniversaries[0].yearly, false, 'a one-off anniversary stays one-off')

const fallbackYear = data.addAnniversary(base, '2026-10-21', '生日', 'nonsense', true, 'a3')
assertEqual(fallbackYear.anniversaries[0].date, '2026-10-21', 'a bad start year falls back to the clicked year')

assertDeepEqual(
  data.removeAnniversary(withAnniversary, 'a1').anniversaries,
  [],
  'removeAnniversary drops the record'
)

// A yearly record matches its month and day in every year; a one-off only
// matches the whole date.
assertEqual(data.anniversaryFallsOn({ date: '1990-10-21', yearly: true }, 2026, 9, 21), true, 'a yearly anniversary falls on its day in a later year')
assertEqual(data.anniversaryFallsOn({ date: '1990-10-21', yearly: true }, 2026, 9, 22), false, 'a yearly anniversary does not fall on another day')
assertEqual(data.anniversaryFallsOn({ date: '2026-10-21', yearly: false }, 2026, 9, 21), true, 'a one-off falls on its date')
assertEqual(data.anniversaryFallsOn({ date: '2026-10-21', yearly: false }, 2027, 9, 21), false, 'a one-off does not repeat')

// ---- A day's contents ------------------------------------------------------
const store = data.normalizeEvents({
  todos: [
    { id: 't1', date: '2026-10-21', text: '买菜', done: false },
    { id: 't2', date: '2026-10-21', text: '交房租', done: true },
    { id: 't3', date: '2026-10-22', text: '别的日子', done: false }
  ],
  anniversaries: [
    { id: 'a1', date: '1990-10-21', text: '生日', yearly: true },
    { id: 'a2', date: '2026-10-22', text: '毕业', yearly: false }
  ]
})

const day = data.eventsForDate(store, '2026-10-21')
assertEqual(day.todos.length, 2, 'a day lists only its own todos')
assertEqual(day.anniversaries.length, 1, 'a day lists yearly anniversaries by month and day')
assertEqual(day.anniversaries[0].text, '生日', 'the right anniversary is listed')

assertDeepEqual(
  data.eventsForDate(store, 'bad'),
  { todos: [], anniversaries: [] },
  'a bad date has nothing'
)
assertDeepEqual(
  data.eventsForDate(data.emptyEvents(), '2026-10-21'),
  { todos: [], anniversaries: [] },
  'an empty store has nothing'
)

assertDeepEqual(
  data.dayMarkers(store, '2026-10-21'),
  { todo: true, openTodo: true, anniversary: true },
  'a day with an open todo and an anniversary marks both'
)
assertDeepEqual(
  data.dayMarkers(store, '2026-10-22'),
  { todo: true, openTodo: true, anniversary: true },
  'a day with a one-off anniversary marks it'
)
assertDeepEqual(
  data.dayMarkers(data.setTodoDone(store, 't1', true), '2026-10-21'),
  { todo: true, openTodo: false, anniversary: true },
  'a day whose todos are all done keeps the todo mark but reports none open'
)
assertDeepEqual(
  data.dayMarkers(store, '2026-10-23'),
  { todo: false, openTodo: false, anniversary: false },
  'an empty day marks nothing'
)

// ---- Counting and labels ---------------------------------------------------
assertEqual(data.anniversaryYears({ date: '2015-10-18', yearly: true }, 2026), 11, 'a 2015 anniversary is 11 in 2026')
assertEqual(data.anniversaryYears({ date: '2026-10-18', yearly: true }, 2026), 0, 'the start year counts zero')
assertEqual(data.anniversaryYears({ date: '2030-10-18', yearly: true }, 2026), 0, 'a future start does not count backwards')
assertEqual(data.anniversaryYears(null, 2026), 0, 'a missing record counts zero')

assertEqual(data.anniversaryLabel({ date: '2026-10-21', yearly: true }, 2026), 'YEARLY', 'the first year reads YEARLY')
assertEqual(data.anniversaryLabel({ date: '2026-10-21', yearly: false }, 2026), 'ONCE', 'a one-off reads ONCE')
assertEqual(data.anniversaryLabel({ date: '2025-10-21', yearly: true }, 2026), '1ST', 'one year reads 1ST')
assertEqual(data.anniversaryLabel({ date: '2024-10-21', yearly: true }, 2026), '2ND', 'two years reads 2ND')
assertEqual(data.anniversaryLabel({ date: '2023-10-21', yearly: true }, 2026), '3RD', 'three years reads 3RD')
assertEqual(data.anniversaryLabel({ date: '2022-10-21', yearly: true }, 2026), '4TH', 'four years reads 4TH')
assertEqual(data.anniversaryLabel({ date: '2015-10-21', yearly: true }, 2026), '11TH', 'eleven years reads 11TH')
assertEqual(data.anniversaryLabel({ date: '2014-10-21', yearly: true }, 2026), '12TH', 'twelve years reads 12TH')
assertEqual(data.anniversaryLabel({ date: '2013-10-21', yearly: true }, 2026), '13TH', 'thirteen years reads 13TH')
assertEqual(data.anniversaryLabel({ date: '2005-10-21', yearly: true }, 2026), '21ST', 'twenty-one years reads 21ST')
assertEqual(data.anniversaryLabel({ date: '2004-10-21', yearly: true }, 2026), '22ND', 'twenty-two years reads 22ND')
assertEqual(data.anniversaryLabel({ date: '2003-10-21', yearly: true }, 2026), '23RD', 'twenty-three years reads 23RD')
assertEqual(data.anniversaryLabel({ date: '1925-10-21', yearly: true }, 2026), '101ST', 'one hundred and one years reads 101ST')
assertEqual(data.anniversaryLabel({ date: '1915-10-21', yearly: true }, 2026), '111TH', 'one hundred and eleven years reads 111TH')
JS
