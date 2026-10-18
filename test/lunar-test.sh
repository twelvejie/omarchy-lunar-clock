#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const lunar = requireFromRoot('Lunar.js')

// ---- Known dates -----------------------------------------------------------
// Festivals and the first day of a leap month. New Year's Eve covers both a
// 三十 and a 廿九 ending, which is the point of deriving it from the year's
// own length rather than hard-coding the twelfth month's last day.
const festivalCases = [
  [2024, 2, 10, '春节'],
  [2025, 1, 29, '春节'],
  [2026, 2, 17, '春节'],
  [2023, 1, 22, '春节'],
  [2024, 2, 9, '除夕'],
  [2025, 1, 28, '除夕'],
  [2026, 2, 16, '除夕'],
  [2024, 6, 10, '端午节'],
  [2025, 5, 31, '端午节'],
  [2026, 6, 19, '端午节'],
  [2024, 9, 17, '中秋节'],
  [2025, 10, 6, '中秋节'],
  [2026, 9, 25, '中秋节'],
  [2026, 10, 18, '重阳节'],
  [2020, 6, 25, '端午节']
]

for (const [y, m, d, expected] of festivalCases) {
  assertEqual(lunar.dayLabel(y, m, d), expected, `${y}-${m}-${d} is ${expected}`)
  assertEqual(lunar.dayInfo(y, m, d).kind, 'festival', `${y}-${m}-${d} is classified as a festival`)
}

const leapCases = [
  [2020, 5, 23, '闰四月'],
  [2023, 3, 22, '闰二月'],
  [2025, 7, 25, '闰六月']
]

for (const [y, m, d, expected] of leapCases) {
  assertEqual(lunar.dayLabel(y, m, d), expected, `${y}-${m}-${d} is ${expected}`)
  assert(lunar.solarToLunar(y, m, d).isLeap, `${y}-${m}-${d} is marked as a leap month`)
}

// Ordinary firsts and day names.
assertEqual(lunar.dayLabel(2024, 12, 31), '腊月', '2024-12-31 starts the twelfth lunar month')
assertEqual(lunar.dayLabel(2026, 2, 19), '初三', '2026-02-19 is the third lunar day')
assertEqual(lunar.dayLabel(2026, 3, 4), '十六', '2026-03-04 is the sixteenth lunar day')
assertEqual(lunar.dayLabel(2026, 3, 10), '廿二', '2026-03-10 is 廿二')
// A solar term outranks the ordinary day name, so 正月初二 in 2026 prints 雨水.
assertEqual(lunar.dayLabel(2026, 2, 18), '雨水', 'a solar term replaces the day name')

// The lunar year is not the Gregorian one in January.
assertEqual(lunar.solarToLunar(2025, 1, 1).lunarYear, 2024, '2025-01-01 belongs to lunar year 2024')
assertEqual(lunar.solarToLunar(2025, 1, 5).lunarYear, 2024, '2025-01-05 belongs to lunar year 2024')

// ---- Solar terms -----------------------------------------------------------
const termCases = [
  [2024, 2, 4, '立春'],
  [2025, 2, 3, '立春'],
  [2026, 2, 4, '立春'],
  [2024, 4, 4, '清明'],
  [2025, 4, 4, '清明'],
  [2026, 4, 5, '清明'],
  [2024, 12, 21, '冬至'],
  [2025, 12, 21, '冬至'],
  [2026, 12, 22, '冬至'],
  [2025, 1, 5, '小寒'],
  [2026, 10, 8, '寒露'],
  [2026, 10, 23, '霜降']
]

for (const [y, m, d, expected] of termCases) {
  assertEqual(lunar.dayLabel(y, m, d), expected, `${y}-${m}-${d} is the solar term ${expected}`)
  assertEqual(lunar.dayInfo(y, m, d).kind, 'term', `${y}-${m}-${d} is classified as a solar term`)
}

