import SwiftUI
import AVFoundation

/// Context menu component for clip operations
/// Displays a popup menu with split functionality when a clip is selected
struct ClipContextMenu: View {
    // MARK: - Properties
    
    /// The current playhead time from AVPlayer
    let currentTime: TimeInterval
    
    /// Callback to handle split action
    let onSplit: () -> Void
    
    /// Callback to handle menu dismissal
    let onDismiss: () -> Void
    
    // MARK: - Constants
    
    /// Menu dimensions and styling
    private let menuWidth: CGFloat = 60
    private let menuHeight: CGFloat = 50
    private let iconSize: CGFloat = 24
    private let cornerRadius: CGFloat = 8
    private let shadowRadius: CGFloat = 4
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 8) {
            // Split action button
            Button(action: handleSplitAction) {
                VStack(spacing: 4) {
                    // Split icon using the square-split-horizontal asset (Requirement 3.4)
                    Image("EditMenu")
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .foregroundColor(.primary)
                    
                    // Action label
                    Text("Split")
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
                .frame(width: menuWidth - 16, height: menuHeight - 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(width: menuWidth, height: menuHeight)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.regularMaterial)
                .shadow(radius: shadowRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
    
    // MARK: - Actions
    
    /// Handle split action button tap
    /// Creates split point at current playhead position and dismisses menu (Requirements 4.1, 4.6)
    private func handleSplitAction() {
        // Perform split operation
        onSplit()
        
        // Dismiss menu after split action (Requirement 4.6)
        onDismiss()
    }
}

/// Container view for positioning the ClipContextMenu
/// Handles menu positioning logic centered on timeline view (Requirements 3.2, 3.3)
struct ClipContextMenuContainer: View {
    // MARK: - Properties
    
    /// Menu state for visibility and positioning
    @ObservedObject var menuState: MenuState
    
    /// Timeline state for accessing current playhead time and split functionality
    @ObservedObject var timelineState: TimelineState
    
    /// AVPlayer reference for getting current playhead time
    let player: AVPlayer?
    
    /// Timeline view geometry for positioning calculations
    let timelineGeometry: GeometryProxy
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if menuState.isVisible {
                ClipContextMenu(
                    currentTime: getCurrentPlayheadTime(),
                    onSplit: handleSplitAction,
                    onDismiss: handleMenuDismiss
                )
                .position(calculateMenuPosition())
                .zIndex(1000) // Ensure menu appears above other content
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .animation(.easeInOut(duration: 0.2), value: menuState.isVisible)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Calculate the menu position centered on timeline view (Requirements 3.2, 3.3)
    /// - Returns: CGPoint for menu positioning
    private func calculateMenuPosition() -> CGPoint {
        // Use the position from MenuState if available, otherwise fallback to center
        if menuState.isVisible && menuState.position != .zero {
            return menuState.position
        }
        
        // Fallback to timeline center with bounds checking
        let menuSize = CGSize(width: 60, height: 50)
        let timelineCenter = timelineGeometry.size.width / 2
        
        // Ensure menu stays within bounds
        let minX = menuSize.width / 2
        let maxX = timelineGeometry.size.width - menuSize.width / 2
        let menuX = max(minX, min(maxX, timelineCenter))
        
        // Position menu in upper portion with bounds checking
        let minY = menuSize.height / 2
        let maxY = timelineGeometry.size.height - menuSize.height / 2
        let menuY = max(minY, min(maxY, timelineGeometry.size.height * 0.3))
        
        return CGPoint(x: menuX, y: menuY)
    }
    
    /// Get current playhead time from AVPlayer with comprehensive validation
    /// Enhanced with better error handling for edge cases
    /// - Returns: Current time in seconds, validated to be within valid range
    private func getCurrentPlayheadTime() -> TimeInterval {
        guard let player = player else {
            print("ClipContextMenu: No player available for playhead time")
            return 0.0
        }
        
        let currentTime = player.currentTime()
        
        // Comprehensive validation of AVPlayer time
        guard currentTime.isValid else {
            print("ClipContextMenu: AVPlayer time is invalid")
            return 0.0
        }
        
        guard !currentTime.seconds.isNaN else {
            print("ClipContextMenu: AVPlayer time is NaN")
            return 0.0
        }
        
        guard currentTime.seconds.isFinite else {
            print("ClipContextMenu: AVPlayer time is not finite: \(currentTime.seconds)")
            return 0.0
        }
        
        // Handle edge case: negative time (can happen during seeking)
        if currentTime.seconds < 0 {
            print("ClipContextMenu: AVPlayer time is negative: \(currentTime.seconds), clamping to 0")
            return 0.0
        }
        
        // Handle edge case: time beyond reasonable bounds (24 hours)
        let maxReasonableTime: TimeInterval = 86400 // 24 hours
        if currentTime.seconds > maxReasonableTime {
            print("ClipContextMenu: AVPlayer time is extremely large: \(currentTime.seconds), may be invalid")
            // Still return it but log the warning
        }
        
        return currentTime.seconds
    }
    
    /// Handle split action by creating split point at current playhead position
    /// Enhanced with comprehensive error handling and validation
    /// Implements Requirements 4.1, 4.3, 4.4
    private func handleSplitAction() {
        let currentTime = getCurrentPlayheadTime()
        
        // Validate current time before attempting split
        guard currentTime.isFinite && !currentTime.isNaN && currentTime >= 0 else {
            print("ClipContextMenu: Invalid playhead time for split: \(currentTime)")
            handleSplitError("Invalid playhead time")
            return
        }
        
        // Check if there's a selected clip to split
        guard let selectedClip = timelineState.clipManager.getSelectedClip() else {
            print("ClipContextMenu: No selected clip to split")
            handleSplitError("No clip selected")
            return
        }
        
        // Validate that the current time is within the selected clip
        guard selectedClip.contains(time: currentTime) else {
            print("ClipContextMenu: Playhead time \(currentTime) is not within selected clip (\(selectedClip.startTime) - \(selectedClip.endTime))")
            handleSplitError("Playhead not in selected clip")
            return
        }
        
        // Check for edge cases that would create very short clips
        let minClipDuration: TimeInterval = 0.1
        let leftDuration = currentTime - selectedClip.startTime
        let rightDuration = selectedClip.endTime - currentTime
        
        if leftDuration < minClipDuration {
            print("ClipContextMenu: Split would create too short left clip: \(leftDuration)s")
            handleSplitError("Split too close to clip start")
            return
        }
        
        if rightDuration < minClipDuration {
            print("ClipContextMenu: Split would create too short right clip: \(rightDuration)s")
            handleSplitError("Split too close to clip end")
            return
        }
        
        // Debug logging to verify playhead integration
        print("ClipContextMenu: Attempting to split at playhead time: \(currentTime) within clip (\(selectedClip.startTime) - \(selectedClip.endTime))")
        
        // Add split point at current playhead position (Requirement 4.1)
        let success = timelineState.addSplitPointAtTime(currentTime)
        
        if success {
            print("ClipContextMenu: Successfully created split point at \(currentTime)")
            // Clear clip selection after successful split (Requirement 4.6)
            timelineState.clearClipSelection()
            
            // Provide user feedback for successful split
            handleSplitSuccess(at: currentTime)
        } else {
            print("ClipContextMenu: Failed to create split point at \(currentTime) - validation failed")
            handleSplitError("Split validation failed")
        }
    }
    
    /// Handle successful split operation
    /// This can be extended to provide user feedback
    private func handleSplitSuccess(at time: TimeInterval) {
        // Log success for debugging
        print("ClipContextMenu: Split operation completed successfully at \(time)")
        
        // Future enhancement: Could trigger haptic feedback or show success indicator
        // HapticFeedback.success()
        
        // Future enhancement: Could trigger analytics event
        // Analytics.track("clip_split_success", properties: ["time": time])
    }
    
    /// Handle split operation errors with user-friendly messaging
    /// This provides better error handling and potential user feedback
    private func handleSplitError(_ reason: String) {
        print("ClipContextMenu: Split operation failed - \(reason)")
        
        // Future enhancement: Could show user-facing error message
        // ErrorBanner.show("Cannot split clip: \(reason)")
        
        // Future enhancement: Could trigger haptic feedback for error
        // HapticFeedback.error()
        
        // Future enhancement: Could trigger analytics event
        // Analytics.track("clip_split_error", properties: ["reason": reason])
    }
    
    /// Handle menu dismissal
    /// Hides menu but preserves clip selection state
    private func handleMenuDismiss() {
        menuState.hideMenu()
    }
}

// MARK: - Preview

#if DEBUG
struct ClipContextMenu_Previews: PreviewProvider {
    static var previews: some View {
        GeometryReader { geometry in
            ZStack {
                Color.gray.opacity(0.3)
                
                ClipContextMenu(
                    currentTime: 10.5,
                    onSplit: {
                        print("Split action triggered")
                    },
                    onDismiss: {
                        print("Menu dismissed")
                    }
                )
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .frame(height: 200)
        .previewDisplayName("Context Menu")
    }
}
#endif