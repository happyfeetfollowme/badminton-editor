import SwiftUI
import AVFoundation
import AVKit

/// Video thumbnail track view that displays video frame previews along the timeline
/// This view handles thumbnail generation, caching, and display with proper aspect ratio handling
struct VideoThumbnailTrackView: View {
    // MARK: - Properties
    
    /// AVPlayer instance for thumbnail generation
    let player: AVPlayer
    
    /// Total duration of the video content
    let totalDuration: TimeInterval
    
    /// Current zoom level (pixels per second)
    let pixelsPerSecond: CGFloat
    
    /// Current content offset for visible area calculation
    let contentOffset: CGFloat
    
    /// Screen width for visible area calculation
    let screenWidth: CGFloat
    
    /// Base offset for timeline alignment
    private let baseOffset: CGFloat = 500
    
    /// Boundary padding for smooth scrolling
    private let boundaryPadding: CGFloat = 1000
    
    /// Standard thumbnail height
    private let thumbnailHeight: CGFloat = 60
    
    /// Standard thumbnail aspect ratio (16:9)
    private let thumbnailAspectRatio: CGFloat = 16.0 / 9.0
    
    /// Minimum thumbnail width to maintain readability
    private let minThumbnailWidth: CGFloat = 40
    
    /// Maximum thumbnail width to prevent oversized thumbnails
    private let maxThumbnailWidth: CGFloat = 200
    
    /// Buffer zone for preloading thumbnails outside visible area
    private let preloadBuffer: CGFloat = 200
    
    // MARK: - State
    
    /// Enhanced thumbnail cache for efficient thumbnail management
    @StateObject private var thumbnailCache = ThumbnailCache()
    
    /// Times at which thumbnails should be generated
    @State private var thumbnailTimes: [TimeInterval] = []
    
    /// Currently visible thumbnail times (for optimization)
    @State private var visibleThumbnailTimes: Set<TimeInterval> = []
    
