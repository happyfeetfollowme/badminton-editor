import SwiftUI
import Foundation
import AVFoundation



// MARK: - Seek Error Types

/// Errors that can occur during seek operations
enum SeekError: Error, LocalizedError {
    case noPendingSeek
    case seekFailed(targetTime: TimeInterval, consecutiveFailures: Int)
    case playerNotReady
    case invalidTimeRange
    
    var errorDescription: String? {
        switch self {
        case .noPendingSeek:
            return "No pending seek operation to execute"
        case .seekFailed(let targetTime, let failures):
            return "Seek to \(targetTime)s failed (consecutive failures: \(failures))"
        case .playerNotReady:
            return "AVPlayer is not ready for seeking"
        case .invalidTimeRange:
            return "Target seek time is outside valid range"
        }
    }
}

/// Core timeline state management for the scrubbing timeline feature
/// Manages zoom levels, content offset, coordinate conversions, and clip management
class TimelineState: ObservableObject {
    // MARK: - Published Properties
    
    /// Current zoom level in pixels per second
    @Published var pixelsPerSecond: CGFloat = 50.0
    
    /// Current content offset for timeline scrolling
    @Published var contentOffset: CGFloat = 0
    
    /// Whether the user is currently dragging the timeline
    @Published var isDragging: Bool = false
    
    /// Last time a seek operation was performed (for debouncing)
    @Published var lastSeekTime: TimeInterval = 0
    
    /// Current drag velocity for smooth gesture handling
    @Published var dragVelocity: CGFloat = 0
    
    /// Whether the timeline is currently being actively scrubbed
    @Published var isActivelyScrubbing: Bool = false
    
    // MARK: - Clip Management Properties
    
    /// Manages video clips and split points
    private var _clipManager: ClipManager?
    var clipManager: ClipManager {
        if _clipManager == nil {
            _clipManager = ClipManager()
        }
        return _clipManager!
    }
    
    /// Manages context menu state for clip operations
    private var _menuState: MenuState?
    var menuState: MenuState {
        if _menuState == nil {
            _menuState = MenuState()
        }
        return _menuState!
    }
    
    /// Timer for debounced seeking operations
    private var seekDebounceTimer: Timer?
    
    /// Pending seek time for debounced operations
    private var pendingSeekTime: TimeInterval?
    
    /// Last successful seek time for error recovery
    private var lastSuccessfulSeekTime: TimeInterval = 0
    
    /// Number of consecutive seek failures for error handling
    private var consecutiveSeekFailures: Int = 0
    
    // MARK: - Zoom Level Constants
    
    /// Minimum zoom level (pixels per second)
    static let minZoom: CGFloat = 10.0
    
    /// Maximum zoom level (pixels per second)
    static let maxZoom: CGFloat = 200.0
    
    /// Predefined zoom steps for consistent zoom behavior
    static let zoomLevels: [CGFloat] = [10, 25, 50, 100, 150, 200]
    
    // MARK: - Initialization
    
    init() {
        // Initialize with default zoom level
        self.pixelsPerSecond = 50.0
        self.contentOffset = 0
        self.isDragging = false
        self.lastSeekTime = 0
    }
    
    // MARK: - Zoom Management Methods
    
    /// Zoom in to the next available zoom level
    func zoomIn() {
        let nextLevel = Self.zoomLevels.first { $0 > pixelsPerSecond } ?? Self.maxZoom
        pixelsPerSecond = min(Self.maxZoom, nextLevel)
    }
    
    /// Zoom out to the previous available zoom level
    func zoomOut() {
        let prevLevel = Self.zoomLevels.last { $0 < pixelsPerSecond } ?? Self.minZoom
        pixelsPerSecond = max(Self.minZoom, prevLevel)
    }
    
    /// Set zoom to a specific level, clamped to valid range
    /// - Parameter zoomLevel: The desired zoom level in pixels per second
    func setZoom(to zoomLevel: CGFloat) {
        pixelsPerSecond = max(Self.minZoom, min(Self.maxZoom, zoomLevel))
    }
    
    // MARK: - Time-to-Pixel Conversion Methods
    
    /// Convert time interval to pixel position
    /// - Parameters:
    ///   - time: Time interval in seconds
    ///   - baseOffset: Base offset to add to the calculation (default: 0)
    /// - Returns: Pixel position as CGFloat
    func timeToPixel(_ time: TimeInterval, baseOffset: CGFloat = 0) -> CGFloat {
        return CGFloat(time) * pixelsPerSecond + baseOffset
    }
    
