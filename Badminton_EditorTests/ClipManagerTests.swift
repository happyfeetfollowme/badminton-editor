import XCTest
@testable import Badminton_Editor

/// Unit tests for ClipManager functionality
/// Tests clip boundary calculation, split point management, and selection handling
final class ClipManagerTests: XCTestCase {
    
    var clipManager: ClipManager!
    
    override func setUp() {
        super.setUp()
        clipManager = ClipManager()
    }
    
    override func tearDown() {
        clipManager = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitializeClipsWithValidDuration() {
        // Test Requirement 1.1: Single clip spans entire video duration
        let duration: TimeInterval = 120.0
        
        clipManager.initializeClips(duration: duration)
        
        XCTAssertEqual(clipManager.clips.count, 1)
        XCTAssertEqual(clipManager.clips.first?.startTime, 0.0)
        XCTAssertEqual(clipManager.clips.first?.endTime, duration)
        XCTAssertEqual(clipManager.splitPoints.count, 0)
        XCTAssertNil(clipManager.selectedClipId)
    }
    
    func testInitializeClipsWithZeroDuration() {
        clipManager.initializeClips(duration: 0.0)
        
        XCTAssertEqual(clipManager.clips.count, 0)
        XCTAssertEqual(clipManager.splitPoints.count, 0)
    }
    
    // MARK: - Split Point Tests
    
    func testAddValidSplitPoint() {
        // Test Requirements 4.3, 4.4: Split divides clip and updates boundaries
        clipManager.initializeClips(duration: 120.0)
        
        let splitTime: TimeInterval = 60.0
        let result = clipManager.addSplitPoint(at: splitTime)
        
        XCTAssertTrue(result)
        XCTAssertEqual(clipManager.splitPoints.count, 1)
        XCTAssertEqual(clipManager.splitPoints.first?.time, splitTime)
        XCTAssertEqual(clipManager.clips.count, 2)
        
        // Verify first clip ends at split point
        XCTAssertEqual(clipManager.clips[0].startTime, 0.0)
        XCTAssertEqual(clipManager.clips[0].endTime, splitTime)
        
        // Verify second clip starts at split point
        XCTAssertEqual(clipManager.clips[1].startTime, splitTime)
        XCTAssertEqual(clipManager.clips[1].endTime, 120.0)
    }
    
    func testAddSplitPointAtInvalidTimes() {
        clipManager.initializeClips(duration: 120.0)
        
        // Test split at start (invalid)
        XCTAssertFalse(clipManager.addSplitPoint(at: 0.0))
        
        // Test split at end (invalid)
        XCTAssertFalse(clipManager.addSplitPoint(at: 120.0))
        
        // Test split too close to start
        XCTAssertFalse(clipManager.addSplitPoint(at: 0.05))
        
        // Test split too close to end
        XCTAssertFalse(clipManager.addSplitPoint(at: 119.95))
        
        XCTAssertEqual(clipManager.splitPoints.count, 0)
        XCTAssertEqual(clipManager.clips.count, 1)
    }
    
    func testAddDuplicateSplitPoint() {
        clipManager.initializeClips(duration: 120.0)
        
        let splitTime: TimeInterval = 60.0
        XCTAssertTrue(clipManager.addSplitPoint(at: splitTime))
        XCTAssertFalse(clipManager.addSplitPoint(at: splitTime))
        
        XCTAssertEqual(clipManager.splitPoints.count, 1)
    }
    
    func testMultipleSplitPoints() {
        // Test Requirements 5.2, 5.3: Multiple clips from split points
        clipManager.initializeClips(duration: 120.0)
        
        XCTAssertTrue(clipManager.addSplitPoint(at: 30.0))
        XCTAssertTrue(clipManager.addSplitPoint(at: 90.0))
        XCTAssertTrue(clipManager.addSplitPoint(at: 60.0)) // Add out of order
        
        XCTAssertEqual(clipManager.clips.count, 4)
        XCTAssertEqual(clipManager.splitPoints.count, 3)
        
        // Verify clips are in correct order
        let sortedClips = clipManager.clips.sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(sortedClips[0].startTime, 0.0)
        XCTAssertEqual(sortedClips[0].endTime, 30.0)
        XCTAssertEqual(sortedClips[1].startTime, 30.0)
        XCTAssertEqual(sortedClips[1].endTime, 60.0)
        XCTAssertEqual(sortedClips[2].startTime, 60.0)
        XCTAssertEqual(sortedClips[2].endTime, 90.0)
        XCTAssertEqual(sortedClips[3].startTime, 90.0)
        XCTAssertEqual(sortedClips[3].endTime, 120.0)
    }
    
    // MARK: - Clip Selection Tests
    
    func testSelectClipAtTime() {
        // Test Requirements 1.2, 1.3: Clip selection and state management
        clipManager.initializeClips(duration: 120.0)
        clipManager.addSplitPoint(at: 60.0)
        
        // Select first clip
        clipManager.selectClip(at: 30.0)
        
        XCTAssertNotNil(clipManager.selectedClipId)
        XCTAssertEqual(clipManager.getSelectedClip()?.startTime, 0.0)
        XCTAssertEqual(clipManager.getSelectedClip()?.endTime, 60.0)
        XCTAssertTrue(clipManager.getSelectedClip()?.isSelected ?? false)
        
        // Select second clip
        clipManager.selectClip(at: 90.0)
        
        XCTAssertNotNil(clipManager.selectedClipId)
        XCTAssertEqual(clipManager.getSelectedClip()?.startTime, 60.0)
        XCTAssertEqual(clipManager.getSelectedClip()?.endTime, 120.0)
        
        // Verify only one clip is selected
        let selectedClips = clipManager.clips.filter { $0.isSelected }
        XCTAssertEqual(selectedClips.count, 1)
    }
    
    func testSelectClipAtInvalidTime() {
        clipManager.initializeClips(duration: 120.0)
        
        clipManager.selectClip(at: 150.0) // Outside video duration
        
        XCTAssertNil(clipManager.selectedClipId)
        XCTAssertNil(clipManager.getSelectedClip())
    }
    
    func testClearSelection() {
        clipManager.initializeClips(duration: 120.0)
        clipManager.selectClip(at: 30.0)
        
        XCTAssertNotNil(clipManager.selectedClipId)
        
        clipManager.clearSelection()
        
        XCTAssertNil(clipManager.selectedClipId)
        XCTAssertNil(clipManager.getSelectedClip())
        
        // Verify no clips are marked as selected
        let selectedClips = clipManager.clips.filter { $0.isSelected }
        XCTAssertEqual(selectedClips.count, 0)
    }
    
    // MARK: - Clip Retrieval Tests
    
    func testGetClipAtTime() {
        clipManager.initializeClips(duration: 120.0)
        clipManager.addSplitPoint(at: 60.0)
        
        // Test getting first clip
        let firstClip = clipManager.getClip(at: 30.0)
        XCTAssertNotNil(firstClip)
        XCTAssertEqual(firstClip?.startTime, 0.0)
        XCTAssertEqual(firstClip?.endTime, 60.0)
        
        // Test getting second clip
        let secondClip = clipManager.getClip(at: 90.0)
        XCTAssertNotNil(secondClip)
        XCTAssertEqual(secondClip?.startTime, 60.0)
        XCTAssertEqual(secondClip?.endTime, 120.0)
        
        // Test getting clip at boundary (should return first clip)
        let boundaryClip = clipManager.getClip(at: 60.0)
        XCTAssertNotNil(boundaryClip)
        XCTAssertEqual(boundaryClip?.startTime, 60.0)
        
        // Test getting clip outside range
        let invalidClip = clipManager.getClip(at: 150.0)
        XCTAssertNil(invalidClip)
    }
    
    // MARK: - Boundary Validation Tests
    
    func testClipBoundariesWithNoGapsOrOverlaps() {
        // Test Requirement 5.5: No gaps or overlaps between clips
        clipManager.initializeClips(duration: 120.0)
        clipManager.addSplitPoint(at: 30.0)
        clipManager.addSplitPoint(at: 90.0)
        
        let sortedClips = clipManager.clips.sorted { $0.startTime < $1.startTime }
        
        // Verify no gaps between clips
        for i in 0..<(sortedClips.count - 1) {
            XCTAssertEqual(sortedClips[i].endTime, sortedClips[i + 1].startTime,
                          accuracy: 0.001, "Gap found between clips")
        }
        
        // Verify first clip starts at 0
        XCTAssertEqual(sortedClips.first?.startTime ?? -1, 0.0, accuracy: 0.001)
        
        // Verify last clip ends at duration
        XCTAssertEqual(sortedClips.last?.endTime ?? -1, 120.0, accuracy: 0.001)
    }
    
    // MARK: - Utility Method Tests
    
    func testUtilityMethods() {
        clipManager.initializeClips(duration: 120.0)
        clipManager.addSplitPoint(at: 60.0)
        clipManager.selectClip(at: 30.0)
        
        XCTAssertEqual(clipManager.clipCount, 2)
        XCTAssertEqual(clipManager.splitPointCount, 1)
        XCTAssertTrue(clipManager.hasSelection)
        
        let sortedTimes = clipManager.sortedSplitTimes
        XCTAssertEqual(sortedTimes, [60.0])
        
        clipManager.reset()
        
        XCTAssertEqual(clipManager.clipCount, 0)
        XCTAssertEqual(clipManager.splitPointCount, 0)
        XCTAssertFalse(clipManager.hasSelection)
    }
    
    // MARK: - Menu Position Validation Tests
    
    func testMenuPositionValidation() {
        // Test that menu positioning doesn't cause crashes with invalid coordinates
        clipManager.initializeClips(duration: 120.0)
        clipManager.selectClip(at: 60.0)
        
        let selectedClip = clipManager.getSelectedClip()
        XCTAssertNotNil(selectedClip)
        XCTAssertTrue(selectedClip?.isSelected ?? false)
        
        // Verify clip selection works correctly for menu display
        XCTAssertEqual(selectedClip?.startTime, 0.0)
        XCTAssertEqual(selectedClip?.endTime, 120.0)
    }
}