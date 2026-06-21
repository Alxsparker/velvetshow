# Velvet Show 0.9 Beta — User Guide

---

## Introduction

### What is Velvet Show?

Velvet Show is a macOS application for live musicians. It manages an audio library, prepares setlists, triggers professional audio transitions, associates prompter memos and MIDI events with each track — and lets you control everything remotely from an iPad or iPhone via **Velvet Remote**.

### Who is it for?

- Solo musicians and bands using backing tracks or playbacks
- Artists managing their own stage audio
- Sound engineers triggering MIDI cues from a setlist

### Core philosophy

Velvet Show reads from an existing library created by **ShowBuddy** (a shared SQLite database). It never modifies that database. All Velvet Show data — memos, queue, trim, volume, history, Velvet shows — is stored separately in a local JSON file.

---

## Installation

### macOS

1. Download the `.zip` or `.dmg` from velvetshow.app/beta
2. Drag **VELVET SHOW.app** into `/Applications`
3. On first launch, macOS may warn "Developer not identified" — right-click → Open to proceed
4. The app requests access to your audio files folder (macOS sandbox) — click **Allow**
5. If ShowBuddy is installed and its database is found automatically, the library loads with no further action. Otherwise, go to **Preferences → Library** to point to `ShowBuddy.db`

### Velvet Remote (iPhone / iPad)

1. Install **Velvet Remote** from TestFlight (link provided separately)
2. Make sure the iPhone or iPad is on the **same Wi-Fi network as the Mac**, or **connected via USB cable**
3. On first launch, iOS requests **Local Network** access — tap **Allow**
4. Velvet Remote automatically discovers Velvet Show via Bonjour — no IP address required

---

## Main Interface — Mac

The Mac interface is organized into two modes, accessible via the buttons at the top left of the main window.

### Modes

| Mode | Description |
|---|---|
| **Library** (Track Library) | Manage tracks, memos, MIDI, trim, volume |
| **Shows** (Show Library) | Setlists, live performance, queue |

---

### Toolbar (shared between modes)

| Element | Function |
|---|---|
| **Mode selector** (left) | Switch between Library and Shows |
| **Status capsule** (center) | Shows the current track + playback state, or "Ready" |
| **Save status** | Indicates whether state is saved (●) or pending |
| **⌘⇧P — Prompter panic** | Opens the emergency prompter panel inside the Shows window |
| **Settings button** | Opens MIDI settings, credits, and library information |

---

### Library Mode

Three-column layout:

**Left column — Categories**
Genres and categories. Selecting a category filters the center column.

**Center column — Tracks**
All tracks in the selected category. Each row shows:
- Title
- Genre (color-coded, customizable via Styles & Colors)
- Risk badge (recent play frequency)
- Duration

Double-click or press Enter to start playback immediately.

**Right column — Track Detail**
Detailed information for the selected track. Editable fields:
- **Memos** (Memos tab) — see Memos section
- **MIDI** (MIDI tab) — see MIDI section
- **Trim** — set in/out points for the audio file
- **Volume** — dB offset independent of system volume

---

### Shows Mode

Two-column layout (with optional additional columns):

**Left column — Shows Sidebar**
Lists all available shows:
- **ShowBuddy shows** (imported from the database, read-only)
- **Velvet shows** (created in the app, with customizable color)

The currently playing show is highlighted in gold.

Shortcut `S`: toggle the Shows sidebar.

**Main column — Setlist**
Tracks in the selected show. Each tile shows:
- Track title
- Genre and color
- Duration
- **NEXT** badge if the track is prioritized in the queue
- Active playback indicator
- Played / remaining indicator

At the bottom: **transport bar** (see Playback section).

**Quick Library column** (optional)
Toggle with `T`. Shows the full library alongside the setlist — drag tracks into the queue without leaving the performance view.

**Emergency Prompter panel** (optional)
Opened with `⌘⇧P`. Displays the current track's memos in a right-side panel, without opening the separate Prompter window.

---

### Prompter Window

A dedicated window (single instance) showing the current track's memos in large format, in real time. Intended for a second screen or stage monitor. Open via **Window → Prompter**.

### Floating Queue Window

A lightweight window showing the active playback queue. Opens automatically when a track is added to the queue from the Quick Library. Keep it visible throughout the concert.

---

## Audio Playback

### Controls

| Action | Keyboard shortcut | Description |
|---|---|---|
| **Play / Pause** | `Space` | Play or pause the selected track |
| **Next** | `⌘ →` | Skip to the next track (with transition) |
| **Previous** | `⌘ ←` | Return to the previous track |
| **Stop** | `⌘ .` | Stop playback with a fade-out |

### Available Transitions

The transition button in the transport bar selects the effect applied when **Next** is triggered.

