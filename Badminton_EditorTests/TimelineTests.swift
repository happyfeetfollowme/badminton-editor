import Testing
@testable import Badminton_Editor
import AVFoundation

@MainActor
struct TimelineTests {

    var timelineState: TimelineState!
    var player: AVPlayer!

    init() {
        timelineState = TimelineState()
        player = AVPlayer()
    }

    @Test func testTimelineState_initialState() {
        #expect(timelineState.pixelsPerSecond == 50.0)
        #expect(timelineState.contentOffset == 0)
        #expect(timelineState.isDragging == false)
        #expect(timelineState.isSeeking == false)
    }

    @Test func testTimelineState_zoomIn() {
        timelineState.zoomIn()
        #expect(timelineState.pixelsPerSecond == 100.0)
    }

    @Test func testTimelineState_zoomOut() {
        timelineState.pixelsPerSecond = 100.0
        timelineState.zoomOut()
        #expect(timelineState.pixelsPerSecond == 50.0)
    }

    @Test func testTimelineState_reset() {
        timelineState.pixelsPerSecond = 100.0
        timelineState.contentOffset = 100.0
        timelineState.isDragging = true
        timelineState.isSeeking = true
        timelineState.reset()
        #expect(timelineState.pixelsPerSecond == 50.0)
        #expect(timelineState.contentOffset == 0)
        #expect(timelineState.isDragging == false)
        #expect(timelineState.isSeeking == false)
    }

    @Test func testTimelineState_performSeek() async {
        let seekTime: TimeInterval = 10.0

        #expect(timelineState.isSeeking == false)

        timelineState.performSeek(to: seekTime, player: player) { success, error in
            #expect(success == true)
            #expect(error == nil)
        }

        #expect(timelineState.isSeeking == true)

        // Wait for seek to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(timelineState.isSeeking == false)
    }

    // MARK: - ThumbnailCache Tests

    @Test func testThumbnailCache_setAsset() {
        let thumbnailCache = ThumbnailCache()
        let asset = AVAsset()
        thumbnailCache.setAsset(asset)
        #expect(thumbnailCache.getThumbnail(for: 0) == nil)
    }

    @Test func testThumbnailCache_generateSingleThumbnail() async {
        let thumbnailCache = ThumbnailCache()
        let asset = AVAsset()
        thumbnailCache.setAsset(asset)

        let expectation = expectation(description: "Thumbnail generation completes")

        thumbnailCache.generateSingleThumbnail(for: 1.0) { image in
            #expect(image != nil)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    @Test func testThumbnailCache_caching() async {
        let thumbnailCache = ThumbnailCache()
        let asset = AVAsset()
        thumbnailCache.setAsset(asset)

        let expectation = expectation(description: "Thumbnail generation completes")

        thumbnailCache.generateSingleThumbnail(for: 1.0) { image in
            #expect(image != nil)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        #expect(thumbnailCache.hasThumbnail(for: 1.0) == true)
    }
}
// Helper to create expectations since we are not in an XCTestCase
extension TimelineTests {
    func expectation(description: String) -> TestExpectation {
        return TestExpectation(description: description)
    }

    func fulfillment(of expectations: [TestExpectation], timeout: TimeInterval) async {
        await withTaskGroup(of: Void.self) { group in
            for expectation in expectations {
                group.addTask {
                    await expectation.waitForFulfillment(timeout: timeout)
                }
            }
        }
    }
}

class TestExpectation {
    let description: String
    private var isFulfilled = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(description: String) {
        self.description = description
    }

    func fulfill() {
        isFulfilled = true
        continuation?.resume()
    }

    func waitForFulfillment(timeout: TimeInterval) async {
        if isFulfilled { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                self.continuation?.resume()
                self.continuation = nil
            }
        }
    }
}
