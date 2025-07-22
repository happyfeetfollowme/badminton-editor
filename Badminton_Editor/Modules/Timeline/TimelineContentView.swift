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
    
    // MARK: - Constants
    
    /// Base offset for timeline alignment
    private let baseOffset: CGFloat = 500
    
    /// Extra padding for smooth scrolling at boundaries
    private let boundaryPadding: CGFloat = 1000
    
    // MARK: - Body
    
    var body: some View {
        // Remove ScrollView and use direct content positioning
        ZStack(alignment: .leading) {
            // Background content area
            timelineBackground
            
            // Timeline ruler (time scale markers)
            timelineRuler
            
            // Video thumbnail track placeholder
            videoThumbnailTrack
            
            // Rally markers overlay
            rallyMarkersOverlay
        }
        .frame(
            width: calculateContentWidth(),
            height: 120 // Standard timeline height
        )
        .offset(x: contentOffset) // Direct offset control without ScrollView
        .clipped() // Clip content that extends beyond bounds
    }
    
    // MARK: - Timeline Background
    
    @ViewBuilder
    private var timelineBackground: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .frame(
                width: calculateContentWidth(),
                height: 120
            )
    }
    
    // MARK: - Timeline Ruler
    
    @ViewBuilder
    private var timelineRuler: some View {
        TimelineRulerView(
            totalDuration: totalDuration,
            pixelsPerSecond: pixelsPerSecond,
            currentTime: 0 // Not used in the new implementation, but required for compatibility
        )
    }
    
    // MARK: - Video Thumbnail Track
    
    @ViewBuilder
    private var videoThumbnailTrack: some View {
        VideoThumbnailTrackView(
            player: player,
            totalDuration: totalDuration,
            pixelsPerSecond: pixelsPerSecond,
            contentOffset: contentOffset,
            screenWidth: screenWidth
        )
    }
    
    // MARK: - Rally Markers Overlay
    
    @ViewBuilder
    private var rallyMarkersOverlay: some View {
        ZStack(alignment: .leading) {
            ForEach(markers) { marker in
                MarkerPinView(marker: marker)
                    .position(
                        x: calculateMarkerPosition(for: marker.time),
                        y: 60 // Center vertically in timeline
                    )
                    .onTapGesture {
                        handleMarkerTap(marker: marker)
                    }
            }
        }
        .frame(
            width: calculateContentWidth(),
            height: 120
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
            }
        )
        .frame(height: 120)
        .background(Color.black)
    }
}