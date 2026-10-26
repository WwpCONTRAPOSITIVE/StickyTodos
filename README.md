StickyTodos · A Desktop To-Do Widget for Mac

StickyTodos is a lightweight macOS to-do app. By default, its window stays on the desktop behind other apps. You can also switch it to an always-on-top or standard window.

## Features

- Browse tasks by date: move between days, pick a date from the calendar, or jump back to today.
- Organize tasks into five categories: Finance Applications (金融申请), Study (学习), Events (活动), Life (生活), and Work (工作).
- Add, complete, edit, reschedule, and delete tasks. Bold selected parts of a task's text.
- Create daily, weekly, monthly, or yearly recurring tasks, with a separate completion state for each occurrence.
- Adjust the widget's position by dragging its translucent window.
- Save everything locally, with no account or cloud service required.

## Build

Requires macOS 13 or later and Xcode Command Line Tools. After cloning the repository, run these commands in Terminal on your Mac:

```bash
cd StickyTodos
bash build-mac.sh
open dist/StickyTodos.app
```

The built app is located at `dist/StickyTodos.app`. You can drag it into your Applications folder. Before rebuilding, quit any running older version from the `…` menu in the app's upper-right corner.

## Usage and Data

Choose a category at the bottom, type a task, and press Return or click `+` to add it to the date currently shown. Click a checkbox to mark a task complete. Double-click a task's text to edit it; select the text you want to bold, then click **B** or press `⌘B`. Right-click a task to change its date or delete it.

While the app is active, press `⌘⇧R` to open the new recurring task form. Choose a start date and a daily, weekly, monthly, or yearly repeat interval. The same option is available in the upper-right `…` menu. Each occurrence has its own completion state. Use the window-position menu in the upper-right corner to switch between desktop, always-on-top, and standard window modes.

Tasks are stored in `~/Library/Application Support/StickyTodos/tasks.json` and are not included in the Git repository. When upgrading, existing task dates are preserved. Older tasks without dates are assigned to the day you first open the new version. Tasks in the old “Content” (内容) category are moved to “Work” (工作).

So far, the project has been checked with the build script and static checks. Please use a macOS build to confirm compilation and the app's interface.
