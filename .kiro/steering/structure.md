# Project Structure

## Root Directory Organization

```
Badminton_Editor/                    # Main app target
├── Badminton_EditorApp.swift       # App entry point (@main)
├── ContentView.swift               # Main view controller
├── Item.swift                      # Data models
├── PerformanceMonitor.swift        # Performance tracking
├── Assets.xcassets/                # App icons and assets
├── Preview Content/                # SwiftUI preview assets
└── Modules/                        # Feature modules
    ├── Timeline/                   # Timeline functionality
    ├── Video/                      # Video processing
    └── UI/                         # Reusable UI components

Badminton_EditorTests/              # Unit tests
Badminton_EditorUITests/            # UI tests
Badminton_Editor.xcodeproj/         # Xcode project files
```

## Module Organization

### Timeline Module (`Modules/Timeline/`)
- **TimelineModels.swift**: Data models (RallyMarker, MarkerPinView, etc.)
- **TimelineState.swift**: Timeline state management
- **TimelineContainerView.swift**: Main timeline container
- **TimelineContentView.swift**: Timeline content and interactions
- **VideoThumbnailTrackView.swift**: Thumbnail track display
- **ThumbnailProvider.swift**: Thumbnail generation and caching

### Video Module (`Modules/Video/`)
- **VideoLoader.swift**: Video asset loading and optimization
- **VideoPickers.swift**: Photo library integration
- **VideoUtils.swift**: Video utility functions

### UI Module (`Modules/UI/`)
- **EditorUIComponents.swift**: Reusable UI components (buttons, toolbars, etc.)

## Naming Conventions

### Files
- **Views**: Suffix with `View` (e.g., `TimelineContentView`)
- **Models**: Descriptive names (e.g., `RallyMarker`, `VideoCodecInfo`)
- **Utilities**: Suffix with appropriate type (e.g., `VideoLoader`, `ThumbnailProvider`)

### Code Structure
- **MARK Comments**: Use `// MARK: -` for section organization
- **Extensions**: Group related functionality in extensions
- **State Variables**: Use descriptive names with appropriate property wrappers

## Architecture Patterns

### View Hierarchy
```
ContentView (Main container)
├── TopToolbarView
├── VideoPlayerView
├── TimelineContainerView
│   ├── TimelineContentView
│   └── VideoThumbnailTrackView
├── PlaybackControlsView
└── MainActionToolbarView
```

### State Management
- **@State**: Local view state
- **@StateObject**: Object lifecycle management
- **@Binding**: Parent-child data flow
- **Async/Await**: Asynchronous operations

### Responsive Design
- Use `GeometryReader` for adaptive layouts
- Implement `isCompact` boolean for iPhone/iPad differences
- Support both portrait and landscape orientations

## File Organization Rules

1. **Single Responsibility**: Each file should have a clear, focused purpose
2. **Logical Grouping**: Related functionality grouped in modules
3. **Consistent Naming**: Follow Swift naming conventions
4. **Documentation**: Use MARK comments for code organization
5. **Imports**: Only import necessary frameworks at file level