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
/// Manages zoom levels, content offset, and coordinate conversions
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
    
    /// Whether a seek operation is currently in progress
    @Published var isSeeking: Bool = false
    
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
        isSeeking = false
        
        // Clean up debouncing state
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
    
    // MARK: - Seeking Methods
    
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
    
    func performSeek(
        to targetTime: TimeInterval,
        player: AVPlayer,
        completion: ((Bool, Error?) -> Void)? = nil
    ) {
        // Prevent concurrent seeks
        guard !isSeeking else {
            completion?(false, nil)
            return
        }

        isSeeking = true
        
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            DispatchQueue.main.async {
                self?.isSeeking = false
                self?.handleSeekCompletion(
                    completed: completed,
                    targetTime: targetTime,
                    completion: completion
                )
            }
        }
        
        updateLastSeekTime(CACurrentMediaTime())
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
}