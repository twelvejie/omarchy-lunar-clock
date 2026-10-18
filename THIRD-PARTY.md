# Third-party notices

`Lunar.js` in this directory contains the Chinese lunar-calendar year table,
the solar-term constants, and the conversion algorithm adapted from the
projects below. The files `Model.js`, `BarWidget.qml`, and the structure of
`Panel.qml` come unmodified from the built-in `omarchy.clock` plugin shipped
with Omarchy.

## chinese-calendar

- Source: https://github.com/tigertall/chinese-calendar
- Licence: MIT
- Copyright (c) 2026 tiger

The 1900-2100 lunar year-info table (`LUNAR_INFO`) and the original lunar /
solar-term conversion algorithm.

## omarchy_chinese_lunar_calendar

- Source: https://github.com/GaryLiuGTA/omarchy_chinese_lunar_calendar
- Commit used as reference: `647ff452ac6c598242cdbf83a47ca9adf765e9d2`
  (2026-08-23)
- Licence: MIT
- Copyright (c) 2026 Gary Liu

The adaptation of the algorithm to plain QML-compatible JavaScript, the
solar-term constants (`TROPICAL_YEAR`, `SOLAR_TERM_INFO`, `TERM_FIX_INFO`),
and the Simplified Chinese festival and solar-term vocabulary.

## Local changes

- Simplified Chinese names only; no Traditional Chinese or English tables.
- No sexagenary year (干支) or zodiac (生肖) display.
- `solarTermIndex` additionally verifies the year and month, not just the
  day.
- New Year's Eve is derived from the lunar year's own length
  (`yearDay === lunarYearDays(year) - 1`) rather than from the twelfth
  month's length, so it is correct whether the year ends on 廿九 or 三十.
- `solarToLunar` reports `yearDay` so the panel can make that derivation.
- Caption formatting and the `showLunar` boolean normaliser are local.

## MIT Licence

The following licence text applies to both upstream projects above.

```
MIT License

Copyright (c) 2026 tiger
Copyright (c) 2026 Gary Liu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
