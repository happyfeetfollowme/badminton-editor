# Design Document

## Overview

The video splitting functionality extends the existing timeline system to support clip-based video editing. The design introduces a clip management system that tracks split points and manages clip boundaries, along with visual selection feedback and a context menu for split operations. The implementation leverages the existing TimelineState and VideoThumbnailTrackView architecture while adding new models and UI components for clip management.

## Architecture

### Core Components

The video splitting feature consists of four main architectural components:

1. **Clip Management System**: Handles clip data models, split point tracking, and boundary calculations
2. **Selection System**: Manages clip selection state and visual feedback
3. **Context Menu System**: Provides popup menu functionality for split operations
4. **Visual Overlay System**: Renders clip boundaries, selection indicators, and split markers

### Integration with Existing Timeline

The design integrates seamlessly with the existing timeline architecture:

- **TimelineState**: Extended to include clip management and selection state
- **VideoThumbnailTrackView**: Enhanced with clip selection gestures and visual overlays
- **TimelineContentView**: Updated to handle clip-based interactions and menu positioning

## Components and Interfaces

### Data Models

#### VideoClip Model
```swift
struct VideoClip: Identifiable, Equatable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    var isSelected: Bool = false
    
    var duration: TimeInterval {
        return endTime - startTime
    }
    
    func contains(time: TimeInterval) -> Bool {
        return time >= startTime && time < endTime
    }
}
```

#### SplitPoint Model
```swift
struct SplitPoint: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let createdAt: Date = Date()
}
```

### State Management

#### ClipManager (ObservableObject)
```swift
class ClipManager: ObservableObject {
    @Published var clips: [VideoClip] = []
    @Published var splitPoints: [SplitPoint] = []
    @Published var selectedClipId: UUID? = nil
    
    // Core functionality
    func initializeClips(duration: TimeInterval)
    func addSplitPoint(at time: TimeInterval)
    func selectClip(at time: TimeInterval)
    func clearSelection()
    func getClip(at time: TimeInterval) -> VideoClip?
    func getSelectedClip() -> VideoClip?
}
```

#### MenuState (ObservableObject)
```swift
class MenuState: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var position: CGPoint = .zero
    @Published var targetClipId: UUID? = nil
    
    func showMenu(at position: CGPoint, for clipId: UUID)
    func hideMenu()
}
```

### UI Components

#### ClipSelectionOverlay
A view that renders white borders around selected clips and handles tap gestures for clip selection.

#### ClipContextMenu
A popup menu component that displays clip-related actions (currently split functionality) and handles clip operations. Designed for extensibility to support additional clip actions in the future.

#### SplitMarkerView
Visual markers that indicate split points on the timeline.

## Data Models

### Clip Boundary Calculation

Clips are defined by split points and video boundaries:

1. **First Clip**: From video start (0.0) to first split point or video end
2. **Middle Clips**: From one split point to the next split point
3. **Last Clip**: From final split point to video end

### Split Point Management

Split points are stored as time intervals and automatically trigger clip boundary recalculation:

```swift
// Example clip calculation logic
func calculateClips(duration: TimeInterval, splitPoints: [TimeInterval]) -> [VideoClip] {
    let sortedSplits = splitPoints.sorted()
    var clips: [VideoClip] = []
    
    if sortedSplits.isEmpty {
        // Single clip for entire video
        clips.append(VideoClip(startTime: 0.0, endTime: duration))
    } else {
        // First clip: start to first split
        clips.append(VideoClip(startTime: 0.0, endTime: sortedSplits[0]))
        
        // Middle clips: split to split
        for i in 0..<(sortedSplits.count - 1) {
            clips.append(VideoClip(startTime: sortedSplits[i], endTime: sortedSplits[i + 1]))
        }
        
        // Last clip: final split to end
        clips.append(VideoClip(startTime: sortedSplits.last!, endTime: duration))
    }
    
    return clips
}
```

## Error Handling

### Gesture Conflict Resolution

The design handles potential conflicts between existing timeline gestures and new clip selection:

1. **Tap Priority**: Clip selection takes precedence over timeline scrubbing for tap gestures
2. **Drag Preservation**: Existing drag gestures for timeline scrolling remain unchanged
3. **Menu Dismissal**: Tapping outside the menu dismisses it while preserving clip selection

### Split Point Validation

Split operations include validation to prevent invalid states:

1. **Boundary Checks**: Prevent splits at video start (0.0) or end
2. **Duplicate Prevention**: Avoid creating split points at existing split locations
3. **Minimum Clip Duration**: Ensure clips maintain minimum viable duration (e.g., 0.1 seconds)

### Menu Positioning Edge Cases

The context menu positioning system handles screen boundary constraints:

