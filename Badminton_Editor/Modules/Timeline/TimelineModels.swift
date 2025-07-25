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