| Transition | Duration | Description |
|---|---|---|
| **FADE** | 1.2 s | Standard crossfade. Both tracks overlap. |
| **SLOW FADE** | 3.0 s | Slow crossfade. For end-of-set moments. |
| **FILTER** | 2.0 s | Crossfade with low-pass filter sweep (stage effect). Used for all remote Next commands. |
| ECHO | — | *Not available in version 0.9* |
| BACKSPIN | — | *Not available in version 0.9* |

The selected transition is saved between sessions.

### Playback Behavior

- Playback stops naturally at the end of a track, unless a next track is queued (automatic mode).
- During a crossfade, the incoming track is shown as "now playing" from the start of the fade.
- The waveform timeline supports click and drag to scrub through the current track.

---

## Queue Manager

The queue is a list of tracks to play after the current one, independent of setlist order.

### Adding a track to the queue

**From Mac:** click a track in the setlist or Quick Library to add it. The floating queue window opens automatically.

**From iPhone:** tapping a track in the "Upcoming Songs" list sends a `prioritizeNext` command — the track is placed at the front of the queue **without starting playback**.

### Behavior when Next is triggered

When the user presses Next (Mac, iPad, or iPhone):

1. **Priority 1 — Queue:** if a track is at the front of the queue, it plays next with the Filter transition.
2. **Priority 2 — Setlist:** the next track in the setlist plays with the selected transition.

### Automatic vs Manual mode

- **Automatic:** a queued track starts automatically at the end of the current track.
- **Manual:** the track stays in the queue until Next is explicitly triggered.

---

## Memos

Memos are text annotations associated with positions in a track. They appear in the Prompter window and on the iPad remote timeline.

### Creating and editing

In the track detail view (Library mode → right column → Memos tab):
- **Add a memo:** click `+` — enter the text and the time position in seconds
- **Edit:** click a memo in the list
- **Delete:** select and press Delete
- **Short name:** short label displayed on the iPad timeline (max 28 characters; if empty, the start of the text is used)

### Display during playback

- The Prompter window shows the active memo in large format, centered
- The iPad timeline shows all memos as colored blocks
- The active memo is highlighted (lighter block) on the timeline

### MIDI memos

A memo can contain MIDI triggers (see MIDI section). A visual indicator distinguishes MIDI-enabled memos on the timeline.

---

## MIDI

### Destinations

Velvet Show sends MIDI messages to CoreMIDI destinations available on the Mac. Set the destination in **Settings → MIDI → Destination**.

### MIDI events

Each track can have MIDI events associated with it, triggered automatically at specific positions (at the start of a memo).

Supported message types:
- Note On / Note Off
- Program Change
- Control Change

### Automatic triggering

The MIDI scheduler activates as soon as playback starts. It monitors the current position and fires messages at the exact time defined in the memo.

> ⚠️ **Do not modify the MIDI scheduler during a live performance.** The scheduler is designed to remain stable once started.

### Precautions

- Verify the MIDI destination before each show (Settings → MIDI)
- MIDI events are not replayed when scrubbing backward in a track
- In rehearsal mode, MIDI memos are disabled

---

## Velvet Remote — iPad

### Connecting

1. Launch Velvet Remote on the iPad
2. The discovery screen lists available VELVET SHOW instances on the network
3. Tap the Mac's name to connect
4. The connection is remembered — subsequent launches reconnect automatically

### Automatic reconnection

If the connection is lost (Wi-Fi drop, Mac sleep), Velvet Remote reconnects automatically as soon as the network is restored. No user action required.

### Transport indicator

The badge in the top-left corner shows the connection state:

| Badge | Meaning |
|---|---|
| 🟢 wifi | Connected via Wi-Fi |
| 🟢 cable.connector | Connected via USB |
| 🟡 wifi | Connected (other interface) |
| 🔴 wifi.slash | Disconnected |

### iPad screen — Full description

**Fixed top band (semi-transparent black background)**

- Connection badge (transport type)
- Current track title (13pt bold)
- Remaining time (15pt black monospaced)
- `▶ NEXT TRACK NAME` (11pt, gold)
- **⏯** button (Play/Pause)
- **⏭** button (Next — applies Filter transition)

**Center area — Prompter**

Displays the current track's memos in large format, adapted to screen size. Font size scales automatically based on text length (42 to 96pt).

**Bottom bar — Timeline (96pt)**

Visual timeline of the current track:
- Dark rounded background
- **Progress fill:** left-to-right progress bar
- **Time grid:** 5 vertical lines (time markers)
- **Memo blocks:** colored rectangles representing memos — the active memo is highlighted
- **Playhead:** white vertical line showing current position
- **Remaining duration:** displayed bottom-right

---

## Velvet Remote — iPhone

### Connecting and reconnecting

Same as iPad (see above). The iPhone displays the compact remote control screen.

### iPhone screen — Full description

**Top area — Header (30% black background)**

- Connection badge (transport type)
- Current track title (16pt bold)
- Remaining time (28pt black monospaced)
- `→ NEXT TRACK NAME` (14pt semibold, gold)
- `→ TRACK +2 NAME` (12pt light, attenuated gold)

