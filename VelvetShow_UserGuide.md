# Velvet Show — User Guide

*The live musician's stage companion*

---

## Table of Contents

1. [Welcome to Velvet Show](#1-welcome-to-velvet-show)
2. [Installation](#2-installation)
3. [First Launch](#3-first-launch)
4. [Understanding Songs vs Shows](#4-understanding-songs-vs-shows)
5. [Importing Songs](#5-importing-songs)
6. [Creating Your First Show](#6-creating-your-first-show)
7. [Playing Songs](#7-playing-songs)
8. [Queue and Play Next](#8-queue-and-play-next)
9. [Live Notes](#9-live-notes)
10. [MIDI Cues and Automation](#10-midi-cues-and-automation)
11. [Stage Screen](#11-stage-screen)
12. [PANIC Mode](#12-panic-mode)
13. [Backup and Data Safety](#13-backup-and-data-safety)
14. [Keyboard Shortcuts](#14-keyboard-shortcuts)
15. [Troubleshooting](#15-troubleshooting)
16. [Frequently Asked Questions](#16-frequently-asked-questions)

---

## 1. Welcome to Velvet Show

Velvet Show is a macOS app designed for live musicians. It manages your setlists, plays your backing tracks, displays lyrics and notes on a second screen, and fires MIDI cues — all from a single window on your Mac.

**What Velvet Show is for:**
- Organizing songs into shows with a clear setlist
- Playing audio files reliably on stage
- Showing lyrics, chord sheets, and performance notes on a stage display
- Triggering MIDI scenes (lights, DMX) automatically as songs play
- Keeping the whole show under control with one keyboard

**What Velvet Show is not:**
- A DAW or recording app
- A DJ mixing application
- A streaming service

---

## 2. Installation

Velvet Show is distributed as a `.dmg` file.

1. Open the `.dmg` and drag **VELVET SHOW** into your Applications folder.
2. Launch it from Applications or Spotlight.
3. On first launch, macOS may ask you to confirm you want to open it. Click **Open**.

**System requirements:** macOS 14 or later, Apple Silicon or Intel Mac.

---

## 3. First Launch

When you open Velvet Show for the first time, a welcome sheet appears:

> *Would you like to explore Velvet Show with a guided demo?*

**Start Guided Tour** loads a demo show with sample songs and walks you through the main features step by step. Recommended for new users.

**Skip for now** takes you straight to the empty app.

You can restart the tour at any time from the **Help** menu → **Start Guided Tour**.

---

## 4. Understanding Songs vs Shows

Velvet Show is built around two modes, switchable from the top center of the window:

### Songs mode

Your full music library. Songs are organized into **categories** (folders) in the left sidebar. Select a category to see its songs; select a song to open its detail panel.

Use Songs mode to:
- Browse your library
- Edit song metadata (title, genre, tempo, notes)
- Review MIDI cues and timing markers
- Import new songs

### Shows mode

Your setlists. Each **Show** is an ordered list of songs selected from your library.

Use Shows mode to:
- Build and reorder setlists
- Perform live — play songs, manage the queue, see remaining time

**Switching modes never interrupts playback.** You can browse Songs while a track is playing in Shows mode.

---

## 5. Importing Songs

Velvet Show accepts **MP3, WAV, AIFF, and M4A** files.

### Basic import

1. Switch to **Songs** mode.
2. Click the **Import a Song** button (↓ arrow icon) in the top-right of the Categories sidebar.
3. Choose your audio file in the file picker.
4. If you have a **MediaFiles** folder configured, an import sheet opens where you choose the destination category. Otherwise the file is copied into the app's internal Media folder.

### Import sheet options

When the import sheet opens:
- **Destination Category** — choose an existing category or type a name to create a new one.
- **Conflict** — if a file with the same name already exists, choose *Keep both (rename)* or *Replace existing file*.
- Click **Import** to confirm.

### Setting up your MediaFiles folder

If your audio files are stored in a ShowBuddy MediaFiles folder, point Velvet Show to it via **Settings → Change audio library…** This allows Velvet Show to read files in place without duplicating them.

---

## 6. Creating Your First Show

1. Switch to **Shows** mode.
2. Click the **+** button (New Show) at the top of the Shows sidebar.
3. Give your show a name and optionally a color.
4. Click **Create**.

### Adding songs to a show

- In **Songs** mode, right-click any song → **Add to [Show Name]** (the currently selected show).
- In **Shows** mode, click **Open Songs (⌘B)** to open the Quick Songs panel on the right. Drag songs from there into the setlist, or double-click to add.
- Drag songs directly within the setlist to reorder them.

### Editing a show

Right-click a show in the sidebar for options:
- **Rename / Options** — rename, change color, add notes.
- **Duplicate Show** — create a copy with the same setlist.
- **Delete** — removes the show only; songs and audio files are not deleted.

To reorder songs within a show, click the **Edit** mode button (pencil/reorder icon) in the setlist header. Drag rows to reorder; click the trash icon on a row to remove a song from the show.

---

## 7. Playing Songs

### Starting playback

In **Shows** mode, select a song in the setlist. Press **Space** to play.

The transport bar in the bottom of the window shows:
- Current position and remaining time
- Play/Pause, Stop, and Return to Start buttons
- Volume control (±1 dB per click)
- AUTO SHOW toggle

### Stopping

- **Pause** — Space bar. Resumes from the same position.
- **Stop** — ⌘ + period (`.`). Sends the Stop Cue MIDI event (if configured) and returns to the beginning of the song.
- **Return to Start** — the ↩ button in the transport bar.

### Navigating songs

- **⌘ →** — load the next song in the setlist.
- **⌘ ←** — load the previous song.

### Show Safety (Safe Play)

When **Show Safety** is on (default), changing the loaded song while playback is active requires a **double-click** on the new song. This prevents accidental song changes on stage. Toggle it in **Settings → Show Safety**.

### Repeat Mode

Activating **Repeat Mode** (the repeat button in the setlist header) keeps played songs in the Remaining list — useful for rehearsals. A red banner appears when Repeat Mode is active. Disable it before performing.

### AUTO SHOW

The **AUTO** button in the transport bar enables automatic song chaining. When a song ends, Velvet Show automatically loads and plays the next song in the setlist using the transition configured per song. Useful for DJ-style continuous sets.

---

## 8. Queue and Play Next

The Queue lets you control the upcoming song order without touching the setlist.

### Play Next

Right-click any song in the setlist → **Play Next**. This song will play after the current one, regardless of setlist order.

### Add to Queue

Right-click a song → **Add to Queue** to add it at the end of the queue.

### Viewing the Queue

The **Queue** button in the setlist toolbar shows how many songs are queued. Click it to expand or collapse the queue panel inline.

For a larger view, click **Open Floating Queue** (or use the macwindow icon in the compact transport strip). This opens a separate floating window showing the full queue — useful on a wide screen where you want the queue always visible.

### Queue playback mode

Each item in the Queue has a mode:
- **Auto** — plays automatically after the previous song ends.
- **Stop** — pauses after the previous song; you manually trigger the queued song.

---

## 9. Live Notes

Live Notes are text attached to each song — lyrics, chord charts, count-ins, cue reminders, anything you need to read on stage.

### Adding notes to a song

1. In **Songs** mode, select a song.
2. The detail panel shows a **Memos & MIDI** card. Each memo is a block of text with an optional timecode, a Start MIDI event, and an End MIDI event.
3. To import lyrics from a text file, click **Import Lyrics** in the detail panel header.

### Viewing notes on stage

Notes appear on the **Stage Screen** (see Section 11). As the song plays, memos scroll automatically to match the current position.

The **Backup Prompter** (bottom of the main window) shows the same notes on your Mac screen if you don't have a second display.

---

## 10. MIDI Cues and Automation

Velvet Show can send MIDI messages to external hardware — lighting consoles, DMX controllers (via MaestroDMX), effects units, or any MIDI-compatible device.

### Setting up MIDI

Open **Settings** (gear icon in the toolbar) → **MIDI Output**. Select your MIDI destination from the **Sortie MIDI** picker (this lists all MIDI devices currently connected to your Mac).

Set the **Avance d'envoi** (send advance) if your lighting hardware has latency — for example, 50 ms means cues are sent 50 ms early so lights change on beat.

### MIDI events

MIDI events live in the **Velvet MIDI Library** (visible in Settings). Each event can contain one or more MIDI messages (Note On, CC, Program Change).

Attach events to memos in the song detail panel:
- **Start event** — fires when the memo's timecode is reached during playback.
- **End event** — fires when the memo's end time is reached.

### Rest Cue

The Rest Cue is a MIDI scene sent automatically when no song is playing — for example, to dim the lights between tracks. Configure it in Settings:
- Choose the MIDI event to send.
- Set a delay (immediate, 1 s, 2 s…).
- Choose when it triggers: on manual Stop, on natural song end, at the end of the last song, or between songs with AUTO SHOW off.

### MaestroDMX

If you use MaestroDMX, import your show file via **Settings → Import MaestroDMX** to create MIDI events mapped to MaestroDMX cue numbers automatically.

Control MaestroDMX brightness live from the **MASTER BRIGHTNESS** popover in the setlist toolbar.

---

## 11. Stage Screen

The Stage Screen (Prompter) displays your Live Notes full-screen on a second display — a TV backstage, an iPad via Sidecar, or any AirPlay display.

### Opening the Stage Screen

Click the **Prompter** button in the top-right toolbar. A separate window opens that you can move to your second display and set to full screen.

### What appears on the Stage Screen

- The current song name.
- Live Notes text, scrolling in sync with the song position.
- The next memo preview (upcoming lyric or cue).

### Prompter themes

Choose a theme for the Stage Screen independently of the main window. In the toolbar gear menu → **Prompter theme**.

### Status pill

The toolbar shows a status capsule indicating the current display state:
- **Prompter on second display** (green) — ideal concert setup.
- **Prompter on Mac** (orange) — second display not detected; window is open but on the main screen.
- **Prompter closed** (orange) — second display connected but Prompter window not open.
- **Mac only** (grey) — editing mode, no display concern.

---

## 12. PANIC Mode

PANIC is a safety net for moments when the stage display fails or you lose sight of your notes.

### Activating PANIC

Press **⌘⇧P**, or click the **🚨 PANIC** button in the top-right corner of the toolbar.

The Backup Prompter appears as a large overlay at the bottom of the main window, showing your current song's Live Notes in large text — readable from a distance.

The toolbar capsule turns red and shows **PANIC Active**.

### Deactivating PANIC

Press **⌘⇧P** again, or click **🚨 PANIC ON**.

PANIC mode does not affect audio playback or MIDI output.

---

## 13. Backup and Data Safety

### Automatic saving

Velvet Show saves your data automatically within 0.4 seconds of any change. The **Save status pill** in the toolbar shows the current state:
- **Ready** — no changes pending.
- **Saving…** — write in progress.
- **Saved** — last save time shown on hover.

All data is stored in:
`~/Library/Application Support/VELVET SHOW/VelvetShowState.json`

### Audio file backups

When you replace a song's audio file using **Replace Audio**, the original file is automatically backed up to:
`~/Library/Application Support/VELVET SHOW/AudioBackups/`

### What is and isn't stored

Velvet Show stores: shows, setlists, Live Notes, MIDI cues, trims, volume settings, colors, concert history.

Velvet Show **never modifies** your original audio files or ShowBuddy.db. Your source files are always safe.

### Restoring

If VelvetShowState.json is lost or corrupted, Velvet Show starts fresh. A `.bak` backup is kept alongside the main file and loaded automatically if the main file is unreadable.

---

## 14. Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| **Space** | Play / Pause |
| **⌘ →** | Load next song |
| **⌘ ←** | Load previous song |
| **⌘ .** | Stop |
| **⌘⇧P** | Toggle PANIC / Backup Prompter |
| **S** | Toggle Shows sidebar |
| **T** (in Shows mode) | Toggle Quick Songs panel |
| **T** (in Songs mode) | Toggle column focus (editor full width) |
| **⌘B** | Hide / Show Quick Songs |
| **⌘F** | Focus search bar |
| **ESC** | Clear search |

---

## 15. Troubleshooting

### "Audio folder: access expired" warning

macOS security-scoped bookmarks can expire after a system update or restart. Go to **Settings (gear) → Change audio library…** and reselect your MediaFiles folder to restore access.

### Songs are silent (no audio plays)

- Check that the audio folder warning is not showing in the toolbar.
- Make sure your audio files are in a format Velvet Show supports: MP3, WAV, AIFF, M4A.
- Confirm the file still exists at its original path (check the **Path** field in the song detail panel).

### MIDI cues are not firing

- Open **Settings** and verify a MIDI destination is selected under **Sortie MIDI**.
- Confirm your MIDI device is connected and powered on before launching Velvet Show (MIDI devices are scanned at startup).
- Check that the memo's Start event has MIDI messages attached (visible in the song detail panel under Memos & MIDI).

### The Stage Screen shows a blank window

- Make sure the Prompter window is on the second display, not behind another window.
- Confirm the current song has Live Notes attached. An empty memo list results in a blank Stage Screen.

### The app feels slow to respond when switching songs

Show Safety (Safe Play) may be enabled, requiring a double-click to confirm song changes during playback. This is intentional. Disable it in **Settings → Show Safety** if you prefer single-click changes.

### A show I created has disappeared

Shows are saved automatically. If a show is missing after a crash, check whether a `.bak` file exists in `~/Library/Application Support/VELVET SHOW/`. If VelvetShowState.json is corrupted, the `.bak` is loaded on next launch.

---

## 16. Frequently Asked Questions

**Can I use Velvet Show without a ShowBuddy database?**
Yes. Velvet Show works entirely on its own. Import songs directly via **Import a Song**. ShowBuddy import is optional for users migrating from that app.

**Does Velvet Show modify my original audio files?**
Never. Velvet Show reads audio files in place (or copies them to its own Media folder on import). Original files are untouched.

**Can I use Velvet Show with just one screen?**
Yes. Use the Backup Prompter (PANIC button) to see your notes on the main screen. It appears as a large overlay at the bottom of the main window.

**What audio formats are supported?**
MP3, WAV, AIFF (and .AIF), M4A.

**Can I control volume per song?**
Yes. In the setlist, use the volume ±1 dB buttons in the transport bar while a song is loaded. Volume settings are saved per song per show.

**Can two shows share the same songs?**
Yes. Songs live in your library; shows just reference them. Deleting a show never deletes songs.

**What happens if I accidentally reset a show?**
Resetting moves all played songs back to remaining — it does not delete anything. If you deleted a show, it cannot be recovered unless a `.bak` file was created before the deletion.

**Can I run Velvet Show on two Macs simultaneously?**
Not natively. VelvetShowState.json is a local file. If you sync it via iCloud Drive or Dropbox between machines, do not have both open at the same time as writes will conflict.

**How do I contact support?**
Email: alexandre.chalon@gmail.com  
Subject: Velvet Show

---

*Velvet Show — built for musicians, by a musician.*
