import SwiftUI
import AVKit
import AVFoundation

/// Scrollable content container for the timeline that displays video thumbnails and markers
/// This view handles the scrollable content area with dynamic width calculation
struct TimelineContentView: View {
    // MARK: - Properties
    
    /// AVPlayer instance for video operations
    let player: AVPlayer
    
    /// Total duration of the video content
    let totalDuration: TimeInterval
    
    /// Current zoom level (pixels per second)
    let pixelsPerSecond: CGFloat
    
    /// Binding for programmatic scroll control
    @Binding var contentOffset: CGFloat
    
    /// Whether the timeline is currently being dragged
    let isDragging: Bool
    
    /// Screen width for calculations
    let screenWidth: CGFloat
    
    /// Thumbnail provider for timeline thumbnails
    @ObservedObject var thumbnailProvider: ThumbnailProvider
    
    /// Timeline state for clip management and gesture coordination
    @ObservedObject var timelineState: TimelineState
    
    // MARK: - Constants
    
    /// Base offset for timeline alignment
    private let baseOffset: CGFloat = 500
    
    /// Extra padding for smooth scrolling at boundaries
    private let boundaryPadding: CGFloat = 1000
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            let timelineHeight = geometry.size.height
            
            // Use direct offset positioning for timeline content
            ZStack(alignment: .leading) {
                // Background content area
                timelineBackground(height: timelineHeight)
                
                // Video thumbnail track
                videoThumbnailTrack(height: timelineHeight)
                
            }
            .frame(
                width: calculateContentWidth(),
                height: timelineHeight
            )
            .offset(x: contentOffset) // Direct offset control for smooth scrolling
            .clipped() // Clip content that extends beyond bounds
        }
    }
    
    // MARK: - Timeline Background
    
    @ViewBuilder
    private func timelineBackground(height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .frame(
                width: calculateContentWidth(),
                height: height
            )
    }
    
    // MARK: - Video Thumbnail Track
    
    @ViewBuilder
    private func videoThumbnailTrack(height: CGFloat) -> some View {
        VideoThumbnailTrackView(
            thumbnailProvider: thumbnailProvider,
            timelineState: timelineState,
            player: player,
            totalDuration: totalDuration,
            pixelsPerSecond: pixelsPerSecond,
            contentOffset: contentOffset,
            screenWidth: screenWidth
        )
        .frame(height: height)
    }
    
    
    // MARK: - Helper Methods
    
    /// Calculate total content width including padding
    private func calculateContentWidth() -> CGFloat {
        guard totalDuration > 0 else { return screenWidth }
        
        // Base content width + base offset + boundary padding
        let contentWidth = CGFloat(totalDuration) * pixelsPerSecond
        return contentWidth + baseOffset + boundaryPadding
    }
    
    
    /// Format time for display
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

struct TimelineContentView_Previews: PreviewProvider {
    static var previews: some View {
        let dummyProvider = ThumbnailProvider()
        let dummyTimelineState = TimelineState()
        
        TimelineContentView(
            player: AVPlayer(),
            totalDuration: 120.0,
            pixelsPerSecond: 50.0,
            contentOffset: .constant(0),
            isDragging: false,
            screenWidth: 400,
            thumbnailProvider: dummyProvider,
            timelineState: dummyTimelineState
        )
        .frame(height: 120)
        .background(Color.black)
        .onAppear {
            dummyTimelineState.initializeClipsForVideo(duration: 120.0)
        }
    }
}
