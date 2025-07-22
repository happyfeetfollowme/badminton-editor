import SwiftUI
import Foundation
import AVFoundation

// MARK: - Data Models

/// Represents a rally marker on the timeline
struct RallyMarker: Identifiable, Equatable {
    let id = UUID()
    var time: TimeInterval
    var type: MarkerType
    
    enum MarkerType {
        case start, end
    }
}

// MARK: - Helper Views

/// Visual representation of a single marker pin
struct MarkerPinView: View {
    let marker: RallyMarker
    
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(marker.type == .start ? .green : .red)
                .frame(width: 2, height: 80)
            Image(systemName: marker.type == .start ? "arrow.right.to.line.alt" : "arrow.left.to.line.alt")
                .foregroundColor(marker.type == .start ? .green : .red)
                .font(.system(size: 18))
                .rotationEffect(.degrees(90))
        }
    }
}

/// Context menu for marker actions
struct MarkerActionMenu: View {
    @Binding var isPresented: Bool
    @Binding var position: CGPoint
    let marker: RallyMarker?
    let onAdd: (RallyMarker.MarkerType) -> Void
    let onDelete: () -> Void

    var body: some View {
        if isPresented {
            VStack(alignment: .leading, spacing: 12) {
                if let marker = marker {
                    // Delete existing marker
                    Button("刪除標記") {
                        onDelete()
                        isPresented = false
                    }
                } else {
                    // Add new marker
                    Button("標記回合開始") {
                        onAdd(.start)
                        isPresented = false
                    }
                    Divider()
                    Button("標記回合結束") {
                        onAdd(.end)
                        isPresented = false
                    }
                }
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(12)
            .shadow(radius: 10)
            .position(position)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Timeline Ruler View

/// Timeline ruler view that displays time scale markers and labels
/// Provides visual time reference with second and 10-second intervals
struct TimelineRulerView: View {
    // MARK: - Properties
    
    /// Total duration of the video content
    let totalDuration: TimeInterval
    
    /// Current zoom level (pixels per second)
    let pixelsPerSecond: CGFloat
    
    /// Current time for reference (maintained for compatibility)
    let currentTime: TimeInterval
    
    /// Base offset for timeline alignment
    private let baseOffset: CGFloat = 500
    
    /// Boundary padding for smooth scrolling
    private let boundaryPadding: CGFloat = 1000
    
    // MARK: - Constants
    
    /// Minimum zoom level to show time labels
    private let minZoomForLabels: CGFloat = 25.0
    
    /// Height for major ruler marks (10-second intervals)
    private let majorMarkHeight: CGFloat = 20.0
    
    /// Height for minor ruler marks (1-second intervals)
    private let minorMarkHeight: CGFloat = 10.0
    
    /// Opacity for major ruler marks
    private let majorMarkOpacity: Double = 0.8
    
    /// Opacity for minor ruler marks
    private let minorMarkOpacity: Double = 0.4
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 0) {
            // Base offset padding
            Rectangle()
                .fill(Color.clear)
                .frame(width: baseOffset)
            
            // Generate ruler marks for each second
            ForEach(0..<Int(ceil(totalDuration)), id: \.self) { second in
                rulerMark(for: TimeInterval(second))
            }
            
            // Boundary padding
            Rectangle()
                .fill(Color.clear)
                .frame(width: boundaryPadding)
        }
    }
    
    // MARK: - Ruler Mark Generation
    
    /// Create a ruler mark for a specific time position
    /// - Parameter time: The time in seconds for this ruler mark
    /// - Returns: A view representing the ruler mark with optional time label
    @ViewBuilder
    private func rulerMark(for time: TimeInterval) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Determine if this is a major mark (10-second interval)
            let isMajorMark = Int(time) % 10 == 0
            let isMinorMark = Int(time) % 5 == 0 && !isMajorMark
            
            // Create the ruler mark line
            rulerMarkLine(isMajor: isMajorMark, isMinor: isMinorMark)
            
            // Add time label for major marks when zoom level is sufficient
            if isMajorMark && shouldShowTimeLabels {
                timeLabel(for: time)
            }
            
            Spacer()
        }
        .frame(width: pixelsPerSecond)
    }
    
    /// Create the visual ruler mark line
    /// - Parameters:
    ///   - isMajor: Whether this is a major (10-second) mark
    ///   - isMinor: Whether this is a minor (5-second) mark
    /// - Returns: A rectangle representing the ruler mark
    @ViewBuilder
    private func rulerMarkLine(isMajor: Bool, isMinor: Bool) -> some View {
        if isMajor {
            Rectangle()
                .fill(Color.white.opacity(majorMarkOpacity))
                .frame(width: 1, height: majorMarkHeight)
        } else if isMinor {
            Rectangle()
                .fill(Color.white.opacity(minorMarkOpacity + 0.2))
                .frame(width: 1, height: minorMarkHeight + 5)
        } else {
            Rectangle()
                .fill(Color.white.opacity(minorMarkOpacity))
                .frame(width: 1, height: minorMarkHeight)
        }
    }
    
    /// Create time label for major marks
    /// - Parameter time: The time to display
    /// - Returns: A text view with formatted time
    @ViewBuilder
    private func timeLabel(for time: TimeInterval) -> some View {
        Text(formatTime(time))
            .font(.system(size: labelFontSize, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.7))
            .padding(.top, 2)
    }
    
    // MARK: - Computed Properties
    
    /// Whether time labels should be shown based on current zoom level
    private var shouldShowTimeLabels: Bool {
        return pixelsPerSecond >= minZoomForLabels
    }
    
    /// Font size for time labels based on zoom level
    private var labelFontSize: CGFloat {
        switch pixelsPerSecond {
        case 0..<30:
            return 7
        case 30..<60:
            return 8
        case 60..<100:
            return 9
        case 100..<150:
            return 10
        default:
            return 11
        }
    }
    
    // MARK: - Helper Methods
    
    /// Format time interval for display
    /// - Parameter time: Time interval in seconds
    /// - Returns: Formatted time string (MM:SS or H:MM:SS for longer durations)
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}