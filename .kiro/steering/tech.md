# Technology Stack

## Build System & Platform
- **Xcode Project**: Standard iOS app project with `.xcodeproj` structure
- **Minimum iOS Version**: iOS 18.0
- **Target Devices**: iPhone and iPad (Universal app)
- **Swift Version**: Swift 5.0
- **Development Team**: HDDVU5Q8H7

## Core Frameworks
- **SwiftUI**: Primary UI framework for all views and components
- **AVFoundation**: Video playback, asset management, and media processing
- **AVKit**: Video player UI components
- **Photos/PhotosUI**: Photo library access and PHAsset integration
- **VideoToolbox**: Hardware video codec detection and optimization
- **UniformTypeIdentifiers**: File type handling

## Architecture Patterns
- **MVVM**: State management with `@State`, `@StateObject`, `@Binding`
- **Modular Structure**: Organized into feature modules (Timeline, Video, UI)
- **Async/Await**: Modern Swift concurrency for video operations
- **Responsive Design**: GeometryReader-based adaptive layouts

## Key Technical Features
- **Hardware Acceleration**: GPU-optimized video decoding with HEVC/H.264 detection
- **Performance Monitoring**: Built-in performance tracking
- **Memory Management**: Optimized for large video file handling
- **Audio Session**: Configured for video playback with external audio support

## Common Commands

### Build & Run
```bash
# Open project in Xcode
open Badminton_Editor.xcodeproj

# Build from command line (if needed)
xcodebuild -project Badminton_Editor.xcodeproj -scheme Badminton_Editor -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### Testing
```bash
# Run unit tests
xcodebuild test -project Badminton_Editor.xcodeproj -scheme Badminton_Editor -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Dependencies
- No external package dependencies (uses only system frameworks)
- All video processing handled through native iOS frameworks