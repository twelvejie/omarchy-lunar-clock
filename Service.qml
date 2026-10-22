import QtQuick
import Quickshell
import Quickshell.Io
import "Reminders.js" as Reminders
import "Events.js" as Events
import "Lunar.js" as Lunar

// Daily reminders for birthdays and anniversaries.
//
// A service plugin, so it runs whenever the shell does rather than only while
// the calendar is open. Once a day it reads the event store, finds every
// record whose date is within a week, and sends one notification per record.
//
// "Once a day" is enforced by stamping the record in the store itself rather
// than by holding a flag in memory: the shell restarts, the machine sleeps, the
// panel is reloaded on every plugin edit, and none of that may produce a second
// notification for the same day. The stamp lives in `reminded`, keyed by record
// id, and Reminders.js decides what is due from it.
Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") !== ""
    ? Quickshell.env("XDG_DATA_HOME")
    : Quickshell.env("HOME") + "/.local/share"
  readonly property string eventsDir: dataHome + "/io.github.twelvejie.lunar-clock"
  readonly property string eventsPath: eventsDir + "/events.json"

  // The store as last read, and whether a read has happened at all. Writing
  // before the first read would replace the file with this session's empty
  // starting point.
  property var events: Events.emptyEvents()
  property var reminded: ({})
  property bool loaded: false

  // The day the last check was made for. A long-lived timer re-checks every
  // hour so that waking from sleep, or crossing midnight while running, picks
  // the new day up without waiting for a restart.
  property string checkedOn: ""

  function todayParts() {
    var now = new Date()
    return { year: now.getFullYear(), month: now.getMonth(), day: now.getDate() }
  }

  function todayKey() {
    var t = todayParts()
    return t.year + "-" + pad2(t.month + 1) + "-" + pad2(t.day)
  }

  function pad2(value) {
    var n = Number(value)
    return (n < 10 ? "0" : "") + n
  }

  // Reading is asynchronous: `check` kicks off a reload and the decision is
  // made in onLoaded, so a stale in-memory copy can never be used to decide
  // whether to notify.
  function check() {
    if (!root.loaded) {
      eventsFile.reload()
      return
    }
    deliver()
  }

  function deliver() {
    if (!root.loaded) return

    var today = todayParts()
    var due = Reminders.dueReminders(root.events, today, Lunar, root.reminded)
    root.checkedOn = todayKey()
    if (due.length === 0) return

    for (var i = 0; i < due.length; i++) notify(due[i], today)

    root.reminded = Reminders.stampReminded(root.events, due, today, root.reminded)
    save()
  }

  function notify(entry, today) {
    var sentence = Reminders.reminderText({ text: entry.text }, entry.occurrence, today, entry.lunarLabel)
    var headline = entry.days === 0 ? reminderTitle("today") : reminderTitle(entry.text)
    var body = entry.lunarLabel !== ""
      ? sentence + "\n" + entry.dateLabel
      : sentence

    // The panel is the thing worth opening when the notification is clicked,
    // so the click command targets the widget rather than doing nothing.
    // --exec must come last: it consumes the rest of the line as its argv.
    notifyProcess.command = [
      "omarchy-notification-send",
      "--app-name", "Chinese Lunar Clock",
      "-g", entry.days === 0 ? "󰃭" : "󰗖",
      "-i", "appointment-soon",
      "-u", entry.days === 0 ? "normal" : "low",
      headline,
      body,
      "--exec", "omarchy-shell", "io.github.twelvejie.lunar-clock", "open"
    ]
    notifyProcess.running = true
  }

  // Keeps the record's own name as the headline when there is one, so a glance
  // at the toast says who or what rather than repeating the body.
  function reminderTitle(text) {
    return text === "today" ? "Today" : text
  }

  function save() {
    if (!root.loaded) return
    var store = Events.normalizeEvents(root.events)
    store.reminded = root.reminded
    eventsFile.setText(JSON.stringify(store, null, 2) + "\n")
  }

  Component.onCompleted: {
    if (!dirProcess.running) dirProcess.running = true
    eventsFile.reload()
  }

  Process {
    id: dirProcess
    command: ["mkdir", "-p", root.eventsDir]
    onExited: eventsFile.reload()
  }

  Process {
    id: notifyProcess
  }

  FileView {
    id: eventsFile
    path: root.eventsPath
    preload: true
    watchChanges: true
    atomicWrites: true
    printErrors: false

    onLoaded: {
      var parsed = Events.parseEvents(text())
      root.reminded = parsed.reminded && typeof parsed.reminded === "object" ? parsed.reminded : ({})
      root.events = parsed
      root.loaded = true
      root.deliver()
    }

    // A fresh install has no file yet. That is not an error: it means there is
    // nothing to remind about, and the first write creates it.
    onLoadFailed: {
      root.events = Events.emptyEvents()
      root.reminded = ({})
      root.loaded = true
      root.deliver()
    }

    // The panel writes this file too. Reloading on change keeps this service's
    // copy in step, but does not re-notify: the stamp is already in the file.
    onFileChanged: reload()
  }

  // Hourly, so a machine that was asleep through midnight catches up on wake
  // without a restart. deliver() is idempotent for the day, so firing more
  // often than needed costs nothing.
  Timer {
    interval: 60 * 60 * 1000
    running: root.loaded
    repeat: true
    triggeredOnStart: true
    onTriggered: root.check()
  }

  // So the behaviour can be checked without waiting for the hour or for the
  // clock to roll over: `omarchy-shell reminders due` lists what would fire
  // now, and `omarchy-shell reminders check` runs the real path.
  IpcHandler {
    target: "reminders"

    function due(): string {
      var list = Reminders.dueReminders(root.events, root.todayParts(), Lunar, root.reminded)
      if (list.length === 0) return "none"
      return list.map(function(entry) {
        return entry.text + " (" + entry.dateLabel + ", " + entry.days + "d)"
      }).join("; ")
    }

    function check(): string {
      root.check()
      return "ok"
    }

    // Forget today's stamps so the next check notifies again. For trying the
    // feature out; it is deliberately not on the hourly path.
    function reset(): string {
      root.reminded = ({})
      root.save()
      return "ok"
    }
  }
}
