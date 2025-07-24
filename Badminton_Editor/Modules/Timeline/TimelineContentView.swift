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
    
    /// Rally markers to display on timeline
    let markers: [RallyMarker]
    
    /// Callback for marker tap interactions
    let onMarkerTap: ((RallyMarker, CGPoint) -> Void)?

    /// Thumbnail provider for timeline thumbnails
    @ObservedObject var thumbnailProvider: ThumbnailProvider
    
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
                
                // Timeline ruler (time scale markers)
                timelineRuler(height: timelineHeight)
                
                // Video thumbnail track
                videoThumbnailTrack(height: timelineHeight)
                
                // Rally markers overlay
                rallyMarkersOverlay(height: timelineHeight)
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
    
    // MARK: - Timeline Ruler
    
    @ViewBuilder
    private func timelineRuler(height: CGFloat) -> some View {
        TimelineRulerView(
            totalDuration: totalDuration,
            pixelsPerSecond: pixelsPerSecond,
            currentTime: 0 // Not used in the new implementation, but required for compatibility
        )
        .frame(height: height)
    }
    
    // MARK: - Video Thumbnail Track
    
    @ViewBuilder
    private func videoThumbnailTrack(height: CGFloat) -> some View {
        VideoThumbnailTrackView(
            thumbnailProvider: thumbnailProvider,
            player: player,
            totalDuration: totalDuration,
            pixelsPerSecond: pixelsPerSecond,
            contentOffset: contentOffset,
            screenWidth: screenWidth
        )
        .frame(height: height)
    }
    
    // MARK: - Rally Markers Overlay
    
    @ViewBuilder
    private func rallyMarkersOverlay(height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(markers) { marker in
                MarkerPinView(marker: marker)
                    .position(
                        x: calculateMarkerPosition(for: marker.time),
                        y: height / 2 // Center vertically in timeline
                    )
                    .onTapGesture {
                        handleMarkerTap(marker: marker)
                    }
            }
        }
        .frame(
            width: calculateContentWidth(),
            height: height
        )
    }
    
    // MARK: - Helper Methods
    
    /// Calculate total content width including padding
    private func calculateContentWidth() -> CGFloat {
        guard totalDuration > 0 else { return screenWidth }
        
        // Base content width + base offset + boundary padding
        let contentWidth = CGFloat(totalDuration) * pixelsPerSecond
        return contentWidth + baseOffset + boundaryPadding
    }
    
    /// Calculate marker position on timeline
    private func calculateMarkerPosition(for time: TimeInterval) -> CGFloat {
        return baseOffset + CGFloat(time) * pixelsPerSecond
    }
    
    /// Handle marker tap interaction
    private func handleMarkerTap(marker: RallyMarker) {
        let markerPosition = calculateMarkerPosition(for: marker.time)
        let tapPoint = CGPoint(x: markerPosition, y: 60)
        onMarkerTap?(marker, tapPoint)
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
        TimelineContentView(
            player: AVPlayer(),
            totalDuration: 120.0,
            pixelsPerSecond: 50.0,
            contentOffset: .constant(0),
            isDragging: false,
            screenWidth: 400,
            markers: [
                RallyMarker(time: 30.0, type: .start),
                RallyMarker(time: 45.0, type: .end),
                RallyMarker(time: 60.0, type: .start)
            ],
            onMarkerTap: { marker, position in
                print("Marker tapped: \(marker.type) at \(marker.time)")
            },
            thumbnailProvider: dummyProvider
        )
        .frame(height: 120)
        .background(Color.black)
    }
}
