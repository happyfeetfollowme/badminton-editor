import SwiftUI
import AVFoundation
import AVKit

/// Video thumbnail track view that displays video frame previews along the timeline
/// This view handles thumbnail generation, caching, and display with proper aspect ratio handling
struct VideoThumbnailTrackView: View {
    // MARK: - Properties (all stored and computed properties first)
    @ObservedObject var thumbnailProvider: ThumbnailProvider

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

    /// Helper: Sorted thumbnail times for consistent layout
    private var sortedThumbnailTimes: [TimeInterval] {
        thumbnailProvider.thumbnails.keys.sorted()
    }

    /// Get the actual thumbnail size from the provider, scaled appropriately for timeline display
    private func actualThumbnailSize(for timelineHeight: CGFloat) -> CGSize {
        // Make the thumbnail size one fourth of the timeline height, always square
        let squareSize = timelineHeight / 4.0
        return CGSize(width: squareSize, height: squareSize)
    }
    
    /// Helper to determine if we're on a compact screen (iPhone/small iPad)
    private func isCompactScreen(width: CGFloat) -> Bool {
        return width < 700
    }

    // MARK: - Body (after all properties)
    var body: some View {
        GeometryReader { geometry in
            let timelineHeight = geometry.size.height
            let thumbnailSize = actualThumbnailSize(for: timelineHeight)
            // Debug logging
            let _ = print("VideoThumbnailTrackView: Using actual thumbnail size: \(thumbnailSize), provider size: \(thumbnailProvider.thumbnailSize)")
            ZStack(alignment: .leading) {
                if thumbnailProvider.isGenerating {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Generating Thumbnails...")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if thumbnailProvider.thumbnails.isEmpty {
                    VStack {
                        Image(systemName: "video.slash")
                            .foregroundColor(.gray)
                            .font(.title2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Generate thumbnails based on zoom level and duration
                    // For no padding, set interval so that thumbnails are edge-to-edge
                    let thumbnailInterval = thumbnailSize.width / pixelsPerSecond
                    let thumbnailTimes = generateThumbnailTimes(interval: thumbnailInterval)
                    let spacingBetweenThumbnails = thumbnailSize.width // No padding, edge-to-edge
                    let _ = print("Thumbnail spacing: interval=\(thumbnailInterval)s, pixelsPerSecond=\(pixelsPerSecond), spacing=\(spacingBetweenThumbnails)pts, thumbnailWidth=\(thumbnailSize.width)pts")

                    // Space for timestamp above thumbnails
                    let timestampHeight: CGFloat = 16
                    let verticalSpacing: CGFloat = 4
                    ZStack(alignment: .leading) {
                        // Base offset space (now taller to fit timestamp + spacing + thumbnail)
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: calculateContentWidth(thumbnailWidth: thumbnailSize.width), height: timestampHeight + verticalSpacing + thumbnailSize.height)

                        // Position timestamp and thumbnail for each time
                        ForEach(thumbnailTimes, id: \.self) { time in
                            VStack(alignment: .leading, spacing: verticalSpacing) {
                                // Timestamp marker aligned to the beginning of the second
                                Text(formatTime(time))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(width: thumbnailSize.width, height: timestampHeight, alignment: .leading)

                                // Thumbnail
                                thumbnailSlot(for: time, size: thumbnailSize)
                            }
                            .position(
                                x: baseOffset + CGFloat(time) * pixelsPerSecond,
                                y: timestampHeight / 2 + verticalSpacing + thumbnailSize.height / 2
                            )
                        }
                    }
                    .frame(width: calculateContentWidth(thumbnailWidth: thumbnailSize.width), height: timestampHeight + verticalSpacing + thumbnailSize.height)
                }
            }
        }
    }
    
    // MARK: - Thumbnail Slot Generation
    
    /// Create a thumbnail slot for a specific time position using the actual thumbnail size
    /// - Parameters:
    ///   - time: The time in seconds for this thumbnail slot
    ///   - size: The actual size to display the thumbnail (from ThumbnailProvider)
    /// - Returns: A view representing the thumbnail or empty space
    @ViewBuilder
    private func thumbnailSlot(for time: TimeInterval, size: CGSize) -> some View {
        if let thumbnail = findClosestThumbnail(for: time) {
            let _ = print("Timeline thumbnail display size: \(size) for time: \(time)")
            Image(uiImage: thumbnail)
                .resizable()
                .frame(width: size.width, height: size.height) // Use exact size, no aspect ratio override
                .cornerRadius(2)
        } else {
            // Empty slot with loading indicator or placeholder
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size.width, height: size.height)
                .cornerRadius(2)
                .overlay(
                    Text(formatTime(time))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                )
        }
    }
    
