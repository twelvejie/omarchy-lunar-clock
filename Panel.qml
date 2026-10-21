import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Events.js" as Events
import "Lunar.js" as Lunar

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "io.github.twelvejie.lunar-clock"
  ipcTarget: "io.github.twelvejie.lunar-clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // ---- Todos and anniversaries. One JSON file under the user's data
  //      directory holds both, and clicking a day opens that day's detail
  //      block under the grid. Keys are "yyyy-MM-dd", the same identity the
  //      grid already uses for today.
  readonly property string xdgDataHome: Quickshell.env("XDG_DATA_HOME") !== ""
    ? Quickshell.env("XDG_DATA_HOME")
    : Quickshell.env("HOME") + "/.local/share"
  readonly property string eventsDir: xdgDataHome + "/io.github.twelvejie.lunar-clock"
  readonly property string eventsPath: eventsDir + "/events.json"

  property var events: Events.emptyEvents()
  property bool eventsLoaded: false
  property string selectedKey: ""
  property bool anniversaryYearly: true

  readonly property var selectedDate: Events.dateFromKey(selectedKey)
  readonly property var selectedEvents: Events.eventsForDate(events, selectedKey)
  readonly property var selectedLunar: {
    if (!selectedDate || !showLunar) return null
    return Lunar.dayInfo(selectedDate.getFullYear(), selectedDate.getMonth() + 1, selectedDate.getDate())
  }
  // True while a text field in the day detail owns the keys, so the panel's
  // shortcut handler steps aside the same way it does for the life fields.
  readonly property bool entryEditing: todoField.activeFocus || annivField.activeFocus || annivYearField.activeFocus

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property string nextWeekStartLabel: Qt.locale().dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  // Whether each day cell carries the lunar/festival/solar-term caption.
  // On by default; `l` flips it and persists the choice.
  readonly property bool showLunar: Lunar.boolValue(setting("showLunar", true), true)



  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(40)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  // The lunar caption's reserved line. A fixed height means a cell with no
  // caption (feature off, or a date outside the 1900-2100 table) keeps its
  // number at the same y as every other cell.
  readonly property int lunarLineHeight: Math.round(Style.font.caption * 1.35)

  // The bar's monospace family carries no CJK glyphs. Left to fontconfig, the
  // fallback lands on whichever Noto CJK face it prefers (in practice KR,
  // whose glyph forms are not the simplified ones), so name an SC face
  // explicitly and fall back to the bar's family only when none is installed.
  readonly property string lunarFontFamily: {
    var families = Qt.fontFamilies()
    var preferred = ["Noto Sans Mono CJK SC", "Noto Sans CJK SC", "Source Han Sans SC", "Noto Sans SC"]
    for (var i = 0; i < preferred.length; i++)
      if (families.indexOf(preferred[i]) !== -1) return preferred[i]
    return root.contentFontFamily
  }

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    if (root.selectedKey !== "") root.clearSelection()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // ---- Day selection and editing. Clicking a day both selects it and, when
  //      it came from the neighbouring month, steps the grid onto its month so
  //      the detail block and the grid never disagree about where you are.
  function selectDay(cell) {
    if (!cell || !cell.key) return
    if (cell.year !== viewYear || cell.month !== viewMonth) {
      root.viewYear = cell.year
      root.viewMonth = cell.month
    }

    var reopening = root.selectedKey !== String(cell.key)
    root.selectedKey = cell.key
    root.anniversaryYearly = true
    Qt.callLater(function() {
      if (root.selectedKey !== String(cell.key)) return
      // Clicking the day that is already open only moves the keys back to
      // its field; clearing it would throw away a half-typed entry.
      if (reopening) {
        todoField.text = ""
        annivField.text = ""
        annivYearField.text = String(cell.year)
      }
      todoField.forceActiveFocus()
    })
  }

  function selectDate(key) {
    var parts = Events.keyParts(key)
    if (!parts) return
    root.selectDay({ key: String(key), year: parts.year, month: parts.month, day: parts.day })
  }

  function clearSelection() {
    root.selectedKey = ""
    todoField.text = ""
    annivField.text = ""
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  function focusTodoField() {
    todoField.forceActiveFocus()
    todoField.selectAll()
  }

  function focusAnniversaryField() {
    annivField.forceActiveFocus()
    annivField.selectAll()
  }

  function saveEvents() {
    // Writing before the file has been read at least once would replace
    // whatever it held with this session's empty starting point.
    if (!root.eventsLoaded) return
    eventsFile.setText(Events.serializeEvents(root.events))
  }

  function addTodoFromField() {
    if (root.selectedKey === "") return
    if (Events.eventText(todoField.text) === "") return
    root.events = Events.addTodo(root.events, root.selectedKey, todoField.text, Events.newEventId("t"))
    root.saveEvents()
    todoField.text = ""
    todoField.forceActiveFocus()
  }

  function toggleTodo(id) {
    var todos = root.selectedEvents.todos
    for (var i = 0; i < todos.length; i++)
      if (todos[i].id === id) {
        root.events = Events.setTodoDone(root.events, id, !todos[i].done)
        root.saveEvents()
        return
      }
  }

  function removeTodo(id) {
    root.events = Events.removeTodo(root.events, id)
    root.saveEvents()
  }

  function addAnniversaryFromField() {
    if (root.selectedKey === "") return
    if (Events.eventText(annivField.text) === "") return
    root.events = Events.addAnniversary(root.events, root.selectedKey, annivField.text,
      parseInt(annivYearField.text, 10), root.anniversaryYearly, Events.newEventId("a"))
    root.saveEvents()
    annivField.text = ""
    annivField.forceActiveFocus()
  }

  function removeAnniversary(id) {
    root.events = Events.removeAnniversary(root.events, id)
    root.saveEvents()
  }

  function anniversaryLabel(anniversary) {
    var year = selectedDate ? selectedDate.getFullYear() : root.today.getFullYear()
    return Events.anniversaryLabel(anniversary, year)
  }

  function dayMarkers(cell) {
    return Events.dayMarkers(root.events, cell ? cell.key : "")
  }

  // Escape in a detail field hands the keys back to the panel but keeps what
  // was typed: losing a half-written entry to a stray keypress is worse than
  // leaving it in the field.
  function handleEntryKey(event) {
    if (event.key !== Qt.Key_Escape) return
    keyCatcher.forceActiveFocus()
    event.accepted = true
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  function toggleLunar() {
    persistSettings({ showLunar: !root.showLunar })
  }

  // A cell's caption, or null when the feature is off or the date falls
  // outside the lunar table. monthGrid() counts months from zero; the lunar
  // tables count from one.
  function lunarInfoFor(cell) {
    if (!cell || !root.showLunar) return null
    return Lunar.dayInfo(cell.year, cell.month + 1, cell.day)
  }

  // Festivals take the accent, solar terms a softer accent, the first of a
  // lunar month the ordinary day ink, and everything else one step dimmer.
  function lunarColor(info) {
    if (!info) return "transparent"
    if (info.kind === "festival") return Style.selectedStateColor(root.contentForeground, Color.accent)
    if (info.kind === "term") return Style.hoverStateColor(root.contentForeground, Color.accent)
    if (info.kind === "first") return Qt.darker(root.contentForeground, 1.5)
    return Qt.darker(root.contentForeground, 1.75)
  }

  // Locale short day names, trimmed of the trailing period some locales
  // carry ("man." -> "MAN") so the header row stays a clean band of caps.
  function weekdayLabel(weekday) {
    return String(Qt.locale().dayName(weekday, Locale.ShortFormat)).replace(/\.$/, "").toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  // ---- Event storage. FileView writes files, never the directory holding
  //      them, so make that first. A missing file is a fresh install, not an
  //      error: it loads as an empty list and the first write creates it.
  Process {
    id: makeEventsDir
    command: ["mkdir", "-p", root.eventsDir]
    running: true
  }

  FileView {
    id: eventsFile
    path: root.eventsPath
    preload: true
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.events = Events.parseEvents(text())
      root.eventsLoaded = true
    }
    onLoadFailed: {
      root.events = Events.emptyEvents()
      root.eventsLoaded = true
    }
    onFileChanged: reload()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife || root.entryEditing
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      // Escape backs out one step at a time: an open day first, then the
      // panel. Closing outright would throw away the day being looked at.
      onCloseRequested: root.selectedKey !== "" ? root.clearSelection() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
        else if (t === "l" || t === "L") root.toggleLunar()
        else if (t === "a") root.focusTodoField()
        else if (t === "A") root.focusAnniversaryField()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      id: dayCell
                      required property var modelData

                      // Null when the caption is switched off or the date
                      // falls outside the 1900-2100 table; the cell then
                      // keeps an empty reserved line rather than a wrong one.
                      readonly property var lunar: root.lunarInfoFor(dayCell.modelData)
                      readonly property bool selected: root.selectedKey === dayCell.modelData.key
                      readonly property var marks: root.dayMarkers(dayCell.modelData)

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      // Today is outlined, not filled: a lit-up block shouts
                      // over a grid this quiet. The selected day is the one
                      // filled cell, because clicking is what picks it.
                      color: selected
                        ? Style.selectedFillFor(root.contentForeground, Color.accent)
                        : (dayCellMouse.containsMouse
                          ? Style.hoverFillFor(root.contentForeground, Color.accent)
                          : "transparent")
                      border.width: (modelData.today || selected) ? Style.spacing.hairline : 0
                      border.color: selected
                        ? Style.selectedBorderFor(root.contentForeground, Color.accent)
                        : Style.normalBorderFor(root.contentForeground, Color.accent)

                      MouseArea {
                        id: dayCellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectDay(dayCell.modelData)
                      }

                      // Two small dots in the corner: an anniversary in the
                      // accent, an open todo in the day ink. Done-only days
                      // keep the todo dot but dim it, so the mark still says
                      // "something is recorded here".
                      Row {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: Style.space(3)
                        anchors.rightMargin: Style.space(4)
                        spacing: Style.space(2)
                        opacity: dayCell.modelData.inMonth ? 1 : 0.5

                        Rectangle {
                          visible: dayCell.marks.anniversary
                          width: Style.space(4)
                          height: width
                          radius: width / 2
                          color: Style.selectedStateColor(root.contentForeground, Color.accent)
                        }

                        Rectangle {
                          visible: dayCell.marks.todo
                          width: Style.space(4)
                          height: width
                          radius: width / 2
                          color: dayCell.marks.openTodo
                            ? root.contentForeground
                            : Qt.darker(root.contentForeground, 2)
                        }
                      }

                      Column {
                        anchors.centerIn: parent
                        width: parent.width - Style.space(4)
                        spacing: Style.space(1)

                        Text {
                          width: parent.width
                          horizontalAlignment: Text.AlignHCenter
                          textFormat: Text.PlainText
                          text: dayCell.modelData.day
                          color: dayCell.modelData.inMonth
                            ? (dayCell.modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                            : Qt.darker(root.contentForeground, 2.2)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.body
                          font.bold: dayCell.modelData.today
                        }

                        // A reserved line box, so a cell with no caption sits
                        // exactly like every other cell instead of jumping
                        // its number up.
                        Text {
                          width: parent.width
                          height: root.lunarLineHeight
                          verticalAlignment: Text.AlignVCenter
                          horizontalAlignment: Text.AlignHCenter
                          textFormat: Text.PlainText
                          elide: Text.ElideRight
                          maximumLineCount: 1
                          text: dayCell.lunar ? dayCell.lunar.label : ""
                          color: root.lunarColor(dayCell.lunar)
                          font.family: root.lunarFontFamily
                          font.pixelSize: Style.font.caption
                          opacity: dayCell.modelData.inMonth ? 1 : 0.5
                        }
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "MAY" to "SEPTEMBER".
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- The selected day's todos and anniversaries. Only here once
          //      a day is clicked; the grid stays visible, so another day is
          //      always one click away.
          Item {
            visible: root.selectedKey !== ""
            width: parent.width
            height: visible ? dayDetail.height : 0

            Column {
              id: dayDetail
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(6)

              // The date itself, its lunar caption, and the way out.
              Item {
                width: parent.width
                height: Math.max(dayTitle.implicitHeight, Style.space(22))

                Row {
                  anchors.left: parent.left
                  anchors.right: dayClose.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  Text {
                    id: dayTitle
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.selectedDate
                      ? Qt.formatDate(root.selectedDate, "dddd, MMMM d")
                      : ""
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.selectedLunar ? root.selectedLunar.label : ""
                    color: root.lunarColor(root.selectedLunar)
                    font.family: root.lunarFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                PanelActionButton {
                  id: dayClose
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.rightMargin: -Style.space(4)
                  iconText: "󰅖"
                  tooltipText: "Close day"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.clearSelection()
                }
              }

              // ---- Todos. The circle toggles done; the row is the target.
              Repeater {
                model: root.selectedEvents.todos

                Item {
                  id: todoRow
                  required property var modelData
                  width: dayDetail.width
                  height: Style.space(22)

                  Rectangle {
                    id: todoBox
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(11)
                    height: width
                    radius: width / 2
                    color: todoRow.modelData.done
                      ? Style.selectedStateColor(root.contentForeground, Color.accent)
                      : "transparent"
                    border.width: todoRow.modelData.done ? 0 : Style.spacing.hairline
                    border.color: Style.hoverStateColor(root.contentForeground, Color.accent)
                  }

                  Text {
                    anchors.left: todoBox.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: todoDelete.left
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: todoRow.modelData.text
                    elide: Text.ElideRight
                    color: todoRow.modelData.done
                      ? Qt.darker(root.contentForeground, 1.55)
                      : root.contentForeground
                    font.family: root.lunarFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.strikeout: todoRow.modelData.done                  }

                  PanelActionButton {
                    id: todoDelete
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰅖"
                    tooltipText: "Delete todo"
                    foreground: Qt.darker(root.contentForeground, 1.6)
                    fontFamily: root.contentFontFamily
                    size: Style.space(22)
                    onClicked: root.removeTodo(todoRow.modelData.id)
                  }

                  MouseArea {
                    anchors.left: parent.left
                    anchors.right: todoDelete.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleTodo(todoRow.modelData.id)
                  }
                }
              }

              // Enter commits the todo and keeps the field focused for the
              // next one; Escape hands the keys back to the panel.
              Row {
                id: todoAddRow
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: todoField
                  width: todoAddRow.width - todoAddButton.width - todoAddRow.spacing
                  foreground: root.contentForeground
                  font.family: root.lunarFontFamily
                  placeholderText: "Add a todo…"
                  Keys.onPressed: function(event) { root.handleEntryKey(event) }
                  onAccepted: root.addTodoFromField()
                }

                PanelActionButton {
                  id: todoAddButton
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.space(26)
                  iconText: "󰐕"
                  tooltipText: "Add todo"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.addTodoFromField()
                }
              }

              // ---- Anniversaries. "SINCE" is the year the date began; it is
              //      what the ordinal on the right counts from. YEARLY is the
              //      default because that is what most anniversaries are.
              Repeater {
                model: root.selectedEvents.anniversaries

                Item {
                  id: anniversaryRow
                  required property var modelData
                  width: dayDetail.width
                  height: Style.space(22)

                  Rectangle {
                    id: anniversaryMark
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(6)
                    height: width
                    rotation: 45
                    color: Style.selectedStateColor(root.contentForeground, Color.accent)
                  }

                  Text {
                    anchors.left: anniversaryMark.right
                    anchors.leftMargin: Style.space(9)
                    anchors.right: anniversaryMeta.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: anniversaryRow.modelData.text
                    elide: Text.ElideRight
                    color: root.contentForeground
                    font.family: root.lunarFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    id: anniversaryMeta
                    anchors.right: anniversaryDelete.left
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.anniversaryLabel(anniversaryRow.modelData)
                    color: Qt.darker(root.contentForeground, 1.7)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }

                  PanelActionButton {
                    id: anniversaryDelete
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰅖"
                    tooltipText: "Delete anniversary"
                    foreground: Qt.darker(root.contentForeground, 1.6)
                    fontFamily: root.contentFontFamily
                    size: Style.space(22)
                    onClicked: root.removeAnniversary(anniversaryRow.modelData.id)
                  }
                }
              }

              Row {
                id: anniversaryAddRow
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: annivField
                  width: anniversaryAddRow.width - sinceLabel.width - annivYearField.width
                    - yearlyChip.width - anniversaryAddButton.width - anniversaryAddRow.spacing * 4
                  foreground: root.contentForeground
                  font.family: root.lunarFontFamily
                  placeholderText: "Add an anniversary…"
                  Keys.onPressed: function(event) { root.handleEntryKey(event) }
                  onAccepted: root.addAnniversaryFromField()
                }

                Text {
                  id: sinceLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: "SINCE"
                  color: Qt.darker(root.contentForeground, 1.7)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }

                TextField {
                  id: annivYearField
                  width: Style.space(48)
                  anchors.verticalCenter: parent.verticalCenter
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly
                  placeholderText: "year"
                  Keys.onPressed: function(event) { root.handleEntryKey(event) }
                  onAccepted: root.addAnniversaryFromField()
                }

                Rectangle {
                  id: yearlyChip
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(58)
                  height: Style.space(24)
                  radius: Style.cornerRadius
                  color: yearlyChipMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : (root.anniversaryYearly
                      ? Style.selectedFillFor(root.contentForeground, Color.accent)
                      : "transparent")
                  border.width: root.anniversaryYearly ? Style.spacing.hairline : 0
                  border.color: Style.selectedBorderFor(root.contentForeground, Color.accent)

                  Text {
                    anchors.centerIn: parent
                    text: root.anniversaryYearly ? "YEARLY" : "ONCE"
                    color: root.anniversaryYearly
                      ? Style.selectedStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.7)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }

                  MouseArea {
                    id: yearlyChipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.anniversaryYearly = !root.anniversaryYearly
                  }

                  PanelToolTip {
                    visible: yearlyChipMouse.containsMouse
                    text: root.anniversaryYearly ? "Repeats every year" : "This date only"
                    fontFamily: root.contentFontFamily
                  }
                }

                PanelActionButton {
                  id: anniversaryAddButton
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.space(26)
                  iconText: "󰐕"
                  tooltipText: "Add anniversary"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.addAnniversaryFromField()
                }
              }
            }
          }
        }
      }
    }
  }
}