    /// Convert pixel position to time interval
    /// - Parameters:
    ///   - pixel: Pixel position as CGFloat
    ///   - baseOffset: Base offset to subtract from the calculation (default: 0)
    /// - Returns: Time interval in seconds
    func pixelToTime(_ pixel: CGFloat, baseOffset: CGFloat = 0) -> TimeInterval {
        return TimeInterval((pixel - baseOffset) / pixelsPerSecond)
    }
    
    /// Calculate content offset needed to center a specific time on screen
    /// - Parameters:
    ///   - time: The time to center
    ///   - screenWidth: Width of the screen/viewport
    ///   - baseOffset: Base offset for timeline content (default: 500)
    /// - Returns: Content offset needed to center the time
    func calculateOffsetToCenter(time: TimeInterval, screenWidth: CGFloat, baseOffset: CGFloat = 500) -> CGFloat {
        let timePosition = timeToPixel(time, baseOffset: baseOffset)
        return screenWidth / 2 - timePosition
    }
    
    /// Calculate time at screen center given current content offset
    /// - Parameters:
    ///   - screenWidth: Width of the screen/viewport
    ///   - baseOffset: Base offset for timeline content (default: 500)
    /// - Returns: Time interval at screen center
    func timeAtScreenCenter(screenWidth: CGFloat, baseOffset: CGFloat = 500) -> TimeInterval {
        let centerPixel = screenWidth / 2 - contentOffset + baseOffset
        return pixelToTime(centerPixel)
    }
    
    // MARK: - Content Width Calculation
    
    /// Calculate total content width for a given duration
    /// - Parameters:
    ///   - duration: Total duration of the timeline content
    ///   - extraPadding: Additional padding to add (default: 1000)
    /// - Returns: Total content width in pixels
    func calculateContentWidth(for duration: TimeInterval, extraPadding: CGFloat = 1000) -> CGFloat {
        guard duration > 0 else { return 400 }
        return CGFloat(duration) * pixelsPerSecond + extraPadding
    }
    
    // MARK: - Utility Methods
    
    /// Reset timeline state to default values
    func reset() {
        pixelsPerSecond = 50.0
        contentOffset = 0
        isDragging = false
        lastSeekTime = 0
        dragVelocity = 0
        isActivelyScrubbing = false
        
        // Clean up debouncing state
        cancelPendingSeek()
        lastSuccessfulSeekTime = 0
        consecutiveSeekFailures = 0
    }
    
    // MARK: - Drag Gesture Support Methods
    
    /// Start drag gesture state tracking
    func startDragGesture() {
        isDragging = true
        isActivelyScrubbing = true
        dragVelocity = 0
    }
    
    /// End drag gesture state tracking
    func endDragGesture() {
        isDragging = false
        isActivelyScrubbing = false
        dragVelocity = 0
    }
    
    /// Update drag velocity for smooth gesture handling
    /// - Parameter velocity: Current drag velocity in pixels per second
    func updateDragVelocity(_ velocity: CGFloat) {
        dragVelocity = velocity
    }
    
    /// Check if seeking should be performed based on debouncing rules
    /// - Parameter currentTime: Current system time for debouncing calculation
    /// - Returns: True if seeking should be performed
    func shouldPerformSeek(at currentTime: TimeInterval) -> Bool {
        let timeSinceLastSeek = currentTime - lastSeekTime
        return timeSinceLastSeek > 0.033 // ~30fps limit
    }
    
    /// Update last seek time for debouncing
    /// - Parameter time: Current system time
    func updateLastSeekTime(_ time: TimeInterval) {
        lastSeekTime = time
    }
    
    // MARK: - Enhanced Debouncing Methods
    