    /// Find the closest available thumbnail for a given time
    /// - Parameter targetTime: The time to find a thumbnail for
    /// - Returns: The closest thumbnail image, if available
    private func findClosestThumbnail(for targetTime: TimeInterval) -> UIImage? {
        let tolerance = 0.5 // Accept thumbnails within 0.5 seconds
        
        return sortedThumbnailTimes
            .compactMap { time in
                abs(time - targetTime) <= tolerance ? (time, thumbnailProvider.thumbnails[time]) : nil
            }
            .min { abs($0.0 - targetTime) < abs($1.0 - targetTime) }?
            .1
    }
    
    /// Calculate visible time range based on current content offset and screen width
    /// - Parameter geometry: GeometryProxy for screen dimensions
    /// - Returns: Range of visible times
    private func calculateVisibleTimeRange(geometry: GeometryProxy) -> ClosedRange<TimeInterval> {
        let screenWidth = geometry.size.width
        let leftEdgeTime = max(0, Double((-contentOffset - baseOffset) / pixelsPerSecond))
        let rightEdgeTime = min(totalDuration, Double((screenWidth - contentOffset - baseOffset) / pixelsPerSecond))
        return leftEdgeTime...rightEdgeTime
    }
    
    /// Calculate appropriate thumbnail interval based on zoom level
    /// - Parameter thumbnailWidth: The width of the thumbnail
    /// - Returns: Time interval between thumbnails
    private func calculateThumbnailInterval(thumbnailWidth: CGFloat) -> TimeInterval {
        // Fixed 1 second interval for consistent playback representation
        let fixedInterval: TimeInterval = 1.0
        // Ensure thumbnails don't overlap by using exact thumbnail width
        let minSpacingPoints = thumbnailWidth // No padding - edge to edge
        let minInterval = minSpacingPoints / pixelsPerSecond
        // Use larger of fixed interval or minimum spacing to prevent overlap
        return max(fixedInterval, minInterval)
    }
    
    /// Generate array of thumbnail times based on interval
    /// - Parameter interval: Time interval between thumbnails
    /// - Returns: Array of time intervals for thumbnail generation
    private func generateThumbnailTimes(interval: TimeInterval) -> [TimeInterval] {
        guard totalDuration > 0 else { return [] }
        
        // Always ensure we have a thumbnail at time 0 for proper playhead alignment
        var times: [TimeInterval] = [0.0]
        
        // Add subsequent thumbnails at regular intervals
        var currentTime = interval
        while currentTime <= totalDuration {
            times.append(currentTime)
            currentTime += interval
        }
        
        return times
    }
    
    /// Calculate total content width including padding
    /// - Parameter thumbnailWidth: The width of the thumbnail
    private func calculateContentWidth(thumbnailWidth: CGFloat) -> CGFloat {
        guard totalDuration > 0 else { return screenWidth }
        // Base content width + base offset + boundary padding
        let contentWidth = CGFloat(totalDuration) * pixelsPerSecond
        return contentWidth + baseOffset + boundaryPadding
    }
    
    /// Format time for display in thumbnails
    /// - Parameter time: Time in seconds
    /// - Returns: Formatted time string
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Thumbnail Configuration
    /// Update thumbnail times and trigger regeneration based on current zoom and duration
    private func updateThumbnailConfiguration() {
        // TODO: Implement thumbnail time calculation and update logic
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
    

    
    // MARK: - Thumbnail Generation (Legacy Support)
    
    // ...existing code...
    
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
    
    // Zoom change observer and handler removed as requested
    
    // MARK: - Cache Management
    
    // Removed cacheMemoryUsage property; not needed with ThumbnailProvider
}

// MARK: - Preview

struct VideoThumbnailTrackView_Previews: PreviewProvider {
    static var previews: some View {
        let dummyProvider = ThumbnailProvider()
        VideoThumbnailTrackView(
            thumbnailProvider: dummyProvider,
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