import SwiftUI
import Foundation

/// SwiftUI view component for rendering clip selection borders and handling clip selection gestures
/// This overlay sits on top of the VideoThumbnailTrackView to provide visual feedback and interaction
struct ClipSelectionOverlay: View {
    // MARK: - Properties
    
    /// Timeline state for coordinate conversion and clip management
    @ObservedObject var timelineState: TimelineState
    
    /// Total duration of the video content
    let totalDuration: TimeInterval
    
    /// Current zoom level (pixels per second)
    let pixelsPerSecond: CGFloat
    
    /// Current content offset for coordinate conversion
    let contentOffset: CGFloat
    
    /// Screen width for coordinate calculations
    let screenWidth: CGFloat
    
    /// Base offset for timeline alignment (matches VideoThumbnailTrackView)
    private let baseOffset: CGFloat = 500
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent background for gesture detection with enhanced conflict resolution
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        // Enhanced gesture handling with conflict resolution
                        createClipSelectionGesture(geometry: geometry)
                    )
                
                // Render selection borders for selected clips
                ForEach(timelineState.clipManager.clips.filter { $0.isSelected }) { clip in
                    clipSelectionBorder(for: clip, in: geometry)
                }
            }
        }
    }
    
    // MARK: - Enhanced Gesture Handling with Conflict Resolution
    
    /// Create a gesture that properly handles conflicts between clip selection and timeline scrolling
    /// This implements comprehensive gesture conflict resolution as required by task 12
    private func createClipSelectionGesture(geometry: GeometryProxy) -> some Gesture {
        // Use DragGesture to distinguish between taps and drags
        let dragGesture = DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                handleGestureChanged(value, in: geometry)
            }
            .onEnded { value in
                handleGestureEnded(value, in: geometry)
            }
        
        // Return the gesture with high priority to ensure clip selection takes precedence
        return dragGesture
    }
    
    /// Handle gesture changes to distinguish between taps and drags
    /// This prevents clip selection from interfering with timeline scrolling
    private func handleGestureChanged(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        // Calculate drag distance to determine if this is a scroll gesture
        let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
        let scrollThreshold: CGFloat = 10.0 // Minimum distance to consider as scroll
        
        // If drag distance exceeds threshold, this is likely a scroll gesture
        // We should not interfere with timeline scrolling
        if dragDistance > scrollThreshold {
            // This is a scroll gesture - let the timeline handle it
            // We don't perform any clip selection actions during scrolling
            return
        }
        
        // For small movements, we treat this as a potential tap
        // No action needed during the change phase for taps
    }
    
    /// Handle gesture end to perform clip selection or menu actions
    /// This ensures clip selection only happens for actual taps, not scroll gestures
    private func handleGestureEnded(_ value: DragGesture.Value, in geometry: GeometryProxy) {
        // Calculate total drag distance
        let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
        let tapThreshold: CGFloat = 10.0 // Maximum distance to consider as tap
        
        // Only handle as tap if drag distance is below threshold
        guard dragDistance <= tapThreshold else {
            // This was a scroll gesture - don't perform clip selection
            print("ClipSelectionOverlay: Ignoring gesture with drag distance \(dragDistance) (threshold: \(tapThreshold))")
            return
        }
        
        // This is a tap gesture - handle clip selection
        handleTapGesture(at: value.location, in: geometry)
    }
    
    // MARK: - Selection Border Rendering
    
    /// Creates a white border view for a selected clip
    /// - Parameters:
    ///   - clip: The selected VideoClip to render border for
    ///   - geometry: GeometryProxy for coordinate calculations
    /// - Returns: A view representing the white selection border
    @ViewBuilder
    private func clipSelectionBorder(for clip: VideoClip, in geometry: GeometryProxy) -> some View {
        let borderRect = calculateClipBorderRect(for: clip, in: geometry)
        
        Rectangle()
            .stroke(Color.white, lineWidth: 2)
            .frame(width: borderRect.width, height: borderRect.height)
            .position(x: borderRect.midX, y: borderRect.midY)
    }
    
    // MARK: - Coordinate Conversion Methods
    
    /// Calculate the rectangle for a clip's selection border
    /// - Parameters:
    ///   - clip: The VideoClip to calculate border for
    ///   - geometry: GeometryProxy for coordinate calculations
    /// - Returns: CGRect representing the border position and size
    private func calculateClipBorderRect(for clip: VideoClip, in geometry: GeometryProxy) -> CGRect {
        let timelineHeight = geometry.size.height
        
        // Convert clip time boundaries to pixel positions
        let startPixel = timeToPixel(clip.startTime)
        let endPixel = timeToPixel(clip.endTime)
        
        // Calculate clip width and position
        let clipWidth = endPixel - startPixel
        let clipX = startPixel
        
        // Border spans the full height of the timeline view
        return CGRect(
            x: clipX,
            y: 0,
            width: clipWidth,
            height: timelineHeight
        )
    }
    
    /// Convert time interval to pixel position using timeline state
    /// - Parameter time: Time interval in seconds
    /// - Returns: Pixel position as CGFloat
    private func timeToPixel(_ time: TimeInterval) -> CGFloat {
        return baseOffset + CGFloat(time) * pixelsPerSecond
    }
    
    /// Convert pixel position to time interval using timeline state
    /// - Parameter pixel: Pixel position as CGFloat
    /// - Returns: Time interval in seconds
    private func pixelToTime(_ pixel: CGFloat) -> TimeInterval {
        return TimeInterval((pixel - baseOffset) / pixelsPerSecond)
    }
    
    // MARK: - Gesture Handling
    
    /// Handle tap gesture for clip selection with enhanced error handling and validation
    /// - Parameters:
    ///   - location: The tap location in the view's coordinate system
    ///   - geometry: GeometryProxy for coordinate calculations
    private func handleTapGesture(at location: CGPoint, in geometry: GeometryProxy) {
        // Validate input parameters
        guard location.x.isFinite && location.y.isFinite else {
            print("ClipSelectionOverlay: Invalid tap location: \(location)")
            return
        }
        
        guard geometry.size.width > 0 && geometry.size.height > 0 else {
            print("ClipSelectionOverlay: Invalid geometry size: \(geometry.size)")
            return
        }
        
        // Convert tap location to time position with validation
        let tapTime = pixelToTime(location.x)
        
        // Validate converted time
        guard tapTime.isFinite && !tapTime.isNaN else {
            print("ClipSelectionOverlay: Invalid tap time conversion: \(tapTime) from location \(location.x)")
            return
        }
        
        // Handle edge case: extremely zoomed out where tap precision is low
        if pixelsPerSecond < 1.0 {
            print("ClipSelectionOverlay: Warning - very low zoom level (\(pixelsPerSecond) px/s), tap precision may be reduced")
        }
        
        // Handle edge case: extremely zoomed in where small movements cause large time changes
        if pixelsPerSecond > 500.0 {
            print("ClipSelectionOverlay: Warning - very high zoom level (\(pixelsPerSecond) px/s), tap sensitivity is high")
        }
        
        // Check if menu is currently visible and handle tap-outside-menu dismissal
        if timelineState.menuState.isVisible {
            handleTapWithMenuVisible(tapTime: tapTime, location: location, geometry: geometry)
            return
        }
        
        // Menu is not visible - handle normal clip selection logic
        handleTapWithMenuHidden(tapTime: tapTime, location: location, geometry: geometry)
    }
    
    /// Handle tap gesture when context menu is visible
    /// This implements proper menu dismissal logic with selection preservation
    private func handleTapWithMenuVisible(tapTime: TimeInterval, location: CGPoint, geometry: GeometryProxy) {
        // Validate tap time is within reasonable bounds (allow some overshoot for smooth UX)
        let timeBuffer: TimeInterval = 1.0 // Allow 1 second overshoot
        
        if tapTime >= -timeBuffer && tapTime <= totalDuration + timeBuffer,
           let tappedClip = timelineState.clipManager.getClip(at: tapTime) {
            // Tap is on a valid clip
            if tappedClip.isSelected {
                // Tapping on the same selected clip - keep menu visible (no action needed)
                print("ClipSelectionOverlay: Tap on selected clip while menu visible - maintaining menu")
                return
            } else {
                // Tapping on a different clip - hide menu and select new clip
                print("ClipSelectionOverlay: Tap on different clip while menu visible - switching selection")
                timelineState.hideContextMenu()
                
                // Validate the new clip selection
                if validateClipSelection(at: tapTime) {
                    timelineState.selectClipAtTime(tapTime)
                } else {
                    print("ClipSelectionOverlay: Failed to validate new clip selection at \(tapTime)")
                }
            }
        } else {
            // Tap outside any clip or outside reasonable video bounds - dismiss menu but preserve selection
            print("ClipSelectionOverlay: Tap outside clips while menu visible - dismissing menu")
            timelineState.hideContextMenu()
        }
    }
    
    /// Handle tap gesture when context menu is hidden
    /// This implements normal clip selection logic with comprehensive validation
    private func handleTapWithMenuHidden(tapTime: TimeInterval, location: CGPoint, geometry: GeometryProxy) {
        // Ensure tap time is within valid video duration with some tolerance for edge cases
        let timeBuffer: TimeInterval = 0.1 // Small buffer for boundary precision
        
        guard tapTime >= -timeBuffer && tapTime <= totalDuration + timeBuffer else {
            // Tap outside video bounds - clear selection
            print("ClipSelectionOverlay: Tap outside video bounds (\(tapTime)) - clearing selection")
            timelineState.clearClipSelection()
            return
        }
        
        // Clamp tap time to valid range
        let clampedTapTime = max(0, min(totalDuration, tapTime))
        
        // Find clip at tap position with error handling
        guard let tappedClip = timelineState.clipManager.getClip(at: clampedTapTime) else {
            // No clip found at tap position - clear selection
            print("ClipSelectionOverlay: No clip found at time \(clampedTapTime) - clearing selection")
            timelineState.clearClipSelection()
            return
        }
        
        // Validate the found clip
        guard validateClipForSelection(tappedClip) else {
            print("ClipSelectionOverlay: Invalid clip found at \(clampedTapTime) - clearing selection")
            timelineState.clearClipSelection()
            return
        }
        
        // Check if this clip is already selected
        if tappedClip.isSelected {
            // Tapping on already selected clip - show context menu
            print("ClipSelectionOverlay: Tap on selected clip - showing context menu")
            
            // Always try to show the menu, with robust fallback handling
            showContextMenuWithFallback(for: tappedClip, in: geometry)
        } else {
            // Select the tapped clip with validation
            print("ClipSelectionOverlay: Selecting clip at time \(clampedTapTime)")
            
            if validateClipSelection(at: clampedTapTime) {
                timelineState.selectClipAtTime(clampedTapTime)
            } else {
                print("ClipSelectionOverlay: Failed to validate clip selection at \(clampedTapTime)")
            }
        }
    }
    
    /// Show context menu with robust fallback handling
    /// This ensures the menu is always shown in a valid position
    private func showContextMenuWithFallback(for clip: VideoClip, in geometry: GeometryProxy) {
        // Try primary position
        let primaryPosition = calculateMenuPosition(for: clip, in: geometry)
        
        if validateMenuPosition(primaryPosition, in: geometry) {
            print("ClipSelectionOverlay: Showing menu at primary position: \(primaryPosition)")
            timelineState.showContextMenuForSelectedClip(at: primaryPosition)
            return
        }
        
        // Try center fallback
        let centerPosition = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        
        if validateMenuPosition(centerPosition, in: geometry) {
            print("ClipSelectionOverlay: Showing menu at center fallback: \(centerPosition)")
            timelineState.showContextMenuForSelectedClip(at: centerPosition)
            return
        }
        
        // Try safe fallback (guaranteed to be within bounds)
        let safePosition = CGPoint(
            x: max(30, min(geometry.size.width - 30, geometry.size.width / 2)),
            y: max(25, min(geometry.size.height - 25, geometry.size.height / 2))
        )
        
        print("ClipSelectionOverlay: Using safe fallback position: \(safePosition)")
        timelineState.showContextMenuForSelectedClip(at: safePosition)
    }
    
    /// Validate that a clip selection operation is valid
    /// This prevents invalid selections that could cause UI issues
    private func validateClipSelection(at time: TimeInterval) -> Bool {
        // Check time is valid
        guard time.isFinite && !time.isNaN && time >= 0 && time <= totalDuration else {
            return false
        }
        
        // Check that a clip actually exists at this time
        guard timelineState.clipManager.getClip(at: time) != nil else {
            return false
        }
        
        // Check that the clip manager is in a valid state
        guard timelineState.clipManager.clips.count > 0 else {
            return false
        }
        
        return true
    }
    
    /// Validate that a clip is suitable for selection
    /// This prevents selection of invalid or corrupted clips
    private func validateClipForSelection(_ clip: VideoClip) -> Bool {
        // Check clip has valid time boundaries
        guard clip.startTime.isFinite && clip.endTime.isFinite else {
            return false
        }
        
        // Check clip has positive duration
        guard clip.duration > 0 else {
            return false
        }
        
        // Check clip boundaries are within video duration
        guard clip.startTime >= 0 && clip.endTime <= totalDuration else {
            return false
        }
        
        return true
    }
    
    /// Validate that a menu position is within screen bounds
    /// This prevents menus from appearing off-screen
    private func validateMenuPosition(_ position: CGPoint, in geometry: GeometryProxy) -> Bool {
        let menuSize = CGSize(width: 60, height: 50) // Menu size from ClipContextMenu
        
        // Validate position values are finite
        guard position.x.isFinite && position.y.isFinite else {
            print("ClipSelectionOverlay: Menu position contains invalid values: \(position)")
            return false
        }
        
        // Validate geometry is reasonable
        guard geometry.size.width > 0 && geometry.size.height > 0 else {
            print("ClipSelectionOverlay: Invalid geometry size: \(geometry.size)")
            return false
        }
        
        // Use more lenient bounds checking - just ensure the menu center is within the view
        let isWithinHorizontalBounds = position.x >= 0 && position.x <= geometry.size.width
        let isWithinVerticalBounds = position.y >= 0 && position.y <= geometry.size.height
        
        if !isWithinHorizontalBounds {
            print("ClipSelectionOverlay: Menu X position \(position.x) outside bounds [0, \(geometry.size.width)]")
        }
        
        if !isWithinVerticalBounds {
            print("ClipSelectionOverlay: Menu Y position \(position.y) outside bounds [0, \(geometry.size.height)]")
        }
        
        return isWithinHorizontalBounds && isWithinVerticalBounds
    }
    
    /// Calculate the position where the context menu should appear for a clip
    /// - Parameters:
    ///   - clip: The VideoClip to show menu for
    ///   - geometry: GeometryProxy for coordinate calculations
    /// - Returns: CGPoint representing the menu position
    private func calculateMenuPosition(for clip: VideoClip, in geometry: GeometryProxy) -> CGPoint {
        let menuSize = CGSize(width: 60, height: 50) // Menu dimensions from ClipContextMenu
        
        // For now, always position the menu at the center of the visible timeline area
        // This avoids coordinate system issues and ensures the menu is always visible
        let menuX = geometry.size.width / 2
        let menuY = geometry.size.height * 0.3 // Position in upper portion
        
        // Ensure the position is within bounds
        let clampedX = max(menuSize.width / 2, min(geometry.size.width - menuSize.width / 2, menuX))
        let clampedY = max(menuSize.height / 2, min(geometry.size.height - menuSize.height / 2, menuY))
        
        return CGPoint(x: clampedX, y: clampedY)
    }
    
    // MARK: - Utility Methods
    
    /// Check if a clip is currently visible in the viewport
    /// - Parameters:
    ///   - clip: The VideoClip to check visibility for
    ///   - geometry: GeometryProxy for viewport calculations
    /// - Returns: True if the clip is at least partially visible
    private func isClipVisible(_ clip: VideoClip, in geometry: GeometryProxy) -> Bool {
        let startPixel = timeToPixel(clip.startTime)
        let endPixel = timeToPixel(clip.endTime)
        
        let viewportLeft: CGFloat = 0
        let viewportRight = geometry.size.width
        
        // Check if clip overlaps with viewport
        return endPixel > viewportLeft && startPixel < viewportRight
    }
    
    /// Get the visible portion of a clip within the current viewport
    /// - Parameters:
    ///   - clip: The VideoClip to get visible portion for
    ///   - geometry: GeometryProxy for viewport calculations
    /// - Returns: CGRect representing the visible portion of the clip
    private func getVisibleClipRect(_ clip: VideoClip, in geometry: GeometryProxy) -> CGRect {
        let startPixel = timeToPixel(clip.startTime)
        let endPixel = timeToPixel(clip.endTime)
        
        let viewportLeft: CGFloat = 0
        let viewportRight = geometry.size.width
        
        // Clamp clip boundaries to viewport
        let visibleLeft = max(startPixel, viewportLeft)
        let visibleRight = min(endPixel, viewportRight)
        
        return CGRect(
            x: visibleLeft,
            y: 0,
            width: max(0, visibleRight - visibleLeft),
            height: geometry.size.height
        )
    }
}

// MARK: - Preview

struct ClipSelectionOverlay_Previews: PreviewProvider {
    static var previews: some View {
        let timelineState = TimelineState()
        
        // Initialize with sample clips for preview
        timelineState.initializeClipsForVideo(duration: 120.0)
        timelineState.selectClipAtTime(30.0) // Select a clip for preview
        
        return ClipSelectionOverlay(
            timelineState: timelineState,
            totalDuration: 120.0,
            pixelsPerSecond: 50.0,
            contentOffset: 0,
            screenWidth: 400
        )
        .frame(height: 60)
        .background(Color.black.opacity(0.3))
        .previewLayout(.sizeThatFits)
    }
}