# Eigenton

Eigenton is an iOS/iPadOS/macOS app written in Swift to play music from an [Ampache](http://ampache.github.io) or [Subsonic](http://www.subsonic.org) server.

It is an independent fork of [Amperfy](https://github.com/BLeeEZ/amperfy) by Maximilian Bauer and its contributors, and continues development in its own direction: UI refinements, behavior changes, new features and a simpler app with fewer features.

Eigenton is not affiliated with the Amperfy project. Please report issues [here](https://github.com/chrizzchrizz/eigenton/issues), not upstream. The original Amperfy is available on the [App Store](https://apps.apple.com/app/amperfy-music/id1530145038).

## Features

- Multi account
- Offline mode
- CarPlay
- Gapless playback for appropriate media file formats
- Music, Podcast and Radio support
- Siri play media command, Siri Shortcuts and App Intents
- Equalizer
- Replay gain
- Sleep timer
- 5 star song rating
- Favorite song
- Sleep Timer
- Scrobbling

## Requirements

* Xcode 26, Swift 6

## Getting Started

1. Check out the project and, next to it, the AudioStreaming fork it uses as a local package:
  ```
  git clone https://github.com/chrizzchrizz/eigenton.git
  git clone https://github.com/chrizzchrizz/AudioStreaming.git
  cd eigenton
  ```

2. Open the `Amperfy.xcodeproj` file (project and scheme still carry the original name).

3. Build and run the "Amperfy" scheme

  >Real device testing: the CarPlay entitlement is removed in this fork. Siri support needs a developer certificate with granted access to `com.apple.developer.siri`; to test without it, clear the remaining entries in `Amperfy/Amperfy.entitlements`.

## Contribution

Issues and pull requests for this fork are welcome. Please execute `AmperfyKitTests` to ensure code quality. Running tests will trigger [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) to apply the [Google Swift Style Guide](https://google.github.io/swift), as configured by [Google-SwiftFormat-Config](https://github.com/NoemiRozpara/Google-SwiftFormat-Config). You can also apply the code style manually by executing `./BuildTools/applyFormat.sh`.

## Attributions

- [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) by [Dimitris C.](https://github.com/dimitris-c) is licensed under [MIT License](https://github.com/dimitris-c/AudioStreaming/blob/main/LICENSE)
- [MarqueeLabel](https://github.com/cbpowell/MarqueeLabel) by [Charles Powell](https://github.com/cbpowell) is licensed under [MIT License](https://github.com/cbpowell/MarqueeLabel/blob/master/LICENSE)
- [NotificationBanner](https://github.com/Daltron/NotificationBanner) by [Dalton Hinterscher](https://github.com/Daltron) is licensed under [MIT License](https://github.com/Daltron/NotificationBanner/blob/master/LICENSE)
- [ID3TagEditor](https://github.com/chicio/ID3TagEditor) by [Fabrizio Duroni](https://github.com/chicio) is licensed under [MIT License](https://github.com/chicio/ID3TagEditor/blob/master/LICENSE.md)
- [CoreDataMigrationRevised-Example](https://github.com/wibosco/CoreDataMigrationRevised-Example) by [William Boles](https://github.com/wibosco) is licensed under [MIT License](https://github.com/wibosco/CoreDataMigrationRevised-Example/blob/master/LICENSE)
- [VYPlayIndicator](https://github.com/obrhoff/VYPlayIndicator) by [Dennis Oberhoff](https://github.com/obrhoff) is licensed under [MIT License](https://github.com/obrhoff/VYPlayIndicator/blob/master/LICENSE)
- [CallbackURLKit](https://github.com/phimage/CallbackURLKit) by [Eric Marchand](https://github.com/phimage) is licensed under [MIT License](https://github.com/phimage/CallbackURLKit/blob/master/LICENSE)
- [DominantColors](https://github.com/DenDmitriev/DominantColors) by [Den Dmitriev](https://github.com/DenDmitriev) is licensed under [MIT License](https://github.com/DenDmitriev/DominantColors/blob/main/LICENSE)
- [AudioVisualizerKit](https://github.com/Kyome22/AudioVisualizerKit) by [Takuto NAKAMURA (Kyome)](https://github.com/Kyome22) is licensed under [MIT License](https://github.com/Kyome22/AudioVisualizerKit/blob/main/LICENSE)
- [Alamofire](https://github.com/Alamofire/Alamofire) by [Alamofire](https://github.com/Alamofire) is licensed under [MIT License](https://github.com/Alamofire/Alamofire/blob/master/LICENSE)
- [Ifrit](https://github.com/ukushu/Ifrit) by [Andrii Vynnychenko](https://github.com/ukushu) is licensed under [MIT License](https://github.com/ukushu/Ifrit/blob/main/LICENSE.md)
- [swift-collections](https://github.com/apple/swift-collections) by [Apple](https://github.com/apple) is licensed under [Apache License 2.0](https://github.com/apple/swift-collections/blob/main/LICENSE.txt)
- [iOS-swiftUI-spotify-equalizer](https://github.com/urvi-k/iOS-swiftUI-spotify-equalizer) by [urvi koladiya](https://github.com/urvi-k) is licensed under [MIT License](https://github.com/urvi-k/iOS-swiftUI-spotify-equalizer/blob/main/LICENSE)

**License:** [GPLv3](LICENSE). Based on [Amperfy](https://github.com/BLeeEZ/amperfy), copyright © 2019-2026 Maximilian Bauer and contributors. Modifications copyright © 2026 Chrizz Gelbach.

**Special thanks:** [Dirk Hildebrand](https://apps.apple.com/us/developer/dirk-hildebrand/id654444924)
