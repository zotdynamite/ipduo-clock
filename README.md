# Ipduo Clock

Ipduo Clock is a small iPhone clock. The working name is deliberate: change `AppIdentity.name`, the display name, and the bundle id `app.ipduo.clock` when you want to call it something else. Nothing in the project is tied to another company's clock, music, or authenticator branding.

It is an iOS 17 SwiftUI app with a Home Screen and Lock Screen widget, a local Swift package of time and playback math, and a layout that follows [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).

Open `IpduoClock.xcodeproj` on a Mac to build and run it. GitHub Actions (`.github/workflows/ios.yml`) runs `swift test`, builds the app for the iOS Simulator with ad-hoc signing and no development team, and captures every screen into `screenshots/`. Duo-only APIs stay behind `IPDUO_HAS_DUO_SDK`, which `Config/DuoSDK.xcconfig` turns on only when the active SDK is iOS 27.1 or later.

## What you see

The interface is a dark or light stage with a soft accent glow, translucent cards, and the system font. The accent is one of six palettes (Aurora, Sunrise, Tide, Blossom, Ember, Graphite) and is saved with the rest of the settings.

**Clock.** A full-bleed pager of four faces:

- Analog, with a sweeping second hand, minute and hour hands that move continuously, and a glass dial.
- Digital, a thin time that scales to the width of the display, with optional seconds.
- Flip, split-flap digits that turn when the minute changes.
- Ambient, a gradient that moves from night through dawn, morning, afternoon, and dusk using the sunrise and sunset for the current time zone when a city in the catalog matches it.

On a compact width (the outer display, and a normal iPhone in portrait) only the face is shown. On a regular width (the inner display) the face sits beside a column of the world clock and whatever is playing. That column is the extra level of hierarchy. The selected face, tab, and playback stay put when the device opens or closes, because they live on the app model rather than in a view that is recreated for each size.

**World.** A list of cities with a day or night symbol and a difference such as “Tomorrow, +9HRS” or “Today, +5:30”. The detail column shows a large time plus sunrise and sunset. “Here” is always the current time zone.

**Alarms.** Time, label, repeat days, snooze, and a sound that can be the notification tone, an Apple Music song, or a podcast episode you have already opened. Adding and editing uses a sheet. On the inner display the selected alarm stays in the detail column.

**Timers.** A countdown with a progress ring and presets, and a stopwatch with laps. On a regular width both are on screen together. On a compact width a segmented control switches between them, and that choice is kept.