**Center area — Available tracks list**

Section header: **UPCOMING SONGS**

Scrollable list of all **unplayed** tracks in the current show, in setlist order. Each row shows:
- Position number (left column)
- Track title
- `→` icon if this track is the designated next

**Action:** tapping a track sends `prioritizeNext:<id>` to the Mac. The track is placed at the front of the queue. **Playback does not start immediately.**

The list updates in real time:
- A played track disappears from the list
- The track selected as next is highlighted (attenuated gold background)

**Bottom bar — Command bar (40% black background)**

Two wide buttons:

| Button | Icon | Action |
|---|---|---|
| **Play / Pause** | ⏯ | Sends `playPause` to the Mac |
| **Next** | ⏭ | Sends `nextTrack` to the Mac — plays the queued track or the next in setlist with Filter transition |

Buttons are disabled (dimmed) when Velvet Remote is disconnected.

---

## Network

### Protocol

Velvet Show and Velvet Remote communicate via **TCP on port 7777**, advertised via Bonjour (`_velvetshow._tcp`). Discovery is fully automatic on the local network.

### USB vs Wi-Fi

- **USB:** plug the iPhone/iPad with an Apple cable — the `wiredEthernet` interface is detected automatically. Takes priority over Wi-Fi when available.
- **Wi-Fi:** standard local network connection. Works with any router.

Transport type is detected automatically and shown in real time in the badge.

### Behavior on network loss

- **Velvet Show (Mac):** the server restarts automatically with exponential backoff (1 → 2 → 4 → 8 → 16 → 30 s) on port errors. No intervention required.
- **Velvet Remote:** automatic reconnection as soon as the network is restored. The last known server is remembered.
- Commands not received during a disconnection are lost — playback continues normally on the Mac.

---

## Troubleshooting

**Velvet Remote cannot find the Mac**
- Confirm Mac and iPhone/iPad are on the **same Wi-Fi network**, or connected via USB
- Confirm VELVET SHOW is running on the Mac
- Check that the **Local Network** permission is granted to Velvet Remote (iOS Settings → Privacy → Local Network)
- Wait 5–10 seconds — Bonjour takes a moment to propagate the service

**iPad shows "Searching for Velvet Show…"**
- Velvet Show is not running, or local network is blocked
- On first launch, grant Local Network access in iOS Settings if the prompt was refused
- Try closing and relaunching Velvet Remote

**Wi-Fi drops during the show**
- Velvet Remote turns red and attempts to reconnect automatically
- Playback on the Mac **continues uninterrupted** — the Mac does not wait for remote clients
- Plug in the USB cable for a reliable transport

**MIDI commands are not firing**
- Check the MIDI destination in Settings → MIDI
- Check that the MIDI device is powered on and recognized by macOS (Audio MIDI Setup)
- Check that MIDI events are assigned to the track's memos

**No audio**
- Check that macOS system volume is not muted or at zero
- Check that the audio file is accessible (the media folder path must be authorized)
- If a "File not found" alert appears in the status bar, reassign the media folder in Preferences

**The next track is not the one expected**
- Check whether a track is in the queue (Floating Queue window) — the queue takes priority over the setlist
- On iPhone, check that the desired track was not overridden by a later selection
- Clear the queue using the × button on tiles or via the Floating Queue window

---

## Changelog — Velvet Show 0.9 Beta

### Velvet Remote

- **Velvet Remote iPad:** new prompter screen with compact control band, timeline, and Play/Pause and Next buttons
- **Velvet Remote iPhone:** full remote control with dynamic header, available tracks list, and command bar
- **Queue Manager iPhone:** select the next track from iPhone — placed at the front of the queue without immediate playback
- **Remote Timeline iPad:** real-time visual representation of memos, progress, time grid, and playhead
- **+2 indicator:** second-next track displayed in the iPhone header
- **Automatic USB/Wi-Fi reconnection:** transparent recovery after connection loss
- **Transport detection:** real-time USB/Wi-Fi badge

### Audio and stability

- **Filter transition on remote Next:** all Next commands from Velvet Remote apply the Filter transition (2 s low-pass sweep)
- **Next + Queue fix:** the Next command from iPhone now respects the queue before the setlist
- **Available tracks list fix:** the iPhone list shows unplayed tracks across the full setlist, not just tracks after the current position
- **Remote server:** exponential backoff on "Address already in use" errors — no more infinite restart loops

### Icons

- AppIcon for Mac, iPhone, and iPad

---

## Screenshots needed

The following sections will require screenshots for the final release:

- Mac main interface (full window, Shows mode)
- Transport bar in each playback state
- Floating Queue window
- Prompter window
- Velvet Remote iPad (full connected screen)
- Velvet Remote iPhone (full connected screen)
- Velvet Remote discovery screen (server list)
- USB vs Wi-Fi transport badge