// ---- Range degradation -----------------------------------------------------
assertEqual(lunar.dayLabel(1900, 1, 30), '', '1900-01-30 is before the table')
assertEqual(lunar.dayInfo(1900, 1, 30), null, '1900-01-30 has no lunar info')
assertEqual(lunar.dayLabel(1899, 12, 31), '', '1899-12-31 is outside the table')
assertEqual(lunar.dayLabel(2101, 1, 1), '', '2101-01-01 is outside the table')
assertEqual(lunar.dayLabel(1900, 1, 31), '春节', '1900-01-31 is the first day of the table')
assertEqual(lunar.dayLabel(2100, 12, 31), '腊月', '2100-12-31 is inside the table')

// ---- Full-range invariants -------------------------------------------------
function eachDay(fromYear, fromMonth, fromDay, toYear, toMonth, toDay, visit) {
  const cursor = new Date(Date.UTC(fromYear, fromMonth - 1, fromDay))
  const end = Date.UTC(toYear, toMonth - 1, toDay)
  while (cursor.getTime() <= end) {
    visit(cursor.getUTCFullYear(), cursor.getUTCMonth() + 1, cursor.getUTCDate())
    cursor.setUTCDate(cursor.getUTCDate() + 1)
  }
}

let missing = 0
let wrongRange = 0
let festivalsInLeapMonth = 0
let tooLong = 0
const eveCounts = new Map()
const seenYears = new Set()

eachDay(1900, 1, 31, 2100, 12, 31, (y, m, d) => {
  const info = lunar.dayInfo(y, m, d)
  const labels = { '1': '春节', '2': '元宵节', '3': '龙抬头', '4': '上巳节',
                   '5': '端午节', '6': '七夕节', '7': '中元节', '8': '中秋节',
                   '9': '重阳节', '10': '腊八节', '11': '小年', '12': '除夕' }
  if (!info || !info.label) { missing++; return }
  if (info.lunarMonth < 1 || info.lunarMonth > 12 || info.lunarDay < 1 || info.lunarDay > 30) wrongRange++
  if (info.isLeap && info.kind === 'festival') festivalsInLeapMonth++
  if (info.label.length > 4) tooLong++
  if (info.isEve) eveCounts.set(info.lunarYear, (eveCounts.get(info.lunarYear) || 0) + 1)
  seenYears.add(info.lunarYear)
})

assertEqual(missing, 0, 'every day in 1900-01-31..2100-12-31 has a non-empty caption')
assertEqual(wrongRange, 0, 'every lunar month is 1-12 and every lunar day is 1-30')
assertEqual(festivalsInLeapMonth, 0, 'no day of a leap month matches a festival')
assertEqual(tooLong, 0, 'every caption is at most four characters')

// Lunar year 2100 ends in early 2101, outside the scanned Gregorian range, so
// it has no Eve in this window; every other lunar year has exactly one.
let badEveYears = []
for (const year of seenYears) {
  if (year === 2100) continue
  if ((eveCounts.get(year) || 0) !== 1) badEveYears.push(year)
}
assertDeepEqual(badEveYears, [], 'each lunar year 1900-2099 has exactly one New Year\'s Eve')

// Every solar term appears exactly once per Gregorian year.
function termCounts(year) {
  const counts = new Array(24).fill(0)
  for (let month = 1; month <= 12; month++) {
    let day = 1
    while (true) {
      const date = new Date(Date.UTC(year, month - 1, day))
      if (date.getUTCMonth() !== month - 1) break
      const index = lunar.solarTermIndex(year, month, day)
      if (index !== null) counts[index]++
      day++
    }
  }
  return counts
}

let badTermYears = []
for (let year = 1900; year <= 2100; year++) {
  if (termCounts(year).some(count => count !== 1)) badTermYears.push(year)
}
assertDeepEqual(badTermYears, [], 'each of the 24 solar terms occurs exactly once per year, 1900-2100')

// ---- boolValue -------------------------------------------------------------
assertEqual(lunar.boolValue(undefined, true), true, 'boolValue defaults when unset')
assertEqual(lunar.boolValue(null, true), true, 'boolValue defaults on null')
assertEqual(lunar.boolValue(false, true), false, 'boolValue keeps a real boolean false')
assertEqual(lunar.boolValue('false', true), false, 'boolValue understands the string "false"')
assertEqual(lunar.boolValue('FALSE', true), false, 'boolValue is case-insensitive')
assertEqual(lunar.boolValue('0', true), false, 'boolValue understands "0"')
assertEqual(lunar.boolValue('no', true), false, 'boolValue understands "no"')
assertEqual(lunar.boolValue('off', true), false, 'boolValue understands "off"')
assertEqual(lunar.boolValue('true', false), true, 'boolValue understands "true"')
assertEqual(lunar.boolValue('1', false), true, 'boolValue understands "1"')
assertEqual(lunar.boolValue('on', false), true, 'boolValue understands "on"')
assertEqual(lunar.boolValue('banana', true), true, 'boolValue falls back on nonsense')