**Listen.** Apple Music library and catalog search play through `ApplicationMusicPlayer`. Podcasts are found with the public iTunes Search API, subscribed to, and loaded from their RSS feeds. Episodes stream with `AVPlayer`, or play from a download, at 0.75×–2×, with 15 and 30 second skips. The playhead is remembered. A mini player sits above the tab bar on every tab. Lock Screen and Control Center controls use `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.

**StandBy.** The moon button on the clock opens a dim, full-screen landscape clock and hides the status bar. The Home Screen widget also supports the small, medium, circular, rectangular, and inline families that StandBy and the Lock Screen use.

**Settings.** Appearance, accent, 24-hour time, seconds, and haptics. Stored in Application Support.

## iPhone Duo

The layout follows the Human Interface Guidelines page for iPhone Duo rather than a fixed phone size.

- Size classes, safe areas, and flexible frames. There are no fixed screen widths.
- Compact width shows one pane. Regular width shows a second pane: the clock beside the world and now playing, the alarm list beside the alarm, the timer beside the stopwatch, a city beside its detail, and the library beside now playing.
- `TabView`, `NavigationStack`, and `NavigationSplitView` own the bars, so the system can place them on the vertical edge. Toolbar items use a title and an SF Symbol. Add, StandBy, Save, and Close are high visibility priority. Settings is low, so it can move into the overflow menu first. The timer screen asks to keep toolbar actions when space is tight. The rest of the app keeps the tab bar.
- The clock and StandBy backgrounds run edge to edge. On iOS 26 and later they use `backgroundExtensionEffect()` so the color continues under a side bar.
- StandBy is an overlay arrangement: the time is the foreground and the gradient is the background, which is the layout `ArrangementView` separates across the fold. The clock screen is a split arrangement.
- Custom drawing reads `GeometryProxy.reservedRegions(kind:)` when that API exists, and `FoldLayout` keeps the StandBy time off the hinge and the camera. Grids use an even column count, and a vertical fold asks for two columns.
- Those Duo types (`ArrangementView`, `ReservedRegion`, `toolbarVerticalCompressionBehavior`, `visibilityPriority`, `splitArrangementLayoutRatio`) shipped in the iOS 27.1 SDK. They are compiled only when `IPDUO_HAS_DUO_SDK` is set. `backgroundExtensionEffect` needs `IPDUO_HAS_IOS26_SDK`. `Config/DuoSDK.xcconfig` sets the flags from the SDK name (`iphoneos27.1*`, `iphonesimulator27.1*`, and later 28–30). On an older SDK the same screens use a size-class fallback, so the project still builds. If a future Xcode does not match the patterns, add the two flags under Build Settings → Active Compilation Conditions.

Navigation stays outside the arrangement views. Sheets are system sheets, which already move for the fold.

## Open and run

1. Install Xcode 15 or later. iOS 17 is the deployment target. Duo-only APIs need Xcode with the iOS 27.1 SDK. The app still builds without them.
2. Open `IpduoClock.xcodeproj`. Do not open the folder as a Swift package. The package is the logic library. The app is the Xcode project.
3. Select the **IpduoClock** scheme and an iPhone simulator, or iPhone Duo in Xcode’s device hub once you have it.
4. Set your Team on the IpduoClock and IpduoClockWidget targets if you run on a device.
5. Run.

The widget is embedded in the app. After the first launch, add **Ipduo Clock** from the widget gallery.

To rename the app, change:

- `AppIdentity.name` in `App/IpduoClockApp.swift`
- the display name build setting (`INFOPLIST_KEY_CFBundleDisplayName`)
- `PRODUCT_BUNDLE_IDENTIFIER` (`app.ipduo.clock` and `app.ipduo.clock.widget`)
- the MusicKit App ID, which must match the new bundle id

## Apple Music

Music playback uses MusicKit. The entitlement is already in `App/IpduoClock.entitlements`:

```xml
<key>com.apple.developer.musickit</key>
<true/>
```

You still have to turn the capability on for the App ID, or signing fails on a device:

1. In the Apple Developer account, open Identifiers and select `app.ipduo.clock` (create it if needed).
2. Enable **MusicKit**.
3. In Xcode, select the IpduoClock target, Signing & Capabilities, and confirm MusicKit is listed. If Xcode offers to add it, let it. Do not let it replace the entitlements file with an empty one.
4. The usage string is already in `App/Info.plist`: “Ipduo Clock plays Apple Music songs you choose, including as an alarm.”

Until that is done, the Listen tab explains that Apple Music is unavailable. Podcasts do not need this entitlement.

A developer token is not checked into the repo. MusicKit on device uses the entitlement and the user’s Apple Music subscription. Catalog playback requires a subscription. Library songs the user owns play according to Apple’s rules.

## Alarms, audio, and the Lock Screen

Alarms are local notifications. iOS will not start a full song while the app is suspended. The notification is the wake-up sound. Opening it, or receiving it while Ipduo Clock is in the foreground, starts the chosen song or episode. Snooze and Stop are notification actions. Repeating alarms schedule one weekly trigger per selected day. iOS allows only 64 pending notifications, so a very long list is trimmed.

Background audio is declared (`audio`) so a podcast or song can keep playing with the screen locked. The remote commands are play, pause, skip back 15 seconds, skip forward 30 seconds, and scrub. The in-app player also has 15 and 30 seconds in both directions, and a speed control for podcasts. Apple Music playback rate stays at 1× because `ApplicationMusicPlayer` does not expose a podcast-style rate or volume. The sleep timer still stops it at the end. For a podcast, volume fades across the last 20 seconds and then playback pauses.

Downloads live in the app’s Application Support folder. Resume positions live in the same JSON file as the alarms and settings.

## Tests

The testable code is the `IpduoClockCore` package: time zones and daylight saving offsets, sunrise and sunset shape, alarm next-fire dates and notification triggers, stopwatch laps, countdown progress, sleep-timer fade, resume positions, skip clamping, RSS parsing, and the iTunes search URL. Fold geometry (which pane to use, and even column counts) is in there too, so it can be tested without SwiftUI.

From the repository root, with a Swift 5.9+ toolchain:

```sh
swift test
```

That runs six suites: `AlarmScheduleTests`, `WorldTimeSolarTests`, `StopwatchCountdownTests`, `SleepAndResumeTests`, `RSSParserTests`, and `FoldLayoutTests`. Xcode lists the same tests after it resolves the local package. On Linux, Swift 6 keeps `XMLParser` in `FoundationXML`; the parser imports that module when it is present and uses Foundation on Apple platforms.

## Layout of the repo

```
IpduoClock.xcodeproj    the app and widget
App/                    SwiftUI screens, playback, alarms
Widget/                 WidgetKit clock
Config/DuoSDK.xcconfig  SDK checks for Duo APIs
Sources/IpduoClockCore  time, alarms, RSS, sleep, fold math
Tests/IpduoClockCoreTests
```

## Notes

- Secrets are not collected. Apple Music authorization stays with MusicKit. Podcast requests go to `itunes.apple.com` and to the show’s own feed URL. Treat feed and audio URLs as untrusted input. The RSS parser does not load remote entities.
- Alarm labels and song titles are shown in the notification. That is visible on the Lock Screen.
- The app does not ship a backend, an account, or analytics.
- Downloads and resume data are local to the device and go away if the app is deleted.

## Next steps

- Run it on the iPhone Duo simulator in Xcode 27.1 and confirm the fold, the vertical bars, and the overlay StandBy layout.
- Add an App Group if the widget should show the next alarm. It was left out so a missing capability does not block installation. The widget currently draws the time only.
- Add a queue, stations, and chapters if Listen grows past one song or episode.
- Consider AlarmKit or a Live Activity for a ringing alarm that is visible without opening the app.
- Localize the city names. The catalog is English on purpose so the ids stay stable.
