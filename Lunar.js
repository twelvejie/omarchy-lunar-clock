// Chinese lunar calendar (农历) for the clock panel: the lunar date, the
// twenty-four solar terms (二十四节气), and the traditional festivals, in
// Simplified Chinese.
//
// Pure date math: no Qt, no locale, no I/O, exactly like Model.js, so the
// whole file can be exercised from node. The QML side only reads `dayInfo`
// and renders `label`.
//
// Dates are defined against Beijing time (UTC+8, no DST) regardless of the
// system timezone, matching how the calendar itself is defined.
//
// The 1900-2100 year-info table and the solar-term calculation are adapted
// from the MIT-licensed chinese-calendar GNOME extension
// (https://github.com/tigertall/chinese-calendar), via the MIT-licensed
// garyliu.lunar-calendar Omarchy plugin
// (https://github.com/GaryLiuGTA/omarchy_chinese_lunar_calendar), and
// rewritten here in the same style as Model.js. Local changes: Simplified
// Chinese names only, no ganzhi/zodiac, and New Year's Eve derived from the
// lunar year's own length rather than the twelfth month's. See THIRD-PARTY.md
// in this directory for attribution and the full licence text.

var MS_PER_DAY = 86400000
var BEIJING_OFFSET_MS = 8 * 3600000

var LUNAR_BASE_YEAR = 1900
var LUNAR_MIN_YEAR = 1900
var LUNAR_MAX_YEAR = 2100

// 农历数据表 (1900-2100)。每个数值通过位运算提取:
// - 第1-4位:闰月月份,0 表示没有闰月
// - 第5-16位:1-12 月大小月信息,1 表示大月(30 天),0 表示小月(29 天)
// - 第17-20位:闰月大小,1 表示大月(30 天),0 表示小月(29 天)
var LUNAR_INFO = [
  0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2, // 1900-1909
  0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977, // 1910-1919
  0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, // 1920-1929
  0x06566, 0x0d4a0, 0x0ea50, 0x16a95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950, // 1930-1939
  0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557, // 1940-1949
  0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0, // 1950-1959
  0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, // 1960-1969
  0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6, // 1970-1979
  0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570, // 1980-1989
  0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x05ac0, 0x0ab60, 0x096d5, 0x092e0, // 1990-1999
  0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, // 2000-2009
  0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930, // 2010-2019
  0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530, // 2020-2029
  0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, // 2030-2039
  0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0, // 2040-2049
  0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06aa0, 0x1a6c4, 0x0aae0, // 2050-2059
  0x092e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4, // 2060-2069
  0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0, // 2070-2079
  0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160, // 2080-2089
  0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252, // 2090-2099
  0x0d520 // 2100
]

// 节气数据。The source project describes its accurate window as 2000-2053;
// the tables were checked here across 1900-2100 (every year yields each of
// the twenty-four terms exactly once).
var TROPICAL_YEAR = 365.24219878
var SOLAR_TERM_YEAR_BASE = 2000
var SOLAR_TERM_INFO = [
  7740, 28943, 50200, 71553, 93042, 114695,
  136531, 158559, 180770, 203149, 225658, 248267,
  270913, 293562, 316142, 338628, 360959, 383127,
  405098, 426887, 448488, 469939, 491257, 512497
]
var TERM_FIX_INFO = [10, 14, 8, 0, 17, -12, 0, -24, -27, -19, -50, -58, -13, -50, -39, -48, -36, 0, 0, 0, 0, 6, 30, 0]

// Month 11 is 冬月 in speech but 十一月 is what a calendar prints; month 12 is
// 腊月. The trailing 月 is appended at display time so leap months can take a
// 闰 prefix in front of the whole name.
var MONTH_NAMES = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "腊"]

var DAY_NAMES = [
  "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
  "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
  "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
]

var SOLAR_TERM_NAMES = [
  "小寒", "大寒", "立春", "雨水", "惊蛰", "春分",
  "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
  "小暑", "大暑", "立秋", "处暑", "白露", "秋分",
  "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
]

// Keyed "月-日" on the ordinary month numbering. A day in a leap month is
// never looked up here, so a 闰四月初五 cannot print 端午节.
var FESTIVALS = {
  "1-1": "春节", "1-15": "元宵节", "2-2": "龙抬头", "3-3": "上巳节",
  "5-5": "端午节", "7-7": "七夕节", "7-15": "中元节", "8-15": "中秋节",
  "9-9": "重阳节", "12-8": "腊八节", "12-23": "小年"
}

var EVE_NAME = "除夕"
var LEAP_WORD = "闰"
var MONTH_WORD = "月"

function beijingMidnightUtcMs(year, month, day) {
  return Date.UTC(year, month - 1, day) - BEIJING_OFFSET_MS
}

function utcMsToBeijingYMD(ms) {
  var t = new Date(ms + BEIJING_OFFSET_MS)
  return { year: t.getUTCFullYear(), month: t.getUTCMonth() + 1, day: t.getUTCDate() }
}

var LUNAR_BASE_MS = beijingMidnightUtcMs(1900, 1, 31) // 农历 1900 年正月初一

function leapMonth(year) {
  return LUNAR_INFO[year - LUNAR_BASE_YEAR] & 0xf
}

function leapMonthDays(year) {
  return leapMonth(year) ? ((LUNAR_INFO[year - LUNAR_BASE_YEAR] & 0x10000) ? 30 : 29) : 0
}

function lunarMonthDays(year, month) {
  return (LUNAR_INFO[year - LUNAR_BASE_YEAR] & (0x10000 >> month)) ? 30 : 29
}