    /// Schedule a debounced seek operation using timer-based approach
    /// - Parameters:
    ///   - targetTime: The time to seek to
    ///   - player: AVPlayer instance to perform seek on
    ///   - completion: Optional completion handler called after seek attempt
    func scheduleDebouncedSeek(
        to targetTime: TimeInterval,
        player: AVPlayer,
        completion: ((Bool, Error?) -> Void)? = nil
    ) {
        // Store the pending seek time
        pendingSeekTime = targetTime
        
        // Cancel any existing timer
        seekDebounceTimer?.invalidate()
        
        // Create new timer with 33ms delay (30fps limit)
        seekDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: false) { [weak self] _ in
            self?.executePendingSeek(player: player, completion: completion)
        }
    }
    
    /// Execute the pending seek operation with error handling
    /// - Parameters:
    ///   - player: AVPlayer instance to perform seek on
    ///   - completion: Optional completion handler called after seek attempt
    private func executePendingSeek(
        player: AVPlayer,
        completion: ((Bool, Error?) -> Void)? = nil
    ) {
        guard let targetTime = pendingSeekTime else {
            completion?(false, SeekError.noPendingSeek)
            return
        }
        
        // Clear pending seek
        pendingSeekTime = nil
        
        // Create CMTime with high precision timescale
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        
        // Perform seek with completion handler for error tracking
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            DispatchQueue.main.async {
                self?.handleSeekCompletion(
                    completed: completed,
                    targetTime: targetTime,
                    completion: completion
                )
            }
        }
        
        // Update last seek time
        updateLastSeekTime(CACurrentMediaTime())
    }
    
    /// Handle seek operation completion with error tracking
    /// - Parameters:
    ///   - completed: Whether the seek completed successfully
    ///   - targetTime: The time that was sought to
    ///   - completion: Optional completion handler to call
    private func handleSeekCompletion(
        completed: Bool,
        targetTime: TimeInterval,
        completion: ((Bool, Error?) -> Void)?
    ) {
        if completed {
            // Reset failure count on successful seek
            consecutiveSeekFailures = 0
            lastSuccessfulSeekTime = targetTime
            completion?(true, nil)
        } else {
            // Increment failure count
            consecutiveSeekFailures += 1
            
            // Create error with failure information
            let error = SeekError.seekFailed(
                targetTime: targetTime,
                consecutiveFailures: consecutiveSeekFailures
            )
            
            completion?(false, error)
            
            // Log error for debugging (in production, this could be sent to analytics)
            print("Seek failed: \(error.localizedDescription)")
        }
    }
    
    /// Perform immediate seek without debouncing (for final precision seeks)
    /// - Parameters:
    ///   - targetTime: The time to seek to
    ///   - player: AVPlayer instance to perform seek on
    ///   - completion: Optional completion handler called after seek attempt
    func performImmediateSeek(
        to targetTime: TimeInterval,
        player: AVPlayer,
        completion: ((Bool, Error?) -> Void)? = nil
    ) {
        // Cancel any pending debounced seeks
        cancelPendingSeek()
        
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            DispatchQueue.main.async {
                self?.handleSeekCompletion(
                    completed: completed,
                    targetTime: targetTime,
                    completion: completion
                )
            }
        }
        
        updateLastSeekTime(CACurrentMediaTime())
    }
    
    /// Cancel any pending debounced seek operations
    func cancelPendingSeek() {
        seekDebounceTimer?.invalidate()
        seekDebounceTimer = nil
        pendingSeekTime = nil
    }
    
    /// Check if there are too many consecutive seek failures
    var hasTooManySeekFailures: Bool {
        return consecutiveSeekFailures >= 5
    }
    
    /// Reset seek failure tracking
    func resetSeekFailureTracking() {
        consecutiveSeekFailures = 0
    }
    
    /// Get the last successful seek time for error recovery
    var lastKnownGoodSeekTime: TimeInterval {
        return lastSuccessfulSeekTime
    }
    
    /// Check if current zoom level is at minimum
    var isAtMinZoom: Bool {
        return pixelsPerSecond <= Self.minZoom
    }
    
    /// Check if current zoom level is at maximum
    var isAtMaxZoom: Bool {
        return pixelsPerSecond >= Self.maxZoom
    }
    
    /// Get current zoom level as a percentage (0-100)
    var zoomPercentage: Double {
        let range = Self.maxZoom - Self.minZoom
        let current = pixelsPerSecond - Self.minZoom
        return Double(current / range) * 100
    }
    
    // MARK: - Clip Management Integration Methods
    
    /// Initialize clips when a video is loaded
    /// Integrates clip initialization with video loading (Requirement 1.1)
    /// - Parameter duration: Total duration of the loaded video
    func initializeClipsForVideo(duration: TimeInterval) {
        clipManager.initializeClips(duration: duration)
    }
    
    /// Handle clip selection at a specific time position
    /// Coordinates between timeline position and clip selection (Requirements 2.1, 2.2)
    /// - Parameter time: Time position where clip selection should occur
    func selectClipAtTime(_ time: TimeInterval) {
        clipManager.selectClip(at: time)
    }
    
    /// Clear clip selection and hide any visible menu
    /// Coordinates selection clearing between clip manager and menu state
    func clearClipSelection() {
        clipManager.clearSelection()
        menuState.hideMenu()
    }
    
    /// Show context menu for the selected clip at the specified position
    /// Coordinates menu display with clip selection state
    /// - Parameter position: Position where the menu should appear
    func showContextMenuForSelectedClip(at position: CGPoint) {
        guard let selectedClip = clipManager.getSelectedClip() else { return }
        menuState.showMenu(at: position, for: selectedClip.id)
    }
    
    /// Hide the context menu without affecting clip selection
    func hideContextMenu() {
        menuState.hideMenu()
    }
    
    /// Get the currently selected clip
    /// - Returns: The selected VideoClip if any, nil otherwise
    func getSelectedClip() -> VideoClip? {
        return clipManager.getSelectedClip()
    }
    
    /// Get the clip at a specific time position
    /// - Parameter time: Time position to search for
    /// - Returns: VideoClip if found, nil otherwise
    func getClipAtTime(_ time: TimeInterval) -> VideoClip? {
        return clipManager.getClip(at: time)
    }
    
    /// Add a split point at the current playhead position with enhanced validation
    /// Coordinates split operations between timeline and clip management with comprehensive error handling
    /// - Parameter time: Time position where the split should occur
    /// - Returns: True if split was successful, false otherwise
    @discardableResult
    func addSplitPointAtTime(_ time: TimeInterval) -> Bool {
        // Comprehensive validation before attempting split
        guard validateSplitOperation(at: time) else {
            print("TimelineState: Split operation validation failed at time \(time)")
            return false
        }
        
        // Attempt split with error handling
        let success = clipManager.addSplitPoint(at: time)
        
        if success {
            // Hide menu after successful split operation
            menuState.hideMenu()
            
            // Log successful split for debugging/analytics
            print("TimelineState: Successfully added split point at \(time)")
            
            // Validate the resulting clip state
            if !validateClipStateAfterSplit() {
                print("TimelineState: Warning - clip state validation failed after split")
            }
        } else {
            print("TimelineState: Failed to add split point at \(time)")
        }
        
        return success
    }
    
    /// Validate that a split operation can be performed at the specified time
    /// This provides comprehensive validation before attempting the split
    private func validateSplitOperation(at time: TimeInterval) -> Bool {
        // Basic time validation
        guard time.isFinite && !time.isNaN && time >= 0 else {
            print("TimelineState: Invalid split time - not finite or negative: \(time)")
            return false
        }
        
        // Check if there's a clip at this time
        guard let targetClip = clipManager.getClip(at: time) else {
            print("TimelineState: No clip found at split time \(time)")
            return false
        }
        
        // Validate the target clip is suitable for splitting
        guard targetClip.duration > 0.2 else { // Minimum 200ms for splitting
            print("TimelineState: Target clip too short for splitting: \(targetClip.duration)s")
            return false
        }
        
        // Check that split point is not too close to clip boundaries
        let minDistanceFromBoundary: TimeInterval = 0.1
        let distanceFromStart = time - targetClip.startTime
        let distanceFromEnd = targetClip.endTime - time
        
        if distanceFromStart < minDistanceFromBoundary {
            print("TimelineState: Split too close to clip start: \(distanceFromStart)s")
            return false
        }
        
        if distanceFromEnd < minDistanceFromBoundary {
            print("TimelineState: Split too close to clip end: \(distanceFromEnd)s")
            return false
        }
        
        return true
    }
    
    /// Validate the clip state after a split operation
    /// This ensures the split operation resulted in a valid clip configuration
    private func validateClipStateAfterSplit() -> Bool {
        let clips = clipManager.clips
        
        // Check that we have at least one clip
        guard !clips.isEmpty else {
            print("TimelineState: No clips after split operation")
            return false
        }
        
        // Validate each clip has positive duration
        for (index, clip) in clips.enumerated() {
            if clip.duration <= 0 {
                print("TimelineState: Clip \(index) has invalid duration: \(clip.duration)")
                return false
            }
        }
        
        // Check for gaps or overlaps between clips
        let sortedClips = clips.sorted { $0.startTime < $1.startTime }
        for i in 0..<(sortedClips.count - 1) {
            let currentClip = sortedClips[i]
            let nextClip = sortedClips[i + 1]
            
            let gap = nextClip.startTime - currentClip.endTime
            if abs(gap) > 0.001 {
                print("TimelineState: Gap between clips \(i) and \(i+1): \(gap)s")
                return false
            }
        }
        
        return true
    }
    
    /// Reset timeline state including clip management
    /// Extended reset method that also clears clip and menu state
    func resetWithClipManagement() {
        // Reset timeline state
        reset()
        
        // Reset clip management state
        clipManager.reset()
        menuState.hideMenu()
    }
}