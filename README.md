# Chinese Lunar Clock

An Omarchy bar widget that adds the **Chinese lunar calendar** (农历) to the
built-in clock: the lunar date, the traditional festivals, and the twenty-four
solar terms (二十四节气) under every day in the calendar popup.

![The calendar popup showing lunar dates, festivals, and solar terms](preview.png)

## What it shows

Each day carries a caption beneath its Gregorian number:

- **Festivals** (accent colour) — 春节, 元宵节, 龙抬头, 上巳节, 端午节, 七夕节,
  中元节, 中秋节, 重阳节, 腊八节, 小年, and 除夕.
- **Solar terms** (softer accent) — all twenty-four, from 小寒 to 冬至.
- **The first of a lunar month** prints the month name, e.g. 九月; a leap month
  is marked 闰四月.
- **Every other day** prints its lunar day, 初二 … 三十.

Days from the neighbouring months keep their captions but are dimmed, the way
the Gregorian numbers already are. Press <kbd>l</kbd> in the popup to turn the
captions off; the choice is remembered.

Everything else about the widget is the built-in one: the same calendar grid,
ISO week numbers, week-start toggle (<kbd>w</kbd>), month stepping, year
progress bar, and the optional memento mori bar.

## Requirements

- Omarchy (the plugin uses the Quattro shell's bar-widget API)
- A CJK font. Omarchy ships `noto-fonts-cjk`; the widget asks fontconfig for a
  Simplified Chinese face explicitly so the captions use simplified glyph forms
  rather than whichever CJK fallback fontconfig happens to prefer.

The lunar table covers **1900-2100**. Outside that range the captions are simply
blank rather than wrong.

## Install

```bash
omarchy plugin add https://github.com/twelvejie/omarchy-lunar-clock.git --enable
```

To use it as a drop-in replacement for the built-in clock, disable the built-in
one so the bar does not show two clocks:

```bash
omarchy plugin disable omarchy.clock
```

Then click the clock to open the calendar.

## Configure

| Setting | Default | What it does |
|---|---|---|
| `showLunar` | `true` | Captions under each day. Also toggled with <kbd>l</kbd>. |

The label format is the built-in one and can be cycled by right-clicking the
clock; the lunar captions do not appear on the bar label itself.

### Keyboard

Inside the calendar popup:

| Key | Action |
|---|---|
| <kbd>l</kbd> | Toggle the lunar captions |
| <kbd>w</kbd> | Start weeks on Monday ⇄ Sunday |
| <kbd>[</kbd> / <kbd>]</kbd> | Previous / next month |
| <kbd>{</kbd> / <kbd>}</kbd> | Previous / next year |
| <kbd>t</kbd> | Back to today |

> The default `SUPER + CTRL + ALT + D` binding summons the built-in `omarchy.clock`,
> so once you replace it with this plugin, rebind it to
> `omarchy-shell shell toggle io.github.twelvejie.lunar-clock` in
> `~/.config/hypr/bindings.lua` if you want that shortcut to keep working.

## Remove

```bash
omarchy plugin remove io.github.twelvejie.lunar-clock
```

## Tests

```bash
./test/lunar-test.sh
```

The suite checks known festival and solar-term dates, leap months, New Year's
Eve on both a 廿九 and a 三十 ending, out-of-range degradation, and then sweeps
the whole 1900-2100 range asserting that every day resolves, that each of the
twenty-four solar terms occurs exactly once per year, that each lunar year has
exactly one 除夕, and that no day of a leap month ever matches a festival.

## Credits

- **[Omarchy](https://omarchy.org/)** by [37signals / DHH](https://github.com/basecamp/omarchy) —
  `BarWidget.qml`, `Panel.qml`, and `Model.js` are its clock widget and calendar
  panel (MIT), extended here with the lunar captions and the `l` toggle.
- **[chinese-calendar](https://github.com/tigertall/chinese-calendar)** by tiger —
  the lunar year table and conversion algorithm (MIT).
- **[omarchy_chinese_lunar_calendar](https://github.com/GaryLiuGTA/omarchy_chinese_lunar_calendar)**
  by Gary Liu — the solar-term calculation and the Simplified Chinese vocabulary
  (MIT).

See [THIRD-PARTY.md](THIRD-PARTY.md) for the full attribution and
[LICENSE](LICENSE) for the licence text.

## Licence

MIT.
