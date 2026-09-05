# AppShelf

AppShelf is a native macOS application launcher focused on quick access, pinning, custom groups, and name-only search.

## Current foundation

- Scans `/Applications`, `/System/Applications`, and `~/Applications`
- Searches application names only
- Launches an application with one click
- Pins applications in a fixed section above the complete application grid
- Persists pinned applications locally
- Reorders pinned applications with drag and drop
- Creates custom groups and assigns applications from the context menu
- Shows or hides AppShelf globally with `Option-Space`
- Interface follows the system language (Chinese and English)
- Reveals an application in Finder from its context menu

## Requirements

- macOS 14 or later
- Xcode 16 or later

Open `AppShelf.xcodeproj` in Xcode and run the `AppShelf` scheme.
