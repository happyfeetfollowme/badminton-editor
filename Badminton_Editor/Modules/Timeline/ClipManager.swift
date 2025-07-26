import SwiftUI
import Foundation
import AVFoundation

// MARK: - Clip Manager

/// ObservableObject class for managing video clips and split points
/// Handles clip boundary calculation, split point management, and clip selection
class ClipManager: ObservableObject {
    // MARK: - Published Properties
    
    /// Array of video clips calculated from split points and video duration
    @Published var clips: [VideoClip] = []
    
    /// Array of split points that define clip boundaries
    @Published var splitPoints: [SplitPoint] = []
    
    /// ID of the currently selected clip, if any
    @Published var selectedClipId: UUID? = nil
    
    // MARK: - Private Properties
    
    /// Total duration of the video in seconds
    private var videoDuration: TimeInterval = 0
    
    // MARK: - Initialization
    
    init() {
        // Initialize with empty state
    }
    
    // MARK: - Core Functionality Methods
    
    /// Initialize clips for a video with the given duration
    /// Creates a single clip spanning the entire video duration
    /// - Parameter duration: Total duration of the video in seconds
    func initializeClips(duration: TimeInterval) {
        guard duration > 0 else { return }
        
        videoDuration = duration
        splitPoints.removeAll()
        selectedClipId = nil
        
        // Create single clip for entire video (Requirement 1.1)
        clips = [VideoClip(startTime: 0.0, endTime: duration)]
    }
    
