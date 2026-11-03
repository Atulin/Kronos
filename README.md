# Kronos

[![Release](https://github.com/Atulin/Kronos/actions/workflows/release.yml/badge.svg)](https://github.com/Atulin/Kronos/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/Atulin/Kronos)](./LICENSE)
[![GitHub release](https://img.shields.io/github/v/tag/Atulin/Kronos?label=latest%20release&sort=semver)](https://github.com/Atulin/Kronos/releases/latest)

Kronos is an Android app for tracking your daily schedule — start a task, stop
it when you're done, and Kronos keeps a searchable, grouped history of
everything you did and how long it took.

## Features

- **Tasks at a glance** — running tasks live at the bottom of the screen with
  their duration counting up in real time; finished tasks are grouped by day
  and sorted most-recent-first.
- **Task details** — tap any entry to view and edit its name, start and end
  times, notes, and color. Clearing the end time puts the task back into
  running state. Timestamps are stored as UTC so history survives timezone
  changes, and displayed in the device's local time.
- **Shared colors** — all tasks with the same name share one color; editing it
  in one place recolors them all. Custom swatches you add to the palette are
  remembered too.
- **Search and filtering** — filter finished tasks by name and by when they
  *started*, so they're easy to find even in months of history.
- **Backups** — a ZIP file of one CSV per content type (`tasks.csv`,
  `task_colors.csv`, …), each a spec-compliant spreadsheet-ready table.
  Export manually or schedule automatic backups to a folder of your choice.
- **Analytics** — see the average, median, minimum, and maximum duration for a
  task, either of the task itself or of time between one instance ending and
  the next starting, with a bar chart over any period: day, week, month, year,
  everything, or a custom range.

## Download

<a href="https://github.com/Atulin/Kronos/releases/latest">
  <img height="18" alt="GitHub" src="https://img.shields.io/badge/GitHub-100000?logo=github&logoColor=white" />
</a>
&nbsp;•&nbsp;
<a href="https://obtainium.imranr.dev/">
  <img height="18" alt="Obtainium" src="https://img.shields.io/badge/Obtainium-03A9F4?logo=androidauto&logoColor=white" />
</a>

### Manual (APK)

Grab the latest signed `Kronos-*.apk` from the
[releases page](https://github.com/Atulin/Kronos/releases/latest), open it on
your phone, and confirm the install — you'll need to allow installing apps
from your browser or file manager first.

### Obtainium

1. Install [Obtainium](https://obtainium.imranr.dev/).
2. Add app, and enter `https://github.com/Atulin/Kronos` as the source.
3. Obtainium tracks the GitHub releases and offers the newest signed APK as an
   in-app update, so you never have to come back here.

## Building

Clone the repository and build with Flutter (the release workflow pins
Flutter 3.47.8, but any recent stable should work):

```sh
flutter pub get
flutter run              # or: flutter build apk --release
```

## License

Distributed under the [MIT License](./LICENSE).
