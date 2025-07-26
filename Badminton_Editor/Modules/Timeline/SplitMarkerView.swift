import SwiftUI
import Foundation

/// SwiftUI view for rendering split point markers on the timeline
/// Displays visual indicators at split point time positions to show where clips are divided
struct SplitMarkerView: View {
    // MARK: - Properties
    
    /// Array of split points to render markers for
    let splitPoints: [SplitPoint]
    
    /// Current zoom level (pixels per second) for positioning calculations
    let pixelsPerSecond: CGFloat
    
    /// Base offset for timeline alignment (should match VideoThumbnailTrackView)
    let baseOffset: CGFloat
    
    /// Height of the timeline area where markers should be displayed
    let timelineHeight: CGFloat
    
    // MARK: - Constants
    
    /// Width of the split marker line
    private let markerWidth: CGFloat = 2.0
    
    /// Color of the split marker
    private let markerColor = Color.red
    
    /// Shadow properties for better visibility against thumbnails
    private let shadowRadius: CGFloat = 1.0
    private let shadowColor = Color.black.opacity(0.8)
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Render a marker for each split point
            ForEach(splitPoints) { splitPoint in
                splitMarker(for: splitPoint)
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Create a visual marker for a specific split point
    /// - Parameter splitPoint: The split point to create a marker for
    /// - Returns: A view representing the split marker
    @ViewBuilder
    private func splitMarker(for splitPoint: SplitPoint) -> some View {
        let xPosition = baseOffset + CGFloat(splitPoint.time) * pixelsPerSecond
        
        Rectangle()
            .fill(markerColor)
            .frame(width: markerWidth, height: timelineHeight)
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 0)
            .position(
                x: xPosition,
                y: timelineHeight / 2
            )
            .onAppear {
                // Debug logging to verify marker positioning
                print("SplitMarkerView: Positioning marker at time \(splitPoint.time)s, x: \(xPosition)px (baseOffset: \(baseOffset), pixelsPerSecond: \(pixelsPerSecond))")
            }
    }
}

// MARK: - Preview

struct SplitMarkerView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleSplitPoints = [
            SplitPoint(time: 10.0),
            SplitPoint(time: 25.0),
            SplitPoint(time: 45.0)
        ]
        
        ZStack {
            // Background to simulate thumbnail track
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 80)
            
            SplitMarkerView(
                splitPoints: sampleSplitPoints,
                pixelsPerSecond: 50.0,
                baseOffset: 500.0,
                timelineHeight: 80.0
            )
        }
        .frame(width: 400, height: 80)
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Split Markers")
    }
}