    /// Last visible time range to prevent unnecessary recalculations
    @State private var lastVisibleRange: (start: TimeInterval, end: TimeInterval) = (0, 0)
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 0) {
            // Base offset padding
            Rectangle()
                .fill(Color.clear)
                .frame(width: baseOffset)
            
            // Thumbnail track content
            thumbnailTrackContent
            
            // Boundary padding
            Rectangle()
                .fill(Color.clear)
                .frame(width: boundaryPadding)
        }
        .onAppear {
            print("VideoThumbnailTrackView onAppear:")
            print("- player.currentItem exists: \(player.currentItem != nil)")
            print("- totalDuration: \(totalDuration)")
            print("- pixelsPerSecond: \(pixelsPerSecond)")
            
            setupThumbnailCache()
            updateThumbnailConfiguration()
            setupZoomChangeObserver()
            
            // 如果已經有影片，立即生成縮圖
            if player.currentItem != nil {
                print("VideoThumbnailTrackView: onAppear - generating thumbnails")
                if totalDuration > 0 && pixelsPerSecond > 0 {
                    generateInitialThumbnails()
                } else {
                    // 如果條件不滿足，使用強制生成
                    forceGenerateInitialThumbnails()
                }
            }
            
            // 調試：檢查對齊設定
            print("VideoThumbnailTrackView onAppear alignment check:")
            print("- baseOffset: \(baseOffset)")
            print("- contentOffset: \(contentOffset)")
            print("- screenWidth: \(screenWidth)")
            
            // 計算時間 0.0 應該出現的螢幕位置
            let time0Position = baseOffset + contentOffset
            let screenCenter = screenWidth / 2
            print("- Time 0.0 position: \(time0Position)")
            print("- Screen center: \(screenCenter)")
            print("- Offset from center: \(time0Position - screenCenter)")
        }
        .onDisappear {
            removeZoomChangeObserver()
        }
        .onChange(of: pixelsPerSecond) { _, newPixelsPerSecond in
            print("VideoThumbnailTrackView: pixelsPerSecond changed to \(newPixelsPerSecond)")
            updateThumbnailConfiguration()
            // 縮放改變後立即更新可見縮圖
            if !thumbnailTimes.isEmpty {
                updateVisibleThumbnails()
            } else if totalDuration > 0 && newPixelsPerSecond > 0 {
                // 如果還沒有 thumbnailTimes，但現在條件滿足了，立即生成
                forceGenerateInitialThumbnails()
            }
        }
        .onChange(of: totalDuration) { _, newDuration in
            print("VideoThumbnailTrackView: totalDuration changed to \(newDuration)")
            updateThumbnailConfiguration()
            // 時長改變後立即生成初始縮圖
            if newDuration > 0 {
                if pixelsPerSecond > 0 {
                    generateInitialThumbnails()
                } else {
                    // 如果 pixelsPerSecond 還沒設定，使用強制生成
                    forceGenerateInitialThumbnails()
                }
            }
        }
        .onChange(of: player.currentItem) { _, _ in
            print("VideoThumbnailTrackView: player.currentItem changed")
            setupThumbnailCache()
            
            // 延遲一點時間確保 totalDuration 已經被設定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                print("VideoThumbnailTrackView: Starting thumbnail generation after item change")
                print("- totalDuration: \(self.totalDuration)")
                print("- pixelsPerSecond: \(self.pixelsPerSecond)")
                
                // 更新縮圖配置並立即生成
                self.updateThumbnailConfiguration()
                
                // 強制生成初始縮圖，即使其他條件不滿足
                self.forceGenerateInitialThumbnails()
                
                // 檢查對齊狀況
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    print("VideoThumbnailTrackView post-load alignment check:")
                    print("- baseOffset: \(self.baseOffset)")
                    print("- contentOffset: \(self.contentOffset)")
                    print("- screenWidth: \(self.screenWidth)")
                    
                    let time0Position = self.baseOffset + self.contentOffset
                    let screenCenter = self.screenWidth / 2
                    print("- Time 0.0 position: \(time0Position)")
                    print("- Screen center: \(screenCenter)")
                    print("- Alignment error: \(time0Position - screenCenter)")
                    
                    if abs(time0Position - screenCenter) > 1.0 {
                        print("WARNING: Time 0.0 is not aligned with playhead!")
                    }
                }
            }
        }
        .onChange(of: contentOffset) { _, _ in
            updateVisibleThumbnails()
        }
        .onChange(of: screenWidth) { _, _ in
            updateVisibleThumbnails()
        }
    }
    
    // MARK: - Thumbnail Track Content
    
    @ViewBuilder
    private var thumbnailTrackContent: some View {
        HStack(spacing: 0) {
            ForEach(Array(thumbnailTimes.enumerated()), id: \.offset) { index, time in
                thumbnailCell(for: time, at: index)
            }
        }
    }
    
    // MARK: - Thumbnail Cell
    
    /// Create a thumbnail cell for a specific time position
    /// - Parameters:
    ///   - time: The time position for this thumbnail
    ///   - index: The index of this thumbnail in the sequence
    /// - Returns: A view representing the thumbnail or placeholder
    @ViewBuilder
    private func thumbnailCell(for time: TimeInterval, at index: Int) -> some View {
        let cellWidth = calculateThumbnailWidth(for: time, at: index)
        
        if let thumbnail = getThumbnail(for: time) {
            // Display actual thumbnail
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: cellWidth, height: thumbnailHeight)
                .clipped()
                .overlay(
                    // Subtle border for definition
                    Rectangle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        } else {
            // Display placeholder while thumbnail loads
            thumbnailPlaceholder(width: cellWidth)
                .onAppear {
                    generateThumbnail(for: time)
                }
        }
    }
    
    // MARK: - Thumbnail Placeholder
    
    /// Create a placeholder rectangle for thumbnails not yet loaded
    /// - Parameter width: The width of the placeholder
    /// - Returns: A placeholder view with loading indicator
    @ViewBuilder
    private func thumbnailPlaceholder(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.3))
            .frame(width: width, height: thumbnailHeight)
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .overlay(
                // Loading indicator
                VStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 14))
                    
                    // Subtle loading animation
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: width * 0.6, height: 2)
                        .cornerRadius(1)
                        .overlay(
                            Rectangle()
                                .fill(Color.white.opacity(0.6))
                                .frame(width: width * 0.2, height: 2)
                                .cornerRadius(1)
                                .animation(
                                    Animation.easeInOut(duration: 1.5)
                                        .repeatForever(autoreverses: true),
                                    value: thumbnailCache.thumbnails.count
                                )
                        )
                }
            )
    }
    
    // MARK: - Thumbnail Width Calculation
    
    /// Calculate the appropriate width for a thumbnail at a specific position
    /// - Parameters:
    ///   - time: The time position of the thumbnail
    ///   - index: The index of the thumbnail in the sequence
    /// - Returns: The calculated width for the thumbnail
    private func calculateThumbnailWidth(for time: TimeInterval, at index: Int) -> CGFloat {
        // Calculate the duration this thumbnail should represent
        let nextTime = (index + 1 < thumbnailTimes.count) ? thumbnailTimes[index + 1] : totalDuration
        let durationSegment = nextTime - time
        
        // Convert duration to pixels based on current zoom level
        let calculatedWidth = CGFloat(durationSegment) * pixelsPerSecond
        
        // Clamp to reasonable bounds
        let clampedWidth = max(minThumbnailWidth, min(maxThumbnailWidth, calculatedWidth))
        
        return clampedWidth
    }
    
    // MARK: - Thumbnail Configuration
    
    /// Update thumbnail times and trigger regeneration based on current zoom and duration
    private func updateThumbnailConfiguration() {
        guard totalDuration > 0, pixelsPerSecond > 0 else {
            thumbnailTimes = []
            return
        }
        
        // Calculate optimal thumbnail interval based on zoom level
        let optimalThumbnailWidth = calculateOptimalThumbnailWidth()
        let timePerThumbnail = optimalThumbnailWidth / pixelsPerSecond
        
        // Ensure minimum interval to prevent too many thumbnails
        let minInterval: TimeInterval = 0.5 // Minimum 0.5 seconds between thumbnails
        let actualInterval = max(minInterval, timePerThumbnail)
        
        // Generate thumbnail times starting from exactly 0.0 to align with playhead
        var newThumbnailTimes: [TimeInterval] = []
        var currentTime: TimeInterval = 0.0
        
        while currentTime < totalDuration {
            newThumbnailTimes.append(currentTime)
            currentTime += actualInterval
        }
        
        // 確保第一個縮圖始終從 0.0 開始，與 playhead 對齊
        if newThumbnailTimes.first != 0.0 {
            newThumbnailTimes.insert(0.0, at: 0)
        }
        
        // Update thumbnail times
        thumbnailTimes = newThumbnailTimes
    }
    
    /// Calculate optimal thumbnail width based on current zoom level
    /// - Returns: The optimal thumbnail width in pixels
    private func calculateOptimalThumbnailWidth() -> CGFloat {
        // Adjust thumbnail density based on zoom level
        switch pixelsPerSecond {
        case 0..<25:
            return 60  // Fewer, wider thumbnails at low zoom
        case 25..<50:
            return 80  // Standard thumbnail width
        case 50..<100:
            return 100 // More detailed thumbnails at medium zoom
        case 100..<150:
            return 120 // High detail at high zoom
        default:
            return 150 // Maximum detail at highest zoom
        }
    }
    
    // MARK: - Visible Area Calculation
    
    /// Update which thumbnails are currently visible and should be prioritized for generation
    private func updateVisibleThumbnails() {
        guard !thumbnailTimes.isEmpty else { return }
        
        let visibleRange = calculateVisibleTimeRange()
        let newVisibleTimes = Set(thumbnailTimes.filter { time in
            time >= visibleRange.start && time <= visibleRange.end
        })
        
        // Only update if the visible set has changed significantly
        if newVisibleTimes != visibleThumbnailTimes {
            visibleThumbnailTimes = newVisibleTimes
            
            // Generate visible thumbnails with priority
            generateVisibleThumbnails()
        }
    }
    
    /// Calculate the time range currently visible on screen (with preload buffer)
    /// - Returns: A tuple containing start and end times for the visible range
    private func calculateVisibleTimeRange() -> (start: TimeInterval, end: TimeInterval) {
        // Calculate the visible pixel range with buffer
        let visibleStartPixel = -contentOffset - preloadBuffer
        let visibleEndPixel = -contentOffset + screenWidth + preloadBuffer
        
        // Convert pixels to time, accounting for base offset
        let startTime = max(0, pixelToTime(visibleStartPixel))
        let endTime = min(totalDuration, pixelToTime(visibleEndPixel))
        
        return (start: startTime, end: endTime)
    }
    
    /// Convert pixel position to time, accounting for base offset
    /// - Parameter pixel: Pixel position
    /// - Returns: Time in seconds
    private func pixelToTime(_ pixel: CGFloat) -> TimeInterval {
        return TimeInterval((pixel - baseOffset) / pixelsPerSecond)
    }
    
    /// Generate thumbnails for currently visible area with priority
    /// This implements the core logic for task 10 - calculating needed thumbnails and generating them
    private func generateVisibleThumbnails() {
        let visibleRange = calculateVisibleTimeRange()
        
        // Use enhanced ThumbnailCache to calculate and generate needed thumbnails
        thumbnailCache.generateThumbnailsForVisibleRange(
            visibleStartTime: visibleRange.start,
            visibleEndTime: visibleRange.end,
            totalDuration: totalDuration,
            pixelsPerSecond: pixelsPerSecond,
            priority: .high
        )
        
        // Store the last visible range to prevent unnecessary recalculations
        lastVisibleRange = visibleRange
    }
    
    // MARK: - Enhanced Thumbnail Generation
    
    /// Setup thumbnail cache with current asset
    private func setupThumbnailCache() {
        guard let currentItem = player.currentItem else {
            print("VideoThumbnailTrackView: No current item in player")
            return
        }
        
        let asset = currentItem.asset
        print("VideoThumbnailTrackView: Setting up cache with asset duration: \(asset.duration.seconds)")
        Task { await thumbnailCache.setAsset(asset) }
    }
    
    /// Generate initial thumbnails immediately after video is loaded
    /// This ensures thumbnails appear quickly, especially at the beginning
    private func generateInitialThumbnails() {
        guard totalDuration > 0, pixelsPerSecond > 0, !thumbnailTimes.isEmpty else {
            print("VideoThumbnailTrackView: Cannot generate initial thumbnails - invalid configuration")
            return
        }
        
        print("VideoThumbnailTrackView: thumbnailTimes = \(Array(thumbnailTimes.prefix(10)))")
        
        // 確保第一個縮圖一定是 0.0 (與 playhead 對齊)
        var priorityTimes: [TimeInterval] = []
        
        // 強制添加 0.0，無論是否在 thumbnailTimes 中
        priorityTimes.append(0.0)
        
        // 添加開頭的幾個縮圖
        let initialThumbnailCount = min(5, thumbnailTimes.count)
        let initialTimes = Array(thumbnailTimes.prefix(initialThumbnailCount))
        priorityTimes.append(contentsOf: initialTimes)
        
        // 移除重複並排序
        priorityTimes = Array(Set(priorityTimes)).sorted()
        
        print("VideoThumbnailTrackView: Generating initial thumbnails for times: \(priorityTimes)")
        print("VideoThumbnailTrackView: First thumbnail time should be 0.0: \(priorityTimes.first == 0.0)")
        
        // 優先生成 0.0 時間的縮圖，確保與 playhead 對齊
        for time in priorityTimes {
            thumbnailCache.generateSingleThumbnail(for: time) { image in
                if let _ = image {
                    print("VideoThumbnailTrackView: Successfully generated initial thumbnail for time: \(time)")
                } else {
                    print("VideoThumbnailTrackView: Failed to generate initial thumbnail for time: \(time)")
                }
            }
        }
        
        // 同時生成可見區域的縮圖
        updateVisibleThumbnails()
    }
    
    /// Force generate initial thumbnails even if conditions are not perfect
    /// This is called when video is first loaded to ensure immediate thumbnail display
    private func forceGenerateInitialThumbnails() {
        guard let currentItem = player.currentItem else {
            print("VideoThumbnailTrackView: No current item, cannot generate thumbnails")
            return
        }
        
        let asset = currentItem.asset
        let videoDuration = asset.duration.seconds
        
        print("VideoThumbnailTrackView: Force generating initial thumbnails")
        print("- Asset duration: \(videoDuration)")
        print("- totalDuration parameter: \(totalDuration)")
        print("- pixelsPerSecond: \(pixelsPerSecond)")
        
        // 如果 totalDuration 還沒設定，使用 asset.duration
        let actualDuration = totalDuration > 0 ? totalDuration : videoDuration
        let actualPixelsPerSecond = pixelsPerSecond > 0 ? pixelsPerSecond : 50.0 // 預設值
        
        // 生成基本的縮圖時間點
        var forceThumbnailTimes: [TimeInterval] = [0.0] // 一定要有 0.0
        
        if actualDuration > 0 {
            // 生成每 2 秒一個縮圖用於初始顯示
            let interval: TimeInterval = 2.0
            var time: TimeInterval = interval
            while time < actualDuration && forceThumbnailTimes.count < 10 {
                forceThumbnailTimes.append(time)
                time += interval
            }
        }
        
        print("VideoThumbnailTrackView: Force generating thumbnails for times: \(forceThumbnailTimes)")
        
        // 立即生成這些縮圖
        for time in forceThumbnailTimes {
            print("VideoThumbnailTrackView: Requesting forced thumbnail for time: \(time)")
            thumbnailCache.generateSingleThumbnail(for: time) { image in
                if let _ = image {
                    print("VideoThumbnailTrackView: Successfully generated forced thumbnail for time: \(time)")
                    
                    // 強制 UI 更新
                    DispatchQueue.main.async {
                        // 這會觸發 View 重新繪製
                    }
                } else {
                    print("VideoThumbnailTrackView: Failed to generate forced thumbnail for time: \(time)")
                }
            }
        }
    }
    

    
    /// Generate a fallback thumbnail with time-specific information
    /// - Parameter time: The time this thumbnail represents
    /// - Returns: A fallback thumbnail image
    private func generateFallbackThumbnail(for time: TimeInterval) -> UIImage {
        let size = CGSize(width: 320, height: 180) // 16:9 aspect ratio, 2x resolution
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        // Create gradient background
        let context = UIGraphicsGetCurrentContext()
        let colors = [UIColor.darkGray.cgColor, UIColor.black.cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)
        
        context?.drawLinearGradient(
            gradient!,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size.width, y: size.height),
            options: []
        )
        
        // Add error indicator and time
        let iconSize: CGFloat = 20
        let iconRect = CGRect(
            x: (size.width - iconSize) / 2,
            y: (size.height - iconSize) / 2 - 10,
            width: iconSize,
            height: iconSize
        )
        
        // Draw error icon
        UIColor.red.withAlphaComponent(0.6).setFill()
        context?.fillEllipse(in: iconRect)
        
        // Add time text
        let timeText = formatTime(time)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white.withAlphaComponent(0.8),
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        
        let textSize = timeText.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: size.height - textSize.height - 5,
            width: textSize.width,
            height: textSize.height
        )
        
        timeText.draw(in: textRect, withAttributes: attributes)
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
    
    /// Format time for display in fallback thumbnails
    /// - Parameter time: Time in seconds
    /// - Returns: Formatted time string
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Thumbnail Generation (Legacy Support)
    
    /// Get thumbnail for a specific time, checking enhanced cache first
    /// - Parameter time: The time to get thumbnail for
    /// - Returns: UIImage if available, nil otherwise
    private func getThumbnail(for time: TimeInterval) -> UIImage? {
        // 首先檢查 published thumbnails (即時更新)
        if let publishedThumbnail = thumbnailCache.thumbnails[time] {
            return publishedThumbnail
        }
        
        // 然後檢查快取
        let cachedThumbnail = thumbnailCache.getThumbnail(for: time)
        if cachedThumbnail != nil {
            print("VideoThumbnailTrackView: Found cached thumbnail for time: \(time)")
        } else {
            print("VideoThumbnailTrackView: No thumbnail found for time: \(time)")
        }
        return cachedThumbnail
    }
    
    /// Generate thumbnail for a specific time using the enhanced cache system
    /// - Parameter time: The time to generate thumbnail for
    private func generateThumbnail(for time: TimeInterval) {
        print("VideoThumbnailTrackView: Requesting thumbnail for time: \(time)")
        
        // Use the enhanced thumbnail cache to generate single thumbnail
        thumbnailCache.generateSingleThumbnail(for: time) { image in
            // The thumbnail cache handles all the generation logic and caching
            // This completion handler is called when generation is complete
            if let image = image {
                print("VideoThumbnailTrackView: Successfully generated thumbnail for time: \(time)")
                // Thumbnail was successfully generated and cached
                // The UI will automatically update through the @StateObject binding
            } else {
                print("VideoThumbnailTrackView: Failed to generate thumbnail for time: \(time)")
            }
        }
    }
    
    /// Generate a fallback thumbnail when video frame extraction fails
    /// - Returns: A default thumbnail image
    private func generateFallbackThumbnail() -> UIImage {
        let size = CGSize(width: 320, height: 180) // 16:9 aspect ratio, 2x resolution
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        // Create gradient background
        let context = UIGraphicsGetCurrentContext()
        let colors = [UIColor.darkGray.cgColor, UIColor.black.cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)
        
        context?.drawLinearGradient(
            gradient!,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size.width, y: size.height),
            options: []
        )
        
        // Add video icon
        let iconSize: CGFloat = 24
        let iconRect = CGRect(
            x: (size.width - iconSize) / 2,
            y: (size.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        
        UIColor.white.withAlphaComponent(0.5).setFill()
        context?.fillEllipse(in: iconRect)
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
    
    // MARK: - Zoom Change Observer
    
    /// Setup observer for zoom change notifications
    /// This implements task 11 requirement 4: "Update thumbnail density when zoom level changes"
    private func setupZoomChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TimelineZoomChanged"),
            object: nil,
            queue: .main
        ) { notification in
            handleZoomChange(notification)
        }
    }
    
    /// Remove zoom change observer
    private func removeZoomChangeObserver() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("TimelineZoomChanged"),
            object: nil
        )
    }
    
    /// Handle zoom change notification and update thumbnail density
    /// This ensures thumbnails are regenerated with appropriate density for the new zoom level
    private func handleZoomChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let newPixelsPerSecond = userInfo["pixelsPerSecond"] as? CGFloat else {
            return
        }
        
        // Clear existing thumbnails to force regeneration with new density
        thumbnailCache.clearCache()
        
        // Update thumbnail configuration for new zoom level
        updateThumbnailConfiguration()
        
        // Regenerate visible thumbnails with new density
        let visibleRange = calculateVisibleTimeRange()
        thumbnailCache.generateThumbnailsForVisibleRange(
            visibleStartTime: visibleRange.start,
            visibleEndTime: visibleRange.end,
            totalDuration: totalDuration,
            pixelsPerSecond: newPixelsPerSecond,
            priority: .high
        )
    }
    
    // MARK: - Cache Management
    
    /// Get current cache memory usage (for debugging/monitoring)
    var cacheMemoryUsage: String {
        return thumbnailCache.cacheInfo.memoryUsage
    }
}

// MARK: - Preview

struct VideoThumbnailTrackView_Previews: PreviewProvider {
    static var previews: some View {
        VideoThumbnailTrackView(
            player: AVPlayer(),
            totalDuration: 120.0,
            pixelsPerSecond: 50.0,
            contentOffset: 0,
            screenWidth: 400
        )
        .frame(height: 60)
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}