1. **Horizontal Centering**: Menu centers on timeline view width
2. **Vertical Positioning**: Menu appears above thumbnail view with padding
3. **Screen Edge Handling**: Menu adjusts position if it would extend beyond screen bounds

## Testing Strategy

### Unit Testing

Test cases will be written for the following components (implementation not included in this spec):

1. **ClipManager Tests**:
   - `testClipBoundaryCalculationWithNoSplits()`: Verify single clip spans entire video duration
   - `testClipBoundaryCalculationWithSingleSplit()`: Verify two clips created with correct boundaries
   - `testClipBoundaryCalculationWithMultipleSplits()`: Verify multiple clips with proper boundaries
   - `testAddSplitPointAtValidTime()`: Verify split point addition and clip recalculation
   - `testAddSplitPointAtInvalidTime()`: Verify rejection of invalid split times (0.0, duration)
   - `testSelectClipAtTime()`: Verify clip selection based on time position
   - `testClearSelection()`: Verify selection state clearing
   - `testGetClipAtTime()`: Verify clip retrieval by time position

2. **MenuState Tests**:
   - `testShowMenuWithValidPosition()`: Verify menu visibility and position setting
   - `testHideMenu()`: Verify menu dismissal and state reset
   - `testMenuPositionCalculation()`: Verify menu positioning relative to timeline center
   - `testMenuPositionWithScreenBounds()`: Verify menu position adjustment for screen edges

3. **Model Tests**:
   - `testVideoClipContainsTime()`: Verify time containment logic for clips
   - `testVideoClipDurationCalculation()`: Verify duration calculation accuracy
   - `testVideoClipEquality()`: Verify clip comparison logic
   - `testSplitPointCreation()`: Verify split point initialization
   - `testSplitPointEquality()`: Verify split point comparison

### Integration Testing

Test cases will be written for the following integration scenarios:

1. **Timeline Integration**:
   - `testClipSelectionWithTimelineScrolling()`: Verify clip selection works during timeline scroll
   - `testSplitOperationWithPlayheadPosition()`: Verify split occurs at current playhead time
   - `testMenuDisplayWithZoomLevels()`: Verify menu positioning at different zoom levels
   - `testClipBoundariesWithPixelConversion()`: Verify clip boundaries align with pixel positions

2. **Gesture Handling**:
   - `testTapGesturePriorityClipVsTimeline()`: Verify clip selection takes precedence over scrubbing
   - `testMenuDismissalOnOutsideTap()`: Verify menu dismisses but selection persists
   - `testDragGesturePreservation()`: Verify timeline scrolling continues to work
   - `testSelectedClipTapShowsMenu()`: Verify tapping selected clip shows context menu

3. **Visual Feedback**:
   - `testClipSelectionBorderRendering()`: Verify white border appears around selected clip
   - `testSplitMarkerPositioning()`: Verify split markers appear at correct timeline positions
   - `testMenuPositioningRelativeToTimeline()`: Verify menu centers on timeline view

### UI Testing

Test cases will be written for the following user interface scenarios:

1. **User Interaction Flows**:
   - `testCompleteClipSelectionAndSplitWorkflow()`: End-to-end clip selection and splitting
   - `testMultipleClipSelectionScenarios()`: Selecting different clips in sequence
   - `testMenuInteractionAndDismissal()`: Menu appearance, interaction, and dismissal

2. **Visual Validation**:
   - `testClipBoundaryAccuracyAtDifferentZooms()`: Verify clip boundaries at various zoom levels
   - `testSelectionIndicatorVisibility()`: Verify selection borders are visible and positioned correctly
   - `testMenuAppearanceAndPositioning()`: Verify menu appears in correct location

3. **Edge Case Scenarios**:
   - `testVeryShortClipHandling()`: Verify clips shorter than 1 second are handled properly
   - `testMaximumZoomWithSmallClips()`: Verify functionality at maximum zoom levels
   - `testRapidTapSequences()`: Verify system handles rapid user interactions gracefully

## Implementation Notes

### Performance Considerations

1. **Clip Calculation Optimization**: Clip boundaries are recalculated only when split points change
2. **Selection State Efficiency**: Only the selected clip maintains selection state to minimize re-renders
3. **Menu Rendering**: Context menu is conditionally rendered to avoid unnecessary view hierarchy

### Accessibility

1. **VoiceOver Support**: Clip selection and menu interactions include appropriate accessibility labels
2. **Dynamic Type**: Menu text and icons scale with user's preferred text size
3. **High Contrast**: Selection borders and menu elements support high contrast mode

### SwiftUI Integration

The design leverages SwiftUI's reactive architecture:

1. **@Published Properties**: State changes automatically trigger UI updates
2. **Gesture Modifiers**: Tap and drag gestures are composed using SwiftUI's gesture system
3. **Overlay Architecture**: Visual elements are layered using ZStack and overlay modifiers