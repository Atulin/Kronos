# Kronos

Kronos is a Flutter application for Android used to track daily schedule.

## Design

At the top, bar with app icon and name to the left, search button to the right. Tapping the app icon opens the settings screen, tapping the search button opens the
search toast with searchbar and two datetime selectors: one for lower bound and one for upper bound. Searching the text in the searchbar should filter the list of
finished tasks described below. Setting the upper and lower bounds should similarly, show only tasks *started* in the given range.

In the center, a virtualized list of finished schedule items. Each with a name on the left and duration on the right. All items grouped into days, with a date in a
customizable format as a divider, based on when the given item was *started*. The list should be scrollable, sorted from most recent at the top. Each task can be
tapped to see it's details (name, duration, start datetime, end datetime, color). The details screen should make the name, start, and end editable. Checks should be
introduced to prevent the end date from being before the start date, ideally at selection step (i.e. do not show invalid datetimes). The details screen should also
have a button to delete the task, with a toast confirmation. The user should also be able to remove the end date, signifying the task is still running. In such an
event, the task should be moved from the finished list, to the running list described below. The color should be editable with a color picker. Each item on the list
should have a 5px colored border on the left side, with the color of the task. All tasks sharing the same name (case-insensitive) should have the same color, and editing it in one should change it for all (color should probably be stored independently of the tasks, only using the name as a key).

At the bottom, a text input for adding new items, and a list of currently running items above it. Entering any text into the input should suggest existing items of
that name. Matching should be case-insensitive and, ideally, fuzzy. Tapping a suggested item automatically starts it and cleans the input. User can also press a button
to start a newly-named task based on the input. All currently running tasks should show their name and duration (updated live), sorted from oldest at the top. Each
running task should have a button that stops it, which moves the task into the center list. Long-pressing it should show a toast with a button to delete it.

Data should be exportable to a file as JSON, and importable from one. A scheduled backup should also be implemented, with customizable frequency and directory. The
user should be given an option to disable the automatic backup. The user should also be able to encrypt the backup file with a password.

The user should have an option to enable biometrics (fingerprint, face, etc.) to unlock the app. If this option is enabled and set up, all the stored data should
be encrypted with said biometrics, and decrypted only on valid unlock. The user should be notified explicitly that their data will be encrypted and unrecoverable
in case of lost biometrics, if biometrics is enabled.

An analytics screen should allow the user to see the average duration of a given task, median, minimum, and maximum. It should also contain a bar graph showing the
duration change over time. All should be calculated for a given time period (day, week, month, year, total, custom range). Another analytics option should be to show
the same kinds of analytics, but for duration between the instances of the given task, from the end of one to the start of another.

All data should be persisted across app and device restarts.

### Color palette

- Dark mode
  - Background: `#0D0D0D`
  - Light background: `#373438`
  - Brand color: `#2C6581`
  - Bright accent: `#05F2DB`
  - Subtle accent: `#4EABBF`

## Milestones

We will be following the milestones one by one. Once you've completed one, stop and wait for the user's go-ahead or comments, suggestions, and reported bugs.

1. Basic functionality – add tasks, see tasks in progress, see completed tasks, task details, delete tasks, edit tasks.
2. Search and filtering
3. Backup and restore
4. Analytics
5. Biometrics and backup encryption
6. F-Droid release

## Instructions

- Make sure to use new and supported versions of packages.
- Code should be clean and readable, without unnecessary abstractions.
- Files should be reasonable in length, split the app into stateless and stateful components where it makes sense rather than writing everything in one huge block.
