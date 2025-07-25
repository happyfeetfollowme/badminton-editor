# Implementation Plan

- [ ] 1. Create core data models for clip management
  - Implement VideoClip struct with time boundaries and selection state
  - Implement SplitPoint struct for tracking split locations
  - Add time containment and duration calculation methods
  - _Requirements: 1.1, 5.1, 5.2, 5.3, 5.4, 5.5_

- [ ] 2. Implement ClipManager state management class
  - Create ObservableObject class for managing clips and split points
  - Implement clip boundary calculation logic based on split points
  - Add methods for split point addition and clip selection
  - Add clip retrieval and selection clearing functionality
  - _Requirements: 1.1, 1.2, 1.3, 4.3, 4.4, 5.1, 5.2, 5.3, 5.4, 5.5_

- [ ] 3. Create MenuState class for context menu management
  - Implement ObservableObject for menu visibility and positioning
  - Add methods for showing and hiding the context menu
  - Implement menu positioning calculations relative to timeline center
  - _Requirements: 3.1, 3.2, 3.3_

- [ ] 4. Extend TimelineState to integrate clip management
  - Add ClipManager and MenuState as properties to TimelineState
  - Integrate clip initialization with video loading
  - Add methods to coordinate between timeline and clip states
  - _Requirements: 1.1, 2.1, 2.2_

- [ ] 5. Create ClipSelectionOverlay view component
  - Implement SwiftUI view for rendering clip selection borders
  - Add tap gesture recognition for clip selection
  - Implement white border rendering around selected clips
  - Handle coordinate conversion between timeline and clip positions
  - _Requirements: 1.2, 1.3, 2.1, 2.2, 2.3_

- [ ] 6. Implement ClipContextMenu popup component
  - Create SwiftUI view for the context menu with split icon
  - Implement menu positioning logic centered on timeline view
  - Add split action handling that creates split points at playhead position
  - Implement menu dismissal and selection clearing on split action
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 4.1, 4.6_

- [ ] 7. Create SplitMarkerView for visual split indicators
  - Implement SwiftUI view for rendering split point markers on timeline
  - Position markers accurately at split point time positions
  - Style markers to be visible against thumbnail background
  - _Requirements: 4.2, 4.5_

- [ ] 8. Integrate clip selection with VideoThumbnailTrackView
  - Add ClipSelectionOverlay as an overlay to the thumbnail track
  - Implement tap gesture handling for clip selection
  - Add gesture priority to ensure clip selection takes precedence over timeline scrubbing
  - Handle tap-outside-menu dismissal while preserving selection
  - _Requirements: 1.2, 1.3, 2.1, 2.2, 2.3_

- [ ] 9. Add split marker rendering to timeline
  - Integrate SplitMarkerView into VideoThumbnailTrackView
  - Position split markers at correct pixel positions based on time
  - Ensure markers are visible at all zoom levels
  - _Requirements: 4.2, 4.5_

- [ ] 10. Implement context menu display logic
  - Add ClipContextMenu to VideoThumbnailTrackView with conditional rendering
  - Connect menu visibility to selected clip tap gestures
  - Implement menu positioning relative to timeline center and above thumbnails
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [ ] 11. Connect split functionality to playhead position
  - Integrate current playhead time from AVPlayer with split operations
  - Implement split point creation at current playhead position
  - Update clip boundaries automatically when splits are created
  - Ensure split markers appear at correct timeline positions
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [ ] 12. Add comprehensive error handling and validation
  - Implement split point validation to prevent invalid operations
  - Add boundary checks for split operations (not at 0.0 or duration)
  - Handle edge cases for very short clips and maximum zoom levels
  - Add gesture conflict resolution between clip selection and timeline scrolling
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 5.4, 5.5_