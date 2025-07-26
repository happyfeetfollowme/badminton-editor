import SwiftUI
import Foundation
import AVFoundation

// MARK: - Data Models

// MARK: - Video Clip Management

/// Represents a video clip with time boundaries and selection state
struct VideoClip: Identifiable, Equatable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    var isSelected: Bool = false
    
    /// Duration of the clip in seconds
    var duration: TimeInterval {
        return endTime - startTime
    }
    
    /// Checks if a given time falls within this clip's boundaries
    /// - Parameter time: The time to check in seconds
    /// - Returns: True if the time is within the clip boundaries (inclusive start, exclusive end)
    func contains(time: TimeInterval) -> Bool {
        return time >= startTime && time < endTime
    }
    
    /// Creates a new VideoClip with updated selection state
    /// - Parameter selected: The new selection state
    /// - Returns: A new VideoClip instance with updated selection
    func withSelection(_ selected: Bool) -> VideoClip {
        var clip = self
        clip.isSelected = selected
        return clip
    }
}

/// Represents a split point in the timeline where clips are divided
struct SplitPoint: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let createdAt: Date = Date()
    
    /// Creates a new split point at the specified time
    /// - Parameter time: The time position in seconds where the split occurs
    init(time: TimeInterval) {
        self.time = time
    }
}