// ---- Panel wiring ----------------------------------------------------------
const panelSource = fs.readFileSync(path.join(root, 'Panel.qml'), 'utf8')
const widgetSource = fs.readFileSync(path.join(root, 'BarWidget.qml'), 'utf8')

assert(/import "Lunar\.js" as Lunar/.test(panelSource), 'Panel imports Lunar.js')
assert(/Lunar\.dayInfo\(cell\.year, cell\.month \+ 1, cell\.day\)/.test(panelSource),
  'Panel converts monthGrid\'s zero-based month before calling Lunar')
assert(/t === "l" \|\| t === "L"/.test(panelSource), 'l toggles the lunar caption')
assert(/setting\("showLunar", true\)/.test(panelSource), 'showLunar defaults to true')
assert(/persistSettings\(\{ showLunar:/.test(panelSource), 'the toggle is persisted')
assert(!/\.pragma|\.import/.test(fs.readFileSync(path.join(root, 'Lunar.js'), 'utf8')),
  'Lunar.js uses neither .pragma nor .import, so node can require it')

// ---- Identity ---------------------------------------------------------------
// The plugin is published under its own id, so the manifest, the bar widget and
// the panel must all agree, and none of them may still claim to be the
// built-in clock: the reserved omarchy.clock id would be rejected by the
// registry, and a stale Panel moduleName would silently break the
// persistSettings -> updateEntryInline path.
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'))
const pluginId = manifest.id

assert(pluginId === 'io.github.twelvejie.lunar-clock', 'manifest keeps its published id')
assert(!pluginId.startsWith('omarchy.'), 'the id avoids the reserved omarchy.* namespace')
assert(!manifest.omarchy || !manifest.omarchy.clonedFrom, 'the clone-only clonedFrom field is gone')
assertEqual(manifest.entryPoints.barWidget, 'BarWidget.qml', 'the entry point still names BarWidget.qml')

assert(new RegExp(`moduleName: "${pluginId.replace(/\./g, '\\.')}"`).test(widgetSource),
  'BarWidget declares the published id as its moduleName')
assert(new RegExp(`target: "${pluginId.replace(/\./g, '\\.')}"`).test(widgetSource),
  'BarWidget owns the IpcHandler for the published id')
assert(new RegExp(`moduleName: "${pluginId.replace(/\./g, '\\.')}"`).test(panelSource),
  'Panel declares the published id as its moduleName')
assert(new RegExp(`ipcTarget: "${pluginId.replace(/\./g, '\\.')}"`).test(panelSource),
  'Panel declares the published id as its ipcTarget')

// Panel.qml's moduleName is what persistSettings passes to updateEntryInline,
// so a mismatch here loses settings on restart rather than erroring.
const panelModuleName = (panelSource.match(/^\s*moduleName: "(.+)"$/m) || [])[1]
assertEqual(panelModuleName, pluginId, "the panel's moduleName matches the manifest id")

for (const [name, source] of [['BarWidget.qml', widgetSource], ['Panel.qml', panelSource], ['manifest.json', JSON.stringify(manifest)]]) {
  assert(!source.includes('omarchy.clock'), `${name} no longer claims the built-in clock's id`)
}

// Model.js stays byte-identical to the built-in, so a future upstream sync
// remains a clean diff.
const builtin = '/usr/share/omarchy/shell/plugins/panels/clock'
if (fs.existsSync(builtin + '/Model.js')) {
  assertEqual(fs.readFileSync(path.join(root, 'Model.js'), 'utf8'),
    fs.readFileSync(builtin + '/Model.js', 'utf8'),
    'Model.js is still byte-identical to the built-in clock')
}
JS
