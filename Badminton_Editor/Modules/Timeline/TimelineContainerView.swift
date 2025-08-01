import SwiftUI
import AVKit
import AVFoundation

/// Main container view that orchestrates the timeline scrubbing experience
/// Replaces the existing SimplifiedTimelineView with enhanced functionality
struct TimelineContainerView: View {
    // MARK: - Bindings
    @Binding var player: AVPlayer
    @Binding var currentTime: TimeInterval
    @Binding var totalDuration: TimeInterval
    @ObservedObject var thumbnailProvider: ThumbnailProvider
    
    // MARK: - State Management
    @StateObject private var timelineState = TimelineState()
    @StateObject private var performanceMonitor = PerformanceMonitor()
    @State private var showMarkerMenu = false
    @State private var menuPosition: CGPoint = .zero
    
    // MARK: - Drag Gesture State
    @State private var dragStartTime: TimeInterval = 0
    @State private var dragStartLocation: CGPoint = .zero
    @State private var lastDragTranslation: CGSize = .zero
    
    // MARK: - Automatic Scrolling State
    @State private var timeObserver: Any?
    @State private var isAutoScrollingEnabled = true
    @State private var lastAutoScrollTime: TimeInterval = 0
    

    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.opacity(0.1)
                    .edgesIgnoringSafeArea(.all)
                
                // Main timeline content stack
                ZStack {
                    timelineContentArea(geometry: geometry)
                    
                    // Fixed playback marker overlay
                    playbackMarkerOverlay(geometry: geometry)
                    
                    // Timeline controls overlay
                    timelineControlsOverlay(geometry: geometry)
                }
                .coordinateSpace(name: "timeline")
                .clipped()
                