function lunarYearDays(year) {
  var sum = 348
  for (var i = 0x8000; i > 0x8; i >>= 1) sum += (LUNAR_INFO[year - LUNAR_BASE_YEAR] & i) ? 1 : 0
  return sum + leapMonthDays(year)
}

// Gregorian date -> lunar date. Returns null outside the table; never throws.
// yearDay is the zero-based day within the lunar year, used below to find New
// Year's Eve without assuming the twelfth month has thirty days.
function solarToLunar(year, month, day) {
  if (year < LUNAR_MIN_YEAR || year > LUNAR_MAX_YEAR) return null

  var offset = Math.floor((beijingMidnightUtcMs(year, month, day) - LUNAR_BASE_MS) / MS_PER_DAY)
  if (offset < 0) return null

  var lunarYear = LUNAR_BASE_YEAR
  var temp = 0
  for (var y = LUNAR_BASE_YEAR; y <= LUNAR_MAX_YEAR && offset > 0; y++) {
    temp = lunarYearDays(y)
    if (offset < temp) break
    offset -= temp
    lunarYear++
  }
  if (lunarYear > LUNAR_MAX_YEAR) return null

  var yearDay = offset

  var leap = leapMonth(lunarYear)
  var isLeap = false
  var lunarMonth = 1
  for (var i = 1; i < 13; i++) {
    if (leap > 0 && i === leap + 1 && !isLeap) {
      --i
      isLeap = true
      temp = leapMonthDays(lunarYear)
    } else {
      temp = lunarMonthDays(lunarYear, i)
    }

    if (isLeap && i === leap + 1) isLeap = false

    if (offset < temp) break
    offset -= temp
    lunarMonth++
  }

  if (isLeap) {
    lunarMonth = leap
  } else if (leap > 0 && lunarMonth > leap) {
    lunarMonth--
  }

  return {
    lunarYear: lunarYear,
    lunarMonth: lunarMonth,
    lunarDay: offset + 1,
    isLeap: isLeap,
    yearDay: yearDay
  }
}

// Index into SOLAR_TERM_NAMES for this Gregorian day, or null. The term year
// is the Gregorian year even when the lunar year is the one before, so this
// must always be called with the Gregorian date.
function solarTermIndex(year, month, day) {
  if (year < LUNAR_MIN_YEAR || year > LUNAR_MAX_YEAR) return null

  var first = (month - 1) * 2
  for (var k = 0; k < 2; k++) {
    var index = first + k
    var offMs = ((year - SOLAR_TERM_YEAR_BASE) * TROPICAL_YEAR * 24 * 60 +
      SOLAR_TERM_INFO[index] + TERM_FIX_INFO[index]) * 60000 +
      beijingMidnightUtcMs(SOLAR_TERM_YEAR_BASE, 1, 1)
    var date = utcMsToBeijingYMD(offMs)
    if (date.year === year && date.month === month && date.day === day) return index
  }
  return null
}

// Festival > solar term > month name on the first > ordinary day name.
// Returns {label, kind, ...} for the panel cell, or null outside the table.
function dayInfo(year, month, day) {
  var lunar = solarToLunar(year, month, day)
  if (!lunar) return null

  var term = solarTermIndex(year, month, day)
  var festival = lunar.isLeap ? "" : (FESTIVALS[lunar.lunarMonth + "-" + lunar.lunarDay] || "")

  // New Year's Eve is the lunar year's final day. Deriving it from the year's
  // own length gives exactly one per year whether the twelfth month ends on
  // 廿九 or 三十.
  var isEve = lunar.yearDay === lunarYearDays(lunar.lunarYear) - 1
  if (!festival && isEve) festival = EVE_NAME

  var label = ""
  var kind = ""

  if (festival) {
    label = festival
    kind = "festival"
  } else if (term !== null) {
    label = SOLAR_TERM_NAMES[term]
    kind = "term"
  } else if (lunar.lunarDay === 1) {
    label = (lunar.isLeap ? LEAP_WORD : "") + MONTH_NAMES[lunar.lunarMonth - 1] + MONTH_WORD
    kind = "first"
  } else {
    label = DAY_NAMES[lunar.lunarDay - 1]
    kind = "day"
  }

  return {
    label: label,
    kind: kind,
    lunarYear: lunar.lunarYear,
    lunarMonth: lunar.lunarMonth,
    lunarDay: lunar.lunarDay,
    isLeap: lunar.isLeap,
    isEve: isEve,
    solarTermIndex: term
  }
}

// The caption alone. Outside 1900-2100 this is an empty string, which the
// panel renders as a blank reserved line rather than a wrong date.
function dayLabel(year, month, day) {
  var info = dayInfo(year, month, day)
  return info ? info.label : ""
}

// shell.json is hand-editable, so accept the same vocabulary Style.boolToken
// does and normalise it before it reaches a binding.
function boolValue(value, fallback) {
  if (value === undefined || value === null) return fallback
  if (typeof value === "boolean") return value

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "true" || text === "1" || text === "yes" || text === "on") return true
  if (text === "false" || text === "0" || text === "no" || text === "off") return false
  return fallback
}

if (typeof module !== "undefined") {
  module.exports = {
    solarToLunar: solarToLunar,
    solarTermIndex: solarTermIndex,
    dayInfo: dayInfo,
    dayLabel: dayLabel,
    boolValue: boolValue,
    leapMonth: leapMonth,
    leapMonthDays: leapMonthDays,
    lunarMonthDays: lunarMonthDays,
    lunarYearDays: lunarYearDays
  }
}
