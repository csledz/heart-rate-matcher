# heart-rate-matcher

iOS app (SwiftUI, iOS 17+) that combines two recordings of the same bike ride
into a single track. For each data channel — GPS, altitude, heart rate,
cadence, power, speed, distance, temperature — you pick which source ride wins.
You can also speed up or slow down a ride by a percentage before the merge.

## Status

| Area              | Status                                                     |
|-------------------|------------------------------------------------------------|
| GPX import        | Done — parses Garmin TrackPointExtension v2 + Strava power |
| FIT import        | Done — minimal decoder for `record` messages (msg 20)      |
| Per-channel merge | Done                                                       |
| Speed tuning      | Done — ±50% / +100%, time-axis rescaling + speed scaling   |
| GPX export        | Done — Strava-compatible (HR, cadence, atemp, power)       |
| FIT export        | Not implemented (GPX is sufficient for Strava upload)      |
| Strava OAuth      | Not implemented (deferred)                                 |
| Garmin Connect    | Not implemented (deferred)                                 |

## Project layout

```
HeartRateMatcher/
  App/        # @main entry + RideStore
  Models/     # RideSample, Ride, RideChannel
  Parsing/    # GPXParser, FITParser, RideImporter
  Merging/    # MergeConfiguration, RideMerger
  Export/     # GPXExporter
  Views/      # ContentView, MergeView
  Resources/  # Info.plist
HeartRateMatcherTests/
project.yml   # XcodeGen spec
```

## Build

The Xcode project is generated from `project.yml`. Install
[XcodeGen](https://github.com/yonaskolb/XcodeGen) once:

```sh
brew install xcodegen
```

Then in the repo root:

```sh
xcodegen generate
open HeartRateMatcher.xcodeproj
```

Run `HeartRateMatcher` on an iOS 17+ simulator or device. Use the import
button (top-right) to add `.fit` or `.gpx` files; iCloud Drive, Files, and
AirDrop all work.

## How merging works

1. Each ride goes through its own optional **time-axis transform**. A
   `speedMultiplier` of 1.10 means "play this ride 10% faster": every sample's
   offset from start is divided by 1.10, and the speed channel is multiplied
   by 1.10. Distance, GPS, HR, cadence, power, altitude, and temperature
   values are unchanged — only the timestamps shift.
2. One ride is chosen as the **primary timeline**. The merged ride has one
   sample per primary sample.
3. For each primary sample and each channel, the merger looks up the value
   from the configured source. If the source is the secondary ride, it
   linearly interpolates onto the primary timestamp using the configured
   alignment (absolute timestamps, or offset-from-start).

Rides exported as GPX include `<gpxtpx:hr>`, `<gpxtpx:cad>`, `<gpxtpx:atemp>`
and `<power>` extensions, so Strava ingests heart rate / cadence / power
correctly when you re-upload the merged file.

## Roadmap

- Strava OAuth + activity stream pull (drop-in once API credentials exist).
- Garmin Connect ingestion (requires partner approval — FIT file import works
  today as a stand-in).
- Map preview and per-channel chart preview before exporting.
- FIT export for direct Garmin Connect upload.