                // Performance monitoring overlay (debug mode)
                if ProcessInfo.processInfo.environment["DEBUG_PERFORMANCE"] != nil {
                    performanceOverlay(geometry: geometry)
                }
            }
        }
        .onAppear {
            setupTimelineState()
            setupAutomaticScrolling()
            setupPerformanceMonitoring()
        }
        .onDisappear {
            cleanupAutomaticScrolling()
            cleanupPerformanceMonitoring()
        }
        .onChange(of: currentTime) { _, newTime in
            updateTimelineForCurrentTime(newTime)
        }
        .onChange(of: totalDuration) { _, newDuration in
            handleDurationChange(newDuration)
        }
        .onChange(of: player) { _, newPlayer in
            setupAutomaticScrolling()
        }
    }
    
    // MARK: - Timeline Content Area
    
    @ViewBuilder
    private func timelineContentArea(geometry: GeometryProxy) -> some View {
        ZStack {
            // Background for timeline content
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: geometry.size.height)
            
            // Timeline content view with scrollable content
            TimelineContentView(
                player: player,
                totalDuration: totalDuration,
                pixelsPerSecond: timelineState.pixelsPerSecond,
                contentOffset: $timelineState.contentOffset,
                isDragging: timelineState.isDragging,
                screenWidth: geometry.size.width,
                thumbnailProvider: thumbnailProvider,
                timelineState: timelineState
            )
            .simultaneousGesture(
                // Enhanced drag gesture with conflict resolution
                createTimelineScrollGesture(geometry: geometry)
            )
            .onTapGesture { location in
                handleTapGesture(location, screenWidth: geometry.size.width)
            }
            .onTapGesture(count: 2) { location in
                handleDoubleTapGesture(location)
            }
        }
    }
    
    // MARK: - Playback Marker Overlay
    
    @ViewBuilder
    private func playbackMarkerOverlay(geometry: GeometryProxy) -> some View {
        VStack(spacing: 2) {
           // Fixed playback marker line - highlight when scrubbing
            Rectangle()
                .fill(timelineState.isDragging ? Color.blue : Color.white)
                .frame(width: timelineState.isDragging ? 3 : 2)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 0)
                .animation(.easeInOut(duration: 0.2), value: timelineState.isDragging)
        }
        .frame(height: geometry.size.height)
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
    
    /// Calculate the time being scrubbed to during drag operations
    private func calculateScrubbingTime(timelineHeight: CGFloat = 120) -> TimeInterval {
        if timelineState.isDragging && dragStartTime > 0 {
            // Calculate based on current drag state
            // Positive drag (right) = backward in time, negative drag (left) = forward in time
            let timeOffset = Double(lastDragTranslation.width / timelineState.pixelsPerSecond)
            let scrubbingTime = dragStartTime - timeOffset  // Note: minus sign for natural scrolling
            return handleTimelineBoundaries(scrubbingTime, totalDuration: totalDuration, timelineHeight: timelineHeight)
        }
        return currentTime
    }
    
    // MARK: - Timeline Controls Overlay
    
    @ViewBuilder
    private func timelineControlsOverlay(geometry: GeometryProxy) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                // Zoom controls container
                VStack(spacing: 4) {
                    // Zoom in button
                    Button(action: {
                        performZoomIn(screenWidth: geometry.size.width)
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(timelineState.isAtMaxZoom ? .gray : .white)
                    }
                    .frame(width: 32, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    )
                    .disabled(timelineState.isAtMaxZoom)
                    .scaleEffect(timelineState.isAtMaxZoom ? 0.95 : 1.0)
                    
                    // Zoom level indicator
                    Text("\(Int(timelineState.pixelsPerSecond))x")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 32, height: 12)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(3)
                    
                    // Zoom out button
                    Button(action: {
                        performZoomOut(screenWidth: geometry.size.width)
                    }) {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(timelineState.isAtMinZoom ? .gray : .white)
                    }
                    .frame(width: 32, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    )
                    .disabled(timelineState.isAtMinZoom)
                    .scaleEffect(timelineState.isAtMinZoom ? 0.95 : 1.0)
                }
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                
                Spacer()
            }
            .padding(.trailing, 12)
            .padding(.top, 8)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Calculate content offset to keep current time centered
    private func calculateContentOffset(screenWidth: CGFloat) -> CGFloat {
        return timelineState.calculateOffsetToCenter(
            time: currentTime,
            screenWidth: screenWidth,
            baseOffset: 500
        )
    }
    
    /// Setup initial timeline state
    private func setupTimelineState() {
        timelineState.reset()
        
        // Initialize clips for the video duration
        if totalDuration > 0 {
            timelineState.initializeClipsForVideo(duration: totalDuration)
        }
        
        // 立即設定正確的 contentOffset，讓當前時間對齊 playhead
        DispatchQueue.main.async {
            let screenWidth = UIScreen.main.bounds.width
            let correctOffset = self.timelineState.calculateOffsetToCenter(
                time: self.currentTime,
                screenWidth: screenWidth,
                baseOffset: 500
            )
            self.timelineState.contentOffset = correctOffset
            print("TimelineContainerView: Set initial contentOffset to \(correctOffset) for currentTime \(self.currentTime)")
        }
    }
    
    /// Update timeline position when current time changes during playback
    private func updateTimelineForCurrentTime(_ newTime: TimeInterval) {
        // Only update if not currently dragging and auto-scrolling is enabled
        if !timelineState.isDragging && isAutoScrollingEnabled {
            // Calculate and update content offset to keep playback marker centered
            let screenWidth = UIScreen.main.bounds.width
            let newOffset = timelineState.calculateOffsetToCenter(
                time: newTime,
                screenWidth: screenWidth,
                baseOffset: 500
            )
            
            // Update content offset smoothly for automatic scrolling
            withAnimation(.linear(duration: 0.1)) {
                timelineState.contentOffset = newOffset
            }
        }
    }
    
    /// Handle duration changes (e.g., when new video is loaded)
    private func handleDurationChange(_ newDuration: TimeInterval) {
        timelineState.reset()
        
        // Handle edge case: invalid or zero duration
        if newDuration <= 0 {
            print("Warning: Invalid duration detected: \(newDuration)")
            return
        }
        
        // Handle edge case: extremely long duration
        if newDuration > 86400 { // More than 24 hours
            print("Warning: Extremely long duration detected: \(newDuration) seconds")
        }
        
        // Initialize clips for the new video duration
        timelineState.initializeClipsForVideo(duration: newDuration)
        
        // 立即設定正確的 contentOffset，讓時間 0.0 對齊 playhead
        DispatchQueue.main.async {
            let screenWidth = UIScreen.main.bounds.width
            let correctOffset = self.timelineState.calculateOffsetToCenter(
                time: 0.0, // 確保時間 0.0 對齊
                screenWidth: screenWidth,
                baseOffset: 500
            )
            self.timelineState.contentOffset = correctOffset
            print("TimelineContainerView: Set initial contentOffset to \(correctOffset) for time 0.0")
        }
    }
    
    // MARK: - Performance Monitoring Setup
    
    /// Setup performance monitoring for timeline operations
    private func setupPerformanceMonitoring() {
        performanceMonitor.startMonitoring()
        
        // Setup memory warning observer
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PerformanceMemoryCritical"),
            object: nil,
            queue: .main
        ) { notification in
            // Handle critical memory warning
            print("Critical memory warning received - triggering cleanup")
            
            // Post notification to trigger thumbnail cache cleanup
            NotificationCenter.default.post(
                name: NSNotification.Name("TimelineCacheCleanup"),
                object: nil,
                userInfo: ["reason": "memory_critical"]
            )
        }
    }
    
    /// Cleanup performance monitoring
    private func cleanupPerformanceMonitoring() {
        performanceMonitor.stopMonitoring()
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("PerformanceMemoryCritical"), object: nil)
    }
    
    /// Handle critical memory warnings with automatic cleanup
    private func handleCriticalMemoryWarning(_ notification: Notification) {
        print("Critical memory warning received - triggering cleanup")
        
        // Post notification to trigger thumbnail cache cleanup
        NotificationCenter.default.post(
            name: NSNotification.Name("TimelineCacheCleanup"),
            object: nil,
            userInfo: ["reason": "memory_critical"]
        )
        
        // Clear performance warnings to free memory
        performanceMonitor.clearWarnings()
    }
    
    // MARK: - Enhanced Gesture Handling with Conflict Resolution
    
    /// Create timeline scroll gesture with proper conflict resolution
    /// This ensures timeline scrolling works properly alongside clip selection
    private func createTimelineScrollGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("timeline"))
            .onChanged { value in
                handleDragChanged(value, screenWidth: geometry.size.width, timelineHeight: geometry.size.height)
            }
            .onEnded { value in
                handleDragEnded(value, screenWidth: geometry.size.width, timelineHeight: geometry.size.height)
            }
    }
    
    // MARK: - Enhanced Drag Gesture Handlers
    
    /// Handle drag gesture changes for timeline scrubbing with enhanced state tracking and error handling
    private func handleDragChanged(_ value: DragGesture.Value, screenWidth: CGFloat, timelineHeight: CGFloat = 120) {
        // Record frame for performance monitoring
        performanceMonitor.recordFrame()
        
        // Validate input parameters to prevent crashes
        guard validateDragParameters(value: value, screenWidth: screenWidth, timelineHeight: timelineHeight) else {
            print("TimelineContainerView: Invalid drag parameters, ignoring gesture")
            return
        }
        
        // Initialize drag state on first change
        if !timelineState.isDragging {
            initializeDragState(value)
        }
        
        // Handle edge case: invalid duration
        guard totalDuration > 0 && totalDuration.isFinite else { 
            print("TimelineContainerView: Cannot perform drag with invalid duration: \(totalDuration)")
            return 
        }
        
        // Calculate target time based on drag distance from start with validation
        let totalDragDistance = value.translation.width
        
        // Handle edge case: extreme drag values that could cause overflow
        guard abs(totalDragDistance) < screenWidth * 5 && totalDragDistance.isFinite else {
            print("TimelineContainerView: Extreme drag distance detected: \(totalDragDistance), clamping")
            return
        }
        
        let timeOffset = Double(totalDragDistance / timelineState.pixelsPerSecond)
        
        // Validate time offset is reasonable
        guard timeOffset.isFinite && abs(timeOffset) < totalDuration * 2 else {
            print("TimelineContainerView: Invalid time offset calculated: \(timeOffset)")
            return
        }
        
        let rawTargetTime = dragStartTime - timeOffset  // Note: minus sign for natural scrolling
        let targetTime = handleTimelineBoundaries(rawTargetTime, totalDuration: totalDuration, timelineHeight: timelineHeight)
        
        // Update the content offset to keep the target time centered
        let newOffset = timelineState.calculateOffsetToCenter(
            time: targetTime,
            screenWidth: screenWidth,
            baseOffset: 500
        )
        
        // Validate the new offset is reasonable
        guard newOffset.isFinite && abs(newOffset) < screenWidth * 10 else {
            print("TimelineContainerView: Invalid content offset calculated: \(newOffset)")
            return
        }
        
        // Apply immediate update for responsive scrubbing (no animation during drag)
        timelineState.contentOffset = newOffset
        
        // Perform throttled seeking for smooth performance with error handling
        let now = CACurrentMediaTime()
        if now - timelineState.lastSeekTime > 0.033 { // Limit to 30fps for seeking
            performDebouncedSeekWithErrorHandling(to: targetTime)
            timelineState.updateLastSeekTime(now)
        }
        
        // Update drag tracking state
        lastDragTranslation = value.translation
    }
    
    /// Validate drag gesture parameters to prevent runtime errors
    /// This implements comprehensive parameter validation for edge cases
    private func validateDragParameters(value: DragGesture.Value, screenWidth: CGFloat, timelineHeight: CGFloat) -> Bool {
        // Validate drag value components
        guard value.translation.width.isFinite && value.translation.height.isFinite else {
            print("TimelineContainerView: Invalid drag translation values")
            return false
        }
        
        guard value.location.x.isFinite && value.location.y.isFinite else {
            print("TimelineContainerView: Invalid drag location values")
            return false
        }
        
        // Validate screen dimensions
        guard screenWidth > 0 && screenWidth.isFinite && screenWidth < 10000 else {
            print("TimelineContainerView: Invalid screen width: \(screenWidth)")
            return false
        }
        
        guard timelineHeight > 0 && timelineHeight.isFinite && timelineHeight < 1000 else {
            print("TimelineContainerView: Invalid timeline height: \(timelineHeight)")
            return false
        }
        
        // Validate pixels per second is reasonable
        guard timelineState.pixelsPerSecond > 0 && timelineState.pixelsPerSecond.isFinite else {
            print("TimelineContainerView: Invalid pixels per second: \(timelineState.pixelsPerSecond)")
            return false
        }
        
        return true
    }
    
    /// Enhanced debounced seek with comprehensive error handling
    private func performDebouncedSeekWithErrorHandling(to targetTime: TimeInterval) {
        // Validate target time before seeking
        guard targetTime.isFinite && !targetTime.isNaN else {
            print("TimelineContainerView: Invalid target time for seek: \(targetTime)")
            return
        }
        
        let startTime = CACurrentMediaTime()
        
        // Use enhanced timer-based debouncing with comprehensive error handling
        timelineState.scheduleDebouncedSeek(to: targetTime, player: player) { success, error in
            let duration = CACurrentMediaTime() - startTime
            performanceMonitor.recordSeekOperation(duration: duration, success: success)
            
            if !success {
                handleSeekErrorWithRecovery(error, targetTime: targetTime)
            }
        }
    }
    
    /// Handle seek errors with automatic recovery mechanisms
    private func handleSeekErrorWithRecovery(_ error: Error?, targetTime: TimeInterval) {
        guard let error = error else { return }
        
        // Log error for debugging
        print("TimelineContainerView: Seek error at \(targetTime): \(error.localizedDescription)")
        
        // Check if we have too many consecutive failures
        if timelineState.hasTooManySeekFailures {
            print("TimelineContainerView: Too many seek failures, attempting recovery")
            
            // Attempt recovery by seeking to last known good position
            let recoveryTime = timelineState.lastKnownGoodSeekTime
            
            // Validate recovery time
            guard recoveryTime.isFinite && recoveryTime >= 0 && recoveryTime <= totalDuration else {
                print("TimelineContainerView: Invalid recovery time: \(recoveryTime)")
                return
            }
            
            timelineState.performImmediateSeek(to: recoveryTime, player: player) { success, _ in
                if success {
                    print("TimelineContainerView: Successfully recovered to time \(recoveryTime)")
                    // Reset failure tracking on successful recovery
                    timelineState.resetSeekFailureTracking()
                } else {
                    print("TimelineContainerView: Recovery seek also failed")
                    // Could implement additional recovery strategies here
                }
            }
        }
    }
    
    /// Handle drag gesture end with final state cleanup
    private func handleDragEnded(_ value: DragGesture.Value, screenWidth: CGFloat, timelineHeight: CGFloat = 120) {
        guard timelineState.isDragging else { return }
        
        // Perform final seek to ensure accuracy based on total drag distance
        if totalDuration > 0 {
            let totalDragDistance = value.translation.width
            let timeOffset = Double(totalDragDistance / timelineState.pixelsPerSecond)
            let finalTime = handleTimelineBoundaries(dragStartTime - timeOffset, totalDuration: totalDuration, timelineHeight: timelineHeight)  // Note: minus sign for natural scrolling
            
            // Final seek without debouncing for precision, with error handling
            timelineState.performImmediateSeek(to: finalTime, player: player) { success, error in
                if !success {
                    self.handleSeekError(error)
                }
            }
        }
        
        // Clean up drag state
        finalizeDragState()
    }
    
    // MARK: - Drag State Management
    
    /// Initialize drag state when drag begins
    private func initializeDragState(_ value: DragGesture.Value) {
        timelineState.startDragGesture()
        dragStartTime = currentTime
        dragStartLocation = value.startLocation
        lastDragTranslation = .zero
        
        // Disable automatic scrolling during manual drag
        // This implements task 12 requirement 3: "Disable automatic scrolling when user is actively dragging timeline"
        disableAutomaticScrolling()
        
        // Store initial seek time for debouncing
        timelineState.updateLastSeekTime(CACurrentMediaTime())
    }
    
    /// Finalize drag state when drag ends
    private func finalizeDragState() {
        timelineState.endDragGesture()
        dragStartTime = 0
        dragStartLocation = .zero
        lastDragTranslation = .zero
        
        // Re-enable automatic scrolling after drag ends
        // This implements task 12 requirement 4: "Ensure smooth transitions between manual and automatic scrolling modes"
        enableAutomaticScrolling()
    }
    
    /// Perform debounced seeking to prevent excessive AVPlayer calls
    private func performDebouncedSeek(to targetTime: TimeInterval) {
        let startTime = CACurrentMediaTime()
        
        // Use enhanced timer-based debouncing with error handling
        timelineState.scheduleDebouncedSeek(to: targetTime, player: player) { success, error in
            let duration = CACurrentMediaTime() - startTime
            performanceMonitor.recordSeekOperation(duration: duration, success: success)
            
            if !success {
                handleSeekError(error)
            }
        }
    }
    
    /// Handle seek operation errors with appropriate recovery
    private func handleSeekError(_ error: Error?) {
        guard let error = error else { return }
        
        // Log error for debugging
        print("Timeline seek error: \(error.localizedDescription)")
        
        // Check if we have too many consecutive failures
        if timelineState.hasTooManySeekFailures {
            // Attempt recovery by seeking to last known good position
            let recoveryTime = timelineState.lastKnownGoodSeekTime
            timelineState.performImmediateSeek(to: recoveryTime, player: player) { success, _ in
                if success {
                    // Reset failure tracking on successful recovery
                    timelineState.resetSeekFailureTracking()
                }
            }
        }
    }
    
    /// Update timeline state during drag for visual feedback
    private func updateTimelineStateForDrag(_ targetTime: TimeInterval) {
        // This method can be extended to provide visual feedback during dragging
        // For now, we rely on the AVPlayer seeking to update the currentTime binding
        // which will trigger UI updates through the onChange modifier
    }
    
    /// Handle tap gesture for seek-to-position
    private func handleTapGesture(_ location: CGPoint, screenWidth: CGFloat) {
        guard totalDuration > 0 else { return }
        
        // Calculate time from tap position relative to screen center
        let tapOffsetFromCenter = location.x - screenWidth / 2
        let timeOffset = Double(tapOffsetFromCenter / timelineState.pixelsPerSecond)
        let newTime = max(0, min(totalDuration, currentTime + timeOffset))
        
        // Use immediate seek for tap gestures (no debouncing needed for single taps)
        timelineState.performImmediateSeek(to: newTime, player: player) { success, error in
            if !success {
                handleSeekError(error)
            }
        }
    }
    
    /// Handle double tap gesture for marker menu
    private func handleDoubleTapGesture(_ location: CGPoint) {
    }
    
    // MARK: - Enhanced Zoom Controls
    
    /// Perform zoom in operation while maintaining current time position
    /// This implements task 11 requirement 3: "Maintain current time position during zoom operations"
    private func performZoomIn(screenWidth: CGFloat) {
        guard !timelineState.isAtMaxZoom else { return }
        
        // Store current time position before zoom
        let timeBeforeZoom = currentTime
        
        // Perform zoom with smooth animation
        withAnimation(.easeInOut(duration: 0.4)) {
            timelineState.zoomIn()
        }
        
        // Maintain current time position after zoom
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.maintainTimePositionAfterZoom(timeBeforeZoom, screenWidth: screenWidth)
        }
    }
    
    /// Perform zoom out operation while maintaining current time position
    /// This implements task 11 requirement 3: "Maintain current time position during zoom operations"
    private func performZoomOut(screenWidth: CGFloat) {
        guard !timelineState.isAtMinZoom else { return }
        
        // Store current time position before zoom
        let timeBeforeZoom = currentTime
        
        // Perform zoom with smooth animation
        withAnimation(.easeInOut(duration: 0.4)) {
            timelineState.zoomOut()
        }
        
        // Maintain current time position after zoom
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.maintainTimePositionAfterZoom(timeBeforeZoom, screenWidth: screenWidth)
        }
    }
    
    /// Maintain the time position after zoom operation
    /// This ensures the playback marker stays aligned with the same time position
    private func maintainTimePositionAfterZoom(_ targetTime: TimeInterval, screenWidth: CGFloat) {
        // Calculate new content offset to keep the target time centered
        let newOffset = timelineState.calculateOffsetToCenter(
            time: targetTime,
            screenWidth: screenWidth,
            baseOffset: 500
        )
        
        // Update content offset with animation to maintain smooth transition
        withAnimation(.easeOut(duration: 0.2)) {
            timelineState.contentOffset = newOffset
        }
        
        // Trigger thumbnail density update by notifying the system of zoom change
        // This implements task 11 requirement 4: "Update thumbnail density when zoom level changes"
        NotificationCenter.default.post(
            name: NSNotification.Name("TimelineZoomChanged"),
            object: nil,
            userInfo: [
                "pixelsPerSecond": timelineState.pixelsPerSecond,
                "currentTime": targetTime
            ]
        )
    }
    
    // MARK: - Automatic Timeline Scrolling
    
    /// Setup AVPlayer time observer for automatic timeline updates
    /// This implements task 12 requirement 1: "Add AVPlayer time observer for automatic timeline updates"
    private func setupAutomaticScrolling() {
        // Remove existing observer if any
        cleanupAutomaticScrolling()
        
        // Add periodic time observer with high frequency for smooth scrolling
        let interval = CMTime(seconds: 0.016, preferredTimescale: 600) // ~60fps updates
        
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            handleAutomaticTimeUpdate(time.seconds)
        }
    }
    
    /// Clean up the time observer when view disappears
    private func cleanupAutomaticScrolling() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    /// Handle automatic time updates from AVPlayer
    /// This implements task 12 requirement 2: "Calculate content offset to keep playback marker centered during normal playback"
    /// This implements task 12 requirement 3: "Disable automatic scrolling when user is actively dragging timeline"
    private func handleAutomaticTimeUpdate(_ newTime: TimeInterval) {
        // Only perform automatic scrolling if conditions are met
        guard shouldPerformAutomaticScrolling(for: newTime) else { return }
        
        // Update the content offset to keep the playback marker centered
        // This is handled automatically by the calculateContentOffset method
        // which is called in the TimelineContentView binding
        
        // Store the last auto-scroll time for smooth transitions
        lastAutoScrollTime = newTime
        
        // Trigger a smooth content offset update if needed
        updateContentOffsetForAutoScroll(newTime)
    }
    
    /// Determine if automatic scrolling should be performed
    /// This implements task 12 requirement 3: "Disable automatic scrolling when user is actively dragging timeline"
    private func shouldPerformAutomaticScrolling(for newTime: TimeInterval) -> Bool {
        // Don't auto-scroll if user is actively dragging
        guard !timelineState.isDragging else { return false }
        
        // Don't auto-scroll if user is actively scrubbing
        guard !timelineState.isActivelyScrubbing else { return false }
        
        // Don't auto-scroll if auto-scrolling is disabled
        guard isAutoScrollingEnabled else { return false }
        
        // Don't auto-scroll if the time hasn't changed significantly
        let timeDelta = abs(newTime - lastAutoScrollTime)
        guard timeDelta > 0.01 else { return false } // Minimum 10ms change
        
        // Don't auto-scroll if we're at the boundaries and time isn't progressing
        if newTime <= 0 || newTime >= totalDuration {
            return false
        }
        
        return true
    }
    
    /// Update content offset for automatic scrolling
    /// This implements task 12 requirement 4: "Ensure smooth transitions between manual and automatic scrolling modes"
    private func updateContentOffsetForAutoScroll(_ newTime: TimeInterval) {
        // Calculate the new content offset needed to center the current time
        let screenWidth = UIScreen.main.bounds.width // Fallback screen width
        let newOffset = timelineState.calculateOffsetToCenter(
            time: newTime,
            screenWidth: screenWidth,
            baseOffset: 500
        )
        
        // Only update if the offset has changed significantly
        let offsetDelta = abs(newOffset - timelineState.contentOffset)
        guard offsetDelta > 1.0 else { return } // Minimum 1 pixel change
        
        // Apply smooth animation for automatic scrolling
        withAnimation(.linear(duration: 0.016)) { // Match the observer interval
            timelineState.contentOffset = newOffset
        }
    }
    
    /// Enable automatic scrolling (called when drag ends)
    /// This implements task 12 requirement 4: "Ensure smooth transitions between manual and automatic scrolling modes"
    private func enableAutomaticScrolling() {
        isAutoScrollingEnabled = true
        
        // Perform an immediate smooth transition to the current time position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.performSmoothTransitionToCurrentTime()
        }
    }
    
    /// Disable automatic scrolling (called when drag starts)
    private func disableAutomaticScrolling() {
        isAutoScrollingEnabled = false
    }
    
    /// Perform smooth transition from manual to automatic scrolling
    private func performSmoothTransitionToCurrentTime() {
        let screenWidth = UIScreen.main.bounds.width
        let targetOffset = timelineState.calculateOffsetToCenter(
            time: currentTime,
            screenWidth: screenWidth,
            baseOffset: 500
        )
        
        // Use a slightly longer animation for the transition
        withAnimation(.easeOut(duration: 0.3)) {
            timelineState.contentOffset = targetOffset
        }
    }
    
    // MARK: - Edge Case Handling
    
    /// Handle timeline boundary conditions with thumbnail-aligned boundaries
    /// This implements task 15 requirement 3: "Handle edge cases like timeline start/end boundaries"
    /// Enhanced to align boundaries with thumbnail width for better visual alignment
    private func handleTimelineBoundaries(_ targetTime: TimeInterval, totalDuration: TimeInterval, timelineHeight: CGFloat = 120) -> TimeInterval {
        // Calculate thumbnail-based boundary offsets
        let thumbnailBoundaryOffset = calculateThumbnailBoundaryOffset(timelineHeight: timelineHeight)
        
        // Handle negative time (before start) with thumbnail alignment
        if targetTime < -thumbnailBoundaryOffset {
            // Allow thumbnail-width overshoot for smooth boundary handling
            if targetTime > -thumbnailBoundaryOffset - 0.1 {
                return -thumbnailBoundaryOffset
            } else {
                print("Warning: Extreme negative time detected: \(targetTime), clamping to thumbnail boundary: \(-thumbnailBoundaryOffset)")
                return -thumbnailBoundaryOffset
            }
        }
        
        // Handle time beyond duration (after end) with thumbnail alignment
        let maxAllowedTime = totalDuration + thumbnailBoundaryOffset
        if targetTime > maxAllowedTime {
            // Allow slight overshoot for smooth boundary handling
            if targetTime < maxAllowedTime + 0.1 {
                return maxAllowedTime
            } else {
                print("Warning: Time beyond duration detected: \(targetTime) > \(maxAllowedTime), clamping to thumbnail boundary")
                return maxAllowedTime
            }
        }
        
        // Handle NaN or infinite values
        if !targetTime.isFinite {
            print("Warning: Invalid time value detected: \(targetTime), using current time")
            return currentTime
        }
        
        return targetTime
    }
    
    /// Calculate boundary offset based on thumbnail width for better alignment
    /// This ensures the playhead boundaries align with thumbnail edges for smoother visual experience
    /// - Parameter timelineHeight: The actual height of the timeline container
    private func calculateThumbnailBoundaryOffset(timelineHeight: CGFloat = 120) -> TimeInterval {
        // Calculate thumbnail dimensions based on timeline height and aspect ratio
        // This matches the approach used in VideoThumbnailTrackView
        
        // Calculate thumbnail height (half of timeline height, matching VideoThumbnailTrackView)
        let thumbnailHeight = timelineHeight / 2
        
        // Get aspect ratio from thumbnail provider (with 16:9 fallback)
        let thumbnailSize = thumbnailProvider.thumbnailSize
        let aspectRatio: CGFloat = (thumbnailSize.width > 0 && thumbnailSize.height > 0) 
            ? thumbnailSize.width / thumbnailSize.height 
            : 16.0 / 9.0
        
        // Calculate thumbnail width based on height and aspect ratio
        let thumbnailWidth = thumbnailHeight * aspectRatio
        
        // Convert thumbnail width to time duration based on current zoom level
        let thumbnailTimeWidth = Double(thumbnailWidth / timelineState.pixelsPerSecond)
        
        // Use half thumbnail width as boundary offset for centered alignment
        // This allows the playhead to extend half a thumbnail width beyond the video boundaries
        let boundaryOffset = thumbnailTimeWidth / 2
        
        // Ensure minimum boundary offset for smooth interaction
        let minBoundaryOffset = 0.1 // 100ms minimum
        let maxBoundaryOffset = 2.0 // 2 seconds maximum to prevent excessive overshoot
        
        let clampedOffset = max(minBoundaryOffset, min(maxBoundaryOffset, boundaryOffset))
        
        print("ThumbnailBoundary: timelineHeight=\(timelineHeight), thumbnailHeight=\(thumbnailHeight), aspectRatio=\(aspectRatio), thumbnailWidth=\(thumbnailWidth), pixelsPerSecond=\(timelineState.pixelsPerSecond), boundaryOffset=\(clampedOffset)s")
        
        return clampedOffset
    }
    
    // Duplicate handleSeekError method removed - using the one defined earlier
    
    // MARK: - Performance Monitoring Overlay
    
    /// Performance monitoring overlay for debug mode
    /// This implements task 15 requirement 1: "Implement frame rate monitoring to ensure 60fps performance during scrubbing"
    @ViewBuilder
    private func performanceOverlay(geometry: GeometryProxy) -> some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Frame rate display
                    HStack {
                        Circle()
                            .fill(performanceMonitor.currentFrameRate >= 30 ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text("FPS: \(String(format: "%.1f", performanceMonitor.currentFrameRate))")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    
                    // Memory usage display
                    HStack {
                        Circle()
                            .fill(performanceMonitor.memoryUsageMB < 100 ? Color.green : 
                                  performanceMonitor.memoryUsageMB < 200 ? Color.orange : Color.red)
                            .frame(width: 8, height: 8)
                        Text("MEM: \(String(format: "%.1f", performanceMonitor.memoryUsageMB))MB")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    
                    // Warning count
                    if !performanceMonitor.performanceWarnings.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 8))
                            Text("Warnings: \(performanceMonitor.performanceWarnings.count)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.top, 8)
            
            Spacer()
        }
    }
}

// MARK: - Preview

struct TimelineContainerView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineContainerView(
            player: .constant(AVPlayer()),
            currentTime: .constant(30.0),
            totalDuration: .constant(120.0),
            thumbnailProvider: ThumbnailProvider()
        )
        .frame(height: 120)
        .background(Color.black)
    }
}
