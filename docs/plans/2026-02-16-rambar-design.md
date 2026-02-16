# RamBar — macOS Menu Bar RAM Monitor

## Overview

A lightweight macOS menu bar app that displays real-time RAM usage. Shows a percentage in the menu bar; expands to a frosted-glass popover with a memory pressure gauge and per-app RAM breakdown.

## Tech Stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI + NSVisualEffectView for glassy popover
- **Target**: macOS 13+ (Ventura)
- **Build**: Xcode project (no SPM dependencies needed)
- **Distribution**: Direct download (or App Store later)

## Architecture

```
RamBar/
├── RamBarApp.swift          # App entry, LSUIElement=true (menu bar only, no dock icon)
├── MenuBarController.swift  # NSStatusItem setup + NSPopover toggle
├── Models/
│   ├── SystemMemory.swift   # Total/used/free/pressure data model
│   └── ProcessMemory.swift  # Per-process: name, icon, RAM usage
├── Services/
│   └── MemoryMonitor.swift  # Timer-driven Mach API data collection (ObservableObject)
└── Views/
    ├── PopoverView.swift    # Main expanded view container
    ├── MemoryGaugeView.swift # Circular pressure gauge + used/free summary
    ├── ProcessListView.swift # Scrollable per-app list sorted by usage
    └── SettingsView.swift   # Launch at login toggle + refresh interval picker
```

### Data Flow

`MemoryMonitor` is an `ObservableObject` that fires a `Timer` every 3 seconds (configurable: 1s/3s/5s). It publishes:
- `systemMemory: SystemMemory` — total, used, free, pressure level
- `processes: [ProcessMemory]` — sorted by RSS descending

SwiftUI views observe these `@Published` properties and re-render reactively.

### Key APIs

| Purpose | API |
|---------|-----|
| System memory stats | `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)` |
| Total physical RAM | `ProcessInfo.processInfo.physicalMemory` |
| Process list | `proc_listallpids()` |
| Per-process RSS | `proc_pidinfo(pid, PROC_PIDTASKINFO, ...)` |
| Memory pressure events | `DispatchSource.makeMemoryPressureSource()` |
| App icons | `NSRunningApplication.icon` |
| Launch at login | `SMAppService.mainApp.register()` (macOS 13+) |

## UI Design

### Menu Bar Item

Plain text showing RAM usage percentage (e.g. `67%`). White, system font, monospaced digits to prevent width jitter. Updates every 3 seconds.

### Expanded Popover

```
┌─────────────────────────────┐  ← Frosted glass (NSVisualEffectView, .popover material)
│                             │
│    ╭───────╮                │
│    │  67%  │  Memory        │  ← Circular gauge ring, color-coded
│    ╰───────╯  Pressure: Low │     Green = normal, Yellow = warn, Red = critical
│                             │
│  Used: 12.4 GB  Free: 3.6 GB│
│─────────────────────────────│
│  ● Chrome          2.1 GB  │  ← App icon + name + RAM usage
│  ● Xcode           1.8 GB  │     Sorted by usage (highest first)
│  ● Figma           890 MB  │     Top ~15 processes
│  ● Slack           650 MB  │     Subtle alternating row tint
│  ● Terminal        120 MB  │
│  ● ...                      │  ← Scrollable
│─────────────────────────────│
│  ⚙ Settings     ✕ Quit     │  ← Footer
└─────────────────────────────┘
```

**Dimensions**: ~300px wide, ~420px tall.

### Visual Style

- **Glassy**: `NSVisualEffectView` with `.popover` material → native frosted glass
- **Typography**: System font, `.light` weight for values, `.medium` for labels
- **Colors**: Muted throughout; the gauge ring is the only strong accent
- **Separators**: Subtle, `.opacity(0.15)`
- **App icons**: From `NSRunningApplication.icon` (16x16)
- **Corners**: Native popover rounding (~12pt)

### Settings Panel

Replaces popover content when settings gear is tapped:
- **Launch at Login** — toggle (SMAppService)
- **Refresh Interval** — segmented picker: 1s / 3s / 5s
- **Back** button to return to main view

Stored in `UserDefaults`.

## Behavior

### Memory Pressure Levels

| Level | Color | Meaning |
|-------|-------|---------|
| Normal | Green | Plenty of free RAM |
| Warning | Yellow | System is compressing memory |
| Critical | Red | System is swapping to disk |

Uses `DispatchSource.makeMemoryPressureSource()` for real-time pressure change events, supplemented by the timer for percentage/process updates.

### Process List Rules

- Top 15 processes shown by default
- Groups helper processes under parent app (e.g., Chrome Helper → Chrome)
- Filters out system processes under 10MB
- Sorted by RSS descending (recalculated each refresh)

### System Behavior

- **No dock icon**: `LSUIElement = true` in Info.plist
- **Launch at login**: Opt-in via SMAppService, toggle in settings
- **Memory footprint**: Target ~10-15MB RSS
- **CPU usage**: Negligible at 3s interval (~0.1% peak during refresh)
