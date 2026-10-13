# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Amperfy is an iOS/iPadOS/macOS (Mac Catalyst) music player in Swift 6 (Xcode 26) for Ampache and Subsonic/OpenSubsonic servers. GPL-3 licensed; new files need the header from `Helper/license-header.txt` (`Helper/add-license-header.sh`).

## Build, test, format

Everything runs through `Amperfy.xcodeproj` (targets: `Amperfy`, `AmperfyKit`, `AmperfyKitTests`; shared schemes: `Amperfy`, `AmperfyIntents`, `DebugCoreData`). SPM dependencies are resolved by Xcode; there is no Package.swift for the app.

```
xcodebuild -project Amperfy.xcodeproj -scheme Amperfy -destination 'platform=iOS Simulator,name=<simulator>' build
xcodebuild -project Amperfy.xcodeproj -scheme Amperfy -destination 'platform=iOS Simulator,name=<simulator>' test
# single test class / method
... test -only-testing:AmperfyKitTests/<TestClass>[/<testMethod>]
```

- Tests live only in `AmperfyKitTests` (Core Data is exercised against an in-memory store; see `Cases/HelperTest.swift` and `Cases/Storage`).
- Formatting: SwiftFormat (Google Swift style, config in `.swiftformat`) built from `BuildTools/` and run automatically when tests run. Apply manually with `./BuildTools/applyFormat.sh`.
- Real-device CarPlay/Siri need special entitlements; to build without them, clear the entries in `Amperfy/Amperfy.entitlements`.

## Architecture

Two main modules:

- **AmperfyKit** (framework, no app UI): all logic — backends, Core Data storage, player, downloads. Also shared by the Intents extension. Public API is explicit (`public`) since the app imports it.
- **Amperfy** (app target): UIKit screens (storyboards/XIBs + view controllers), CarPlay (`CarPlay/`), App Intents/Siri (`Intents/`), a few SwiftUI views (`SwiftUI/`), scene delegates (main, mini player, settings, CarPlay).

### AmperfyKit pieces that span many files

- **`MetaManager`** is the composition root: lazily builds the `BackendProxy`, `LibrarySyncer`, download managers, duplicate resolver, scrobble syncer, etc. `AppDelegate` owns it; look here to see how components are wired.
- **Backend abstraction** (`Api/`): `BackendProxy` / `LibrarySyncerProxy` dispatch to the Ampache or Subsonic implementation based on the active account. Each backend has `*Api`, `*ServerApi` (HTTP), `*LibrarySyncer`, and one XML parser delegate per entity type (`Ampache/*ParserDelegate`, `Subsonic/Ss*ParserDelegate`). Adding a server feature usually means touching both backends plus the shared protocols in `BackendApi.swift`.
- **Storage** (`Storage/`): Core Data model in `ManagedObjects/Amperfy.xcdatamodeld`. Each entity has an `*MO` managed object (generated-style `+CoreDataClass/Properties`) and a plain wrapper class in `EntityWrappers/` (`Song`, `Album`, `Artist`, `Playlist`, …) that the rest of the code uses. `LibraryStorage` is the main synchronous accessor; `AsyncCoreDataAccessWrapper` is used for background contexts. `ResultController/` holds fetched-results wrappers used by list screens. Model changes require a new model version plus migration handling. Settings are in `Settings.swift` / `PersistentStorage.swift`.
- **Player** (`Player/`): `PlayerFacade` is the public entry point; it wraps `AudioPlayer` (queue logic via `PlayQueueHandler`, with prev/user/next queues and shuffle/repeat/autoplay) and `BackendAudioPlayer` (AudioStreaming/AVPlayer, gapless, EQ, replay gain). Now-playing info, remote commands, scrobbling and audio session each have their own handler.
- **Downloads** (`Download/`, `Storage/DownloadRequestManager`, `CacheFileManager`): `DownloadManager` runs queued requests for playable files and artwork; delegates differ per content type.
- **Notifications** (`Common/*NotificationHandler`, `Player/PlayerNotificationAdapter`): the app and player communicate via notification handlers/observers rather than direct references in many places.

### App target notes

- Screens are in `Amperfy/Screens/{Basics,Player,View,ViewController}`; storyboard access goes through `AppStoryboard.swift`. Many views are XIB-backed, so renaming outlets requires updating the `.xib` too. Home screen sections are driven by `HomeManager` / `HomeVC` / `AmperfyKit/Storage/HomeSection.swift`.
- macOS is built via Mac Catalyst (see `MacWindowHelper.swift`, `AppDelegateMainMenuExtension.swift`, `AppDelegateKeyboardCommands.swift`); check for platform-specific code paths when changing UI.

## Git

- Do not add `Co-Authored-By` trailers (or any other attribution lines) to commit messages or pull request descriptions.