    /// Add a split point at the specified time and recalculate clip boundaries
    /// - Parameter time: Time position in seconds where the split should occur
    /// - Returns: True if split point was added successfully, false if invalid
    @discardableResult
    func addSplitPoint(at time: TimeInterval) -> Bool {
        // Comprehensive validation for split point time (Requirements 4.1, 4.2)
        guard isValidSplitTime(time) else { 
            print("ClipManager: Invalid split time \(time) - outside valid range or too close to existing splits")
            return false 
        }
        
        // Check if split point already exists at this time with tolerance
        let duplicateTolerance: TimeInterval = 0.01
        guard !splitPoints.contains(where: { abs($0.time - time) < duplicateTolerance }) else { 
            print("ClipManager: Split point already exists at time \(time)")
            return false 
        }
        
        // Validate that we don't exceed maximum split points (prevent memory issues)
        let maxSplitPoints = 1000 // Reasonable limit for performance
        guard splitPoints.count < maxSplitPoints else {
            print("ClipManager: Maximum split points (\(maxSplitPoints)) exceeded")
            return false
        }
        
        // Add new split point with error handling
        do {
            let newSplitPoint = SplitPoint(time: time)
            splitPoints.append(newSplitPoint)
            
            // Recalculate clip boundaries with validation (Requirements 4.3, 4.4, 5.4)
            let recalculationSuccess = recalculateClipsWithValidation()
            
            if !recalculationSuccess {
                // Rollback the split point addition if recalculation failed
                splitPoints.removeAll { $0.time == time }
                print("ClipManager: Failed to recalculate clips after adding split point, rolled back")
                return false
            }
            
            print("ClipManager: Successfully added split point at \(time), total clips: \(clips.count)")
            return true
            
        } catch {
            print("ClipManager: Error adding split point: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Select a clip at the specified time position
    /// - Parameter time: Time position to find and select the clip at
    func selectClip(at time: TimeInterval) {
        // Find clip containing the specified time
        guard let targetClip = clips.first(where: { $0.contains(time: time) }) else {
            clearSelection()
            return
        }
        
        // Update selection state (Requirements 1.2, 1.3)
        selectedClipId = targetClip.id
        updateClipSelectionStates()
    }
    
    /// Clear the current clip selection
    func clearSelection() {
        selectedClipId = nil
        updateClipSelectionStates()
    }
    
    /// Get the clip at the specified time position
    /// - Parameter time: Time position to search for
    /// - Returns: VideoClip if found, nil otherwise
    func getClip(at time: TimeInterval) -> VideoClip? {
        return clips.first { $0.contains(time: time) }
    }
    
    /// Get the currently selected clip
    /// - Returns: Selected VideoClip if any, nil otherwise
    func getSelectedClip() -> VideoClip? {
        guard let selectedId = selectedClipId else { return nil }
        return clips.first { $0.id == selectedId }
    }
    
    // MARK: - Private Helper Methods
    
    /// Validate if a split time is valid for creating a split point
    /// Enhanced validation with comprehensive edge case handling
    /// - Parameter time: Time to validate
    /// - Returns: True if valid, false otherwise
    private func isValidSplitTime(_ time: TimeInterval) -> Bool {
        // Handle edge case: invalid time values (NaN, infinite, negative)
        guard time.isFinite && !time.isNaN && time >= 0 else {
            print("ClipManager: Invalid time value - not finite or negative: \(time)")
            return false
        }
        
        // Handle edge case: zero or invalid video duration
        guard videoDuration > 0 && videoDuration.isFinite else {
            print("ClipManager: Invalid video duration: \(videoDuration)")
            return false
        }
        
        // Cannot split at the very beginning or end of video (Requirements 4.1, 4.2)
        guard time > 0.0 && time < videoDuration else {
            print("ClipManager: Split time \(time) is at video boundaries (0.0 to \(videoDuration))")
            return false
        }
        
        // Ensure minimum clip duration to prevent very short clips (Requirement 5.4, 5.5)
        let minClipDuration: TimeInterval = 0.1
        
        // Handle edge case: extremely short video duration
        if videoDuration < minClipDuration * 2 {
            print("ClipManager: Video too short (\(videoDuration)s) for splitting (minimum: \(minClipDuration * 2)s)")
            return false
        }
        
        // Check if split would create clips that are too short
        let sortedSplits = splitPoints.map { $0.time }.sorted()
        
        // Check distance from start
        if time < minClipDuration {
            print("ClipManager: Split time \(time) too close to start (minimum: \(minClipDuration)s)")
            return false
        }
        
        // Check distance from end
        if (videoDuration - time) < minClipDuration {
            print("ClipManager: Split time \(time) too close to end (minimum: \(minClipDuration)s from \(videoDuration))")
            return false
        }
        
        // Check distance from existing split points
        for existingSplit in sortedSplits {
            if abs(time - existingSplit) < minClipDuration {
                print("ClipManager: Split time \(time) too close to existing split at \(existingSplit) (minimum: \(minClipDuration)s)")
                return false
            }
        }
        
        // Handle edge case: maximum zoom levels - ensure split is visible
        // At maximum zoom, ensure split points are at least 1 pixel apart
        let maxPixelsPerSecond: CGFloat = 1000 // Maximum zoom level
        let minVisibleTimeAtMaxZoom = Double(1.0 / maxPixelsPerSecond) // 1 pixel worth of time
        
        for existingSplit in sortedSplits {
            if abs(time - existingSplit) < minVisibleTimeAtMaxZoom {
                print("ClipManager: Split time \(time) too close to existing split at maximum zoom level")
                return false
            }
        }
        
        return true
    }
    
    /// Recalculate all clip boundaries based on current split points
    /// Enhanced version with comprehensive validation and error handling
    /// Implements the clip boundary calculation logic from Requirements 5.1, 5.2, 5.3, 5.4, 5.5
    private func recalculateClipsWithValidation() -> Bool {
        guard videoDuration > 0 && videoDuration.isFinite else {
            print("ClipManager: Cannot recalculate clips with invalid video duration: \(videoDuration)")
            return false
        }
        
        // Get sorted split times with validation
        let sortedSplitTimes = splitPoints.map { $0.time }.sorted()
        
        // Validate all split times are within bounds
        for splitTime in sortedSplitTimes {
            guard splitTime > 0 && splitTime < videoDuration && splitTime.isFinite else {
                print("ClipManager: Invalid split time detected during recalculation: \(splitTime)")
                return false
            }
        }
        
        // Store current selection to preserve it
        let currentSelectedId = selectedClipId
        let previousClips = clips // Backup for rollback
        
        // Clear existing clips
        clips.removeAll()
        
        do {
            if sortedSplitTimes.isEmpty {
                // No splits - single clip for entire video (Requirement 5.1)
                let singleClip = VideoClip(startTime: 0.0, endTime: videoDuration)
                clips.append(singleClip)
            } else {
                // Create clips based on split points (Requirements 5.2, 5.3)
                
                // First clip: from start to first split (Requirement 5.1)
                let firstClip = VideoClip(startTime: 0.0, endTime: sortedSplitTimes[0])
                clips.append(firstClip)
                
                // Middle clips: from split to split (Requirement 5.2)
                for i in 0..<(sortedSplitTimes.count - 1) {
                    let middleClip = VideoClip(
                        startTime: sortedSplitTimes[i],
                        endTime: sortedSplitTimes[i + 1]
                    )
                    clips.append(middleClip)
                }
                
                // Last clip: from final split to end (Requirement 5.3)
                let lastClip = VideoClip(
                    startTime: sortedSplitTimes.last!,
                    endTime: videoDuration
                )
                clips.append(lastClip)
            }
            
            // Comprehensive validation of clip boundaries (Requirement 5.5)
            let validationResult = validateClipBoundariesWithErrorHandling()
            if !validationResult.isValid {
                print("ClipManager: Clip boundary validation failed: \(validationResult.errorMessage)")
                // Rollback to previous clips
                clips = previousClips
                return false
            }
            
            // Restore selection if the clip still exists
            if let selectedId = currentSelectedId {
                // Try to find a clip that contains the same time range as the previously selected clip
                selectedClipId = clips.first { $0.id == selectedId }?.id
            }
            
            // Update selection states
            updateClipSelectionStates()
            
            print("ClipManager: Successfully recalculated \(clips.count) clips from \(sortedSplitTimes.count) split points")
            return true
            
        } catch {
            print("ClipManager: Error during clip recalculation: \(error.localizedDescription)")
            // Rollback to previous clips
            clips = previousClips
            return false
        }
    }
    
    /// Legacy method for backward compatibility
    private func recalculateClips() {
        _ = recalculateClipsWithValidation()
    }
    
    /// Update the selection state of all clips based on selectedClipId
    private func updateClipSelectionStates() {
        clips = clips.map { clip in
            var updatedClip = clip
            updatedClip.isSelected = (clip.id == selectedClipId)
            return updatedClip
        }
    }
    
    /// Enhanced validation result structure for comprehensive error reporting
    private struct ValidationResult {
        let isValid: Bool
        let errorMessage: String
        
        static let valid = ValidationResult(isValid: true, errorMessage: "")
        static func invalid(_ message: String) -> ValidationResult {
            return ValidationResult(isValid: false, errorMessage: message)
        }
    }
    
    /// Validate that clip boundaries have no gaps or overlaps with comprehensive error handling
    /// Enhanced version that returns detailed validation results instead of using assertions
    /// This is a safety check to ensure Requirements 5.5 is met
    private func validateClipBoundariesWithErrorHandling() -> ValidationResult {
        // Handle edge case: empty clips array
        guard !clips.isEmpty else {
            return .invalid("No clips to validate")
        }
        
        // Single clip validation
        if clips.count == 1 {
            let clip = clips[0]
            
            // Validate single clip spans entire duration
            let tolerance: TimeInterval = 0.001
            if abs(clip.startTime - 0.0) > tolerance {
                return .invalid("Single clip does not start at 0: \(clip.startTime)")
            }
            if abs(clip.endTime - videoDuration) > tolerance {
                return .invalid("Single clip does not end at video duration: \(clip.endTime) vs \(videoDuration)")
            }
            
            return .valid
        }
        
        // Multiple clips validation
        let sortedClips = clips.sorted { $0.startTime < $1.startTime }
        let tolerance: TimeInterval = 0.001
        
        // Validate each adjacent pair of clips
        for i in 0..<(sortedClips.count - 1) {
            let currentClip = sortedClips[i]
            let nextClip = sortedClips[i + 1]
            
            // Validate clip duration is positive
            if currentClip.duration <= 0 {
                return .invalid("Clip \(i) has non-positive duration: \(currentClip.duration)")
            }
            
            // Ensure no gap between clips
            let gap = nextClip.startTime - currentClip.endTime
            if abs(gap) > tolerance {
                return .invalid("Gap detected between clips \(i) and \(i+1): \(gap)s at \(currentClip.endTime) to \(nextClip.startTime)")
            }
            
            // Ensure no overlap between clips
            if currentClip.endTime > nextClip.startTime + tolerance {
                return .invalid("Overlap detected between clips \(i) and \(i+1): \(currentClip.endTime) > \(nextClip.startTime)")
            }
            
            // Validate time values are finite
            if !currentClip.startTime.isFinite || !currentClip.endTime.isFinite {
                return .invalid("Clip \(i) has invalid time values: start=\(currentClip.startTime), end=\(currentClip.endTime)")
            }
        }
        
        // Validate last clip duration
        if let lastClip = sortedClips.last, lastClip.duration <= 0 {
            return .invalid("Last clip has non-positive duration: \(lastClip.duration)")
        }
        
        // Ensure first clip starts at 0
        if let firstClip = sortedClips.first {
            if abs(firstClip.startTime - 0.0) > tolerance {
                return .invalid("First clip does not start at 0: \(firstClip.startTime)")
            }
        }
        
        // Ensure last clip ends at video duration
        if let lastClip = sortedClips.last {
            if abs(lastClip.endTime - videoDuration) > tolerance {
                return .invalid("Last clip does not end at video duration: \(lastClip.endTime) vs \(videoDuration)")
            }
        }
        
        // Validate total duration matches video duration
        let totalClipDuration = sortedClips.reduce(0) { $0 + $1.duration }
        if abs(totalClipDuration - videoDuration) > tolerance {
            return .invalid("Total clip duration (\(totalClipDuration)) does not match video duration (\(videoDuration))")
        }
        
        return .valid
    }
    
    /// Legacy validation method for backward compatibility (now uses enhanced validation)
    private func validateClipBoundaries() {
        let result = validateClipBoundariesWithErrorHandling()
        if !result.isValid {
            print("ClipManager: Validation failed: \(result.errorMessage)")
            // In production, we log the error instead of crashing with assert
            // This provides better user experience while still catching issues
        }
    }
    
    // MARK: - Utility Methods
    
    /// Get all split times in sorted order
    var sortedSplitTimes: [TimeInterval] {
        return splitPoints.map { $0.time }.sorted()
    }
    
    /// Get the number of clips
    var clipCount: Int {
        return clips.count
    }
    
    /// Get the number of split points
    var splitPointCount: Int {
        return splitPoints.count
    }
    
    /// Check if any clip is currently selected
    var hasSelection: Bool {
        return selectedClipId != nil
    }
    
    /// Reset all clip and split point data
    func reset() {
        clips.removeAll()
        splitPoints.removeAll()
        selectedClipId = nil
        videoDuration = 0
    }
}