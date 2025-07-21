import Foundation
import AVFoundation
import UIKit
import SwiftUI

/// Priority levels for thumbnail generation to optimize performance
enum ThumbnailGenerationPriority {
    case high    // For visible thumbnails - generated immediately
    case normal  // For preload thumbnails - generated with lower priority
    case low     // For background preloading - generated when system is idle
}

@MainActor
class ThumbnailCache: ObservableObject {
    // MARK: - Properties
    
    private let cache = NSCache<NSNumber, UIImage>()
    private var imageGenerator: AVAssetImageGenerator?
    private let thumbnailQueue = DispatchQueue(label: "thumbnail.generation", qos: .userInitiated)
    private var asset: AVAsset?
    
    @Published var thumbnails: [TimeInterval: UIImage] = [:]
    @Published var isGenerating: Bool = false
    
    // Cache configuration
    private let maxCacheSize: Int = 100 // Maximum number of thumbnails to cache
    private let thumbnailSize = CGSize(width: 120, height: 68) // 16:9 aspect ratio
    
    // MARK: - Initialization
    
    init(asset: AVAsset? = nil) {
        self.asset = asset
        
        if let asset = asset {
            self.imageGenerator = AVAssetImageGenerator(asset: asset)
            configureImageGenerator()
        } else {
            self.imageGenerator = nil
        }
        
        setupCache()
        setupMemoryWarningObserver()
        setupPerformanceIntegration()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Cache Configuration
    
    private func setupCache() {
        cache.countLimit = maxCacheSize
        cache.totalCostLimit = maxCacheSize * Int(thumbnailSize.width * thumbnailSize.height * 4) // 4 bytes per pixel
    }
    
    private func configureImageGenerator() {
        guard let generator = imageGenerator else { return }
        
        generator.maximumSize = thumbnailSize
        generator.requestedTimeToleranceBefore = CMTime.zero
        generator.requestedTimeToleranceAfter = CMTime.zero
        generator.appliesPreferredTrackTransform = true
    }
    
    // MARK: - Memory Management
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        Task { @MainActor in
            clearCache()
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        thumbnails.removeAll()
    }
    
    // MARK: - Asset Management
    
    func setAsset(_ newAsset: AVAsset) {
        cancelAllOperations()

        print("ThumbnailCache: Setting new asset with duration: \(newAsset.duration.seconds)")
        asset = newAsset
        clearCache()
        
        // Create new image generator for the asset
        imageGenerator = AVAssetImageGenerator(asset: newAsset)
        configureImageGenerator()
        
        print("ThumbnailCache: Image generator configured successfully")
    }
    
    // MARK: - Thumbnail Retrieval
    
    func getThumbnail(for time: TimeInterval) -> UIImage? {
        let key = NSNumber(value: time)
        return cache.object(forKey: key)
    }
    
    func hasThumbnail(for time: TimeInterval) -> Bool {
        let key = NSNumber(value: time)
        return cache.object(forKey: key) != nil
    }
    
    // MARK: - Thumbnail Generation
    
    func generateThumbnails(for times: [TimeInterval]) {
        guard let asset = asset, let generator = imageGenerator else { return }
        
        // Filter out times that already have cached thumbnails
        let uncachedTimes = times.filter { !hasThumbnail(for: $0) }
        guard !uncachedTimes.isEmpty else { return }
        
        Task { @MainActor in
            isGenerating = true
        }
        
        thumbnailQueue.async { [weak self] in
            guard let self = self else { return }
            
            let cmTimes = uncachedTimes.map { time in
                CMTime(seconds: time, preferredTimescale: 600)
            }
            
            var generatedCount = 0
            let totalCount = cmTimes.count
            
            generator.generateCGImagesAsynchronously(forTimes: cmTimes.map { NSValue(time: $0) }) { [weak self] requestedTime, cgImage, actualTime, result, error in
                
                guard let self = self else { return }
                
                let timeInterval = CMTimeGetSeconds(requestedTime)
                
                if let cgImage = cgImage, result == .succeeded {
                    let uiImage = UIImage(cgImage: cgImage)
                    let key = NSNumber(value: timeInterval)
                    
                    // Cache the thumbnail with cost based on image size
                    let cost = Int(self.thumbnailSize.width * self.thumbnailSize.height * 4)
                    self.cache.setObject(uiImage, forKey: key, cost: cost)
                    
                    // Update published thumbnails on main thread
                    Task { @MainActor in
                        self.thumbnails[timeInterval] = uiImage
                    }
                } else if let error = error {
                    print("Thumbnail generation failed for time \(timeInterval): \(error.localizedDescription)")
                }
                
                generatedCount += 1
                
                // Update generation status when complete
                if generatedCount >= totalCount {
                    Task { @MainActor in
                        self.isGenerating = false
                    }
                }
            }
        }
    }
    
    func generateSingleThumbnail(for time: TimeInterval, completion: @escaping (UIImage?) -> Void) {
        print("ThumbnailCache: generateSingleThumbnail called for time: \(time)")
        
        guard let asset = asset else {
            print("ThumbnailCache: No asset available")
            completion(nil)
            return
        }
        
        guard let generator = imageGenerator else {
            print("ThumbnailCache: No image generator available")
            completion(nil)
            return
        }
        
        // Check cache first
        if let cachedImage = getThumbnail(for: time) {
            print("ThumbnailCache: Found cached thumbnail for time: \(time)")
            completion(cachedImage)
            return
        }
        
        print("ThumbnailCache: Generating new thumbnail for time: \(time)")
        
        thumbnailQueue.async { [weak self] in
            guard let self = self else {
                print("ThumbnailCache: Self was deallocated")
                completion(nil)
                return
            }
            
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            print("ThumbnailCache: Attempting to generate CGImage at time: \(cmTime)")
            
            // Use the new async method instead of deprecated copyCGImage
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { [weak self] requestedTime, cgImage, actualTime, result, error in
                guard let self = self else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                if let cgImage = cgImage, result == .succeeded {
                    let uiImage = UIImage(cgImage: cgImage)
                    
                    print("ThumbnailCache: Successfully generated thumbnail for time: \(time)")
                    
                    // Cache the thumbnail on main thread to avoid threading issues
                    DispatchQueue.main.async {
                        let key = NSNumber(value: time)
                        let cost = Int(self.thumbnailSize.width * self.thumbnailSize.height * 4)
                        self.cache.setObject(uiImage, forKey: key, cost: cost)
                        
                        // Update published thumbnails
                        self.thumbnails[time] = uiImage
                        
                        completion(uiImage)
                    }
                } else {
                    let errorMessage = error?.localizedDescription ?? "Unknown error"
                    print("ThumbnailCache: Single thumbnail generation failed for time \(time): \(errorMessage)")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            }
        }
    }
    
    // MARK: - Enhanced Batch Operations
    
    func preloadThumbnails(for timeRange: ClosedRange<TimeInterval>, interval: TimeInterval = 1.0) {
        let times = stride(from: timeRange.lowerBound, through: timeRange.upperBound, by: interval).map { $0 }
        generateThumbnails(for: times)
    }
    
    /// Calculate which thumbnails are needed based on current zoom and scroll position
    /// This is the core logic for task 10 requirement 1
    func calculateNeededThumbnails(
        visibleStartTime: TimeInterval,
        visibleEndTime: TimeInterval,
        totalDuration: TimeInterval,
        pixelsPerSecond: CGFloat,
        preloadBuffer: TimeInterval = 10.0
    ) -> [TimeInterval] {
        // Ensure valid time range
        let startTime = max(0, visibleStartTime - preloadBuffer)
        let endTime = min(totalDuration, visibleEndTime + preloadBuffer)
        
        guard startTime < endTime else { return [] }
        
        // Calculate optimal thumbnail interval based on zoom level
        let thumbnailInterval = calculateOptimalThumbnailInterval(pixelsPerSecond: pixelsPerSecond)
        
        // Generate thumbnail times within the range
        var thumbnailTimes: [TimeInterval] = []
        var currentTime = startTime
        
        while currentTime <= endTime {
            thumbnailTimes.append(currentTime)
            currentTime += thumbnailInterval
        }
        
        // Filter out times that already have cached thumbnails
        return thumbnailTimes.filter { !hasThumbnail(for: $0) }
    }
    
    /// Calculate optimal thumbnail interval based on zoom level
    private func calculateOptimalThumbnailInterval(pixelsPerSecond: CGFloat) -> TimeInterval {
        switch pixelsPerSecond {
        case 0..<20:
            return 2.0  // Low zoom: fewer thumbnails, 2 second intervals
        case 20..<40:
            return 1.5  // Medium-low zoom: 1.5 second intervals
        case 40..<80:
            return 1.0  // Medium zoom: 1 second intervals
        case 80..<120:
            return 0.5  // High zoom: 0.5 second intervals
        default:
            return 0.25 // Very high zoom: 0.25 second intervals for maximum detail
        }
    }
    
    /// Generate thumbnails for visible range with priority handling
    /// This implements task 10 requirements 2 and 3
    func generateThumbnailsForVisibleRange(
        visibleStartTime: TimeInterval,
        visibleEndTime: TimeInterval,
        totalDuration: TimeInterval,
        pixelsPerSecond: CGFloat,
        priority: ThumbnailGenerationPriority = .normal
    ) {
        let neededTimes = calculateNeededThumbnails(
            visibleStartTime: visibleStartTime,
            visibleEndTime: visibleEndTime,
            totalDuration: totalDuration,
            pixelsPerSecond: pixelsPerSecond
        )
        
        guard !neededTimes.isEmpty else { return }
        
        // Separate visible and preload thumbnails for priority handling
        let visibleTimes = neededTimes.filter { time in
            time >= visibleStartTime && time <= visibleEndTime
        }
        let preloadTimes = neededTimes.filter { time in
            time < visibleStartTime || time > visibleEndTime
        }
        
        // Generate visible thumbnails first with high priority
        if !visibleTimes.isEmpty {
            generateThumbnailsWithPriority(for: visibleTimes, priority: .high)
        }
        
        // Generate preload thumbnails with normal priority
        if !preloadTimes.isEmpty {
            generateThumbnailsWithPriority(for: preloadTimes, priority: .normal)
        }
    }
    
    /// Generate thumbnails with priority handling and enhanced error recovery
    /// This implements task 10 requirements 2, 3, and 4
    private func generateThumbnailsWithPriority(
        for times: [TimeInterval],
        priority: ThumbnailGenerationPriority
    ) {
        guard let asset = asset, let generator = imageGenerator else { return }
        
        // Filter out times that already have cached thumbnails
        let uncachedTimes = times.filter { !hasThumbnail(for: $0) }
        guard !uncachedTimes.isEmpty else { return }
        
        Task { @MainActor in
            isGenerating = true
        }
        
        // Choose appropriate queue based on priority
        let queue: DispatchQueue
        switch priority {
        case .high:
            queue = DispatchQueue.main // High priority on main queue for immediate processing
        case .normal:
            queue = thumbnailQueue // Normal priority on background queue
        case .low:
            queue = DispatchQueue.global(qos: .background) // Low priority on background
        }
        
        queue.async { [weak self] in
            self?.performPriorityThumbnailGeneration(
                for: uncachedTimes,
                asset: asset,
                generator: generator,
                priority: priority
            )
        }
    }
    
    /// Perform thumbnail generation with enhanced error handling and fallback images
    /// This implements task 10 requirement 4
    private func performPriorityThumbnailGeneration(
        for times: [TimeInterval],
        asset: AVAsset,
        generator: AVAssetImageGenerator,
        priority: ThumbnailGenerationPriority
    ) {
        let cmTimes = times.map { time in
            CMTime(seconds: time, preferredTimescale: 600)
        }
        
        var generatedCount = 0
        let totalCount = cmTimes.count
        
        // Configure generator based on priority
        let configuredGenerator = AVAssetImageGenerator(asset: asset)
        configuredGenerator.appliesPreferredTrackTransform = true
        configuredGenerator.maximumSize = thumbnailSize
        
        // Set tolerance based on priority
        let tolerance: CMTime
        switch priority {
        case .high:
            tolerance = CMTime.zero // Exact frames for visible thumbnails
        case .normal:
            tolerance = CMTime(seconds: 0.1, preferredTimescale: 600) // Small tolerance
        case .low:
            tolerance = CMTime(seconds: 0.2, preferredTimescale: 600) // Larger tolerance for background
        }
        
        configuredGenerator.requestedTimeToleranceBefore = tolerance
        configuredGenerator.requestedTimeToleranceAfter = tolerance
        
        configuredGenerator.generateCGImagesAsynchronously(forTimes: cmTimes.map { NSValue(time: $0) }) { [weak self] requestedTime, cgImage, actualTime, result, error in
            
            guard let self = self else { return }
            
            let timeInterval = CMTimeGetSeconds(requestedTime)
            
            if let cgImage = cgImage, result == .succeeded {
                // Successful generation
                let uiImage = UIImage(cgImage: cgImage)
                self.cacheThumbnailWithPriority(uiImage, for: timeInterval, priority: priority)
            } else {
                // Handle generation error with fallback placeholder
                self.handleThumbnailGenerationError(for: timeInterval, error: error, priority: priority)
            }
            
            generatedCount += 1
            
            // Update generation status when complete
            if generatedCount >= totalCount {
                Task { @MainActor in
                    self.isGenerating = false
                }
            }
        }
    }
    
    /// Cache thumbnail with priority-based cost calculation
    private func cacheThumbnailWithPriority(_ image: UIImage, for time: TimeInterval, priority: ThumbnailGenerationPriority) {
        let key = NSNumber(value: time)
        
        // Calculate cost based on priority (high priority thumbnails get higher cost to stay in cache longer)
        let baseCost = Int(thumbnailSize.width * thumbnailSize.height * 4)
        let priorityCost: Int
        switch priority {
        case .high:
            priorityCost = baseCost * 3 // High priority thumbnails are 3x more expensive to evict
        case .normal:
            priorityCost = baseCost * 2 // Normal priority thumbnails are 2x more expensive to evict
        case .low:
            priorityCost = baseCost // Low priority thumbnails have base cost
        }
        
        cache.setObject(image, forKey: key, cost: priorityCost)
        
        // Update published thumbnails on main thread
        Task { @MainActor in
            self.thumbnails[time] = image
        }
    }
    
    /// Handle thumbnail generation errors with appropriate fallback images
    /// This implements task 10 requirement 4 - error handling with fallback placeholder images
    private func handleThumbnailGenerationError(
        for time: TimeInterval,
        error: Error?,
        priority: ThumbnailGenerationPriority
    ) {
        // Log error for debugging
        if let error = error {
            print("Thumbnail generation failed for time \(time) with priority \(priority): \(error.localizedDescription)")
        }
        
        // Create fallback placeholder image with time information
        let fallbackImage = createErrorFallbackImage(for: time, priority: priority)
        
        // Cache the fallback image with lower cost to allow easy replacement
        let key = NSNumber(value: time)
        let fallbackCost = Int(thumbnailSize.width * thumbnailSize.height) // Lower cost for fallback images
        cache.setObject(fallbackImage, forKey: key, cost: fallbackCost)
        
        // Update published thumbnails on main thread
        Task { @MainActor in
            self.thumbnails[time] = fallbackImage
        }
    }
    
    /// Create error fallback image with time and priority information
    private func createErrorFallbackImage(for time: TimeInterval, priority: ThumbnailGenerationPriority) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        return renderer.image { context in
            // Background gradient based on priority
            let colors: [UIColor]
            switch priority {
            case .high:
                colors = [UIColor.systemRed.withAlphaComponent(0.3), UIColor.systemRed.withAlphaComponent(0.1)]
            case .normal:
                colors = [UIColor.systemOrange.withAlphaComponent(0.3), UIColor.systemOrange.withAlphaComponent(0.1)]
            case .low:
                colors = [UIColor.systemGray.withAlphaComponent(0.3), UIColor.systemGray.withAlphaComponent(0.1)]
            }
            
            // Create gradient
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors.map { $0.cgColor } as CFArray, locations: nil)
            
            context.cgContext.drawLinearGradient(
                gradient!,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: thumbnailSize.width, y: thumbnailSize.height),
                options: []
            )
            
            // Add error indicator
            let iconSize: CGFloat = 20
            let iconRect = CGRect(
                x: (thumbnailSize.width - iconSize) / 2,
                y: (thumbnailSize.height - iconSize) / 2 - 8,
                width: iconSize,
                height: iconSize
            )
            
            // Draw error icon
            UIColor.white.withAlphaComponent(0.8).setFill()
            let iconPath = UIBezierPath(ovalIn: iconRect)
            iconPath.fill()
            
            // Add exclamation mark
            UIColor.red.setFill()
            let exclamationRect = CGRect(
                x: iconRect.midX - 1,
                y: iconRect.midY - 6,
                width: 2,
                height: 8
            )
            context.cgContext.fill(exclamationRect)
            
            let dotRect = CGRect(
                x: iconRect.midX - 1,
                y: iconRect.midY + 3,
                width: 2,
                height: 2
            )
            context.cgContext.fill(dotRect)
            
            // Add time and priority text
            let timeText = formatTimeForFallback(time)
            let priorityText = "P: \(priority)"
            let fullText = "\(timeText) (\(priorityText))"

            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .font: UIFont.systemFont(ofSize: 9, weight: .medium),
                .strokeColor: UIColor.black.withAlphaComponent(0.5),
                .strokeWidth: -1.0
            ]
            
            let textSize = fullText.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (thumbnailSize.width - textSize.width) / 2,
                y: thumbnailSize.height - textSize.height - 4,
                width: textSize.width,
                height: textSize.height
            )
            
            fullText.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    /// Format time for fallback image display
    private func formatTimeForFallback(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Cache Statistics
    
    var cacheInfo: (count: Int, memoryUsage: String) {
        let count = thumbnails.count
        let estimatedMemory = count * Int(thumbnailSize.width * thumbnailSize.height * 4)
        let memoryMB = Double(estimatedMemory) / (1024 * 1024)
        return (count, String(format: "%.1f MB", memoryMB))
    }
    
    // MARK: - Utility Methods
    
    func cancelAllOperations() {
        imageGenerator?.cancelAllCGImageGeneration()
        Task { @MainActor in
            isGenerating = false
        }
    }
    
    func evictOldThumbnails(keepingRecent recentCount: Int = 50) {
        let sortedTimes = thumbnails.keys.sorted()
        let toRemove = sortedTimes.dropLast(recentCount)
        
        for time in toRemove {
            let key = NSNumber(value: time)
            cache.removeObject(forKey: key)
            thumbnails.removeValue(forKey: time)
        }
    }
    
    // MARK: - Performance Integration
    
    /// Setup performance monitoring integration for automatic cache cleanup
    /// This implements task 15 requirement 2: "Add memory usage monitoring and automatic cache cleanup"
    private func setupPerformanceIntegration() {
        // Listen for cache cleanup notifications from performance monitor
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TimelineCacheCleanup"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handlePerformanceCacheCleanup(notification)
        }
        
        // Listen for zoom changes to adjust cache strategy
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TimelineZoomChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleZoomChange(notification)
        }
    }
    
    /// Handle performance-triggered cache cleanup
    private func handlePerformanceCacheCleanup(_ notification: Notification) {
        let reason = notification.userInfo?["reason"] as? String ?? "unknown"
        print("Performing cache cleanup due to: \(reason)")
        
        if reason == "memory_critical" {
            // Aggressive cleanup for critical memory situations
            performAggressiveCacheCleanup()
        } else {
            // Standard cleanup
            performStandardCacheCleanup()
        }
    }
    
    /// Perform aggressive cache cleanup for critical memory situations
    private func performAggressiveCacheCleanup() {
        // Keep only the most recent 20 thumbnails
        evictOldThumbnails(keepingRecent: 20)
        
        // Reduce cache limits temporarily
        cache.countLimit = 50
        cache.totalCostLimit = cache.totalCostLimit / 2
        
        print("Aggressive cache cleanup completed - kept 20 recent thumbnails")
    }
    
    /// Perform standard cache cleanup
    private func performStandardCacheCleanup() {
        // Keep the most recent 50 thumbnails
        evictOldThumbnails(keepingRecent: 50)
        
        print("Standard cache cleanup completed - kept 50 recent thumbnails")
    }
    
    /// Handle zoom level changes to optimize thumbnail density
    private func handleZoomChange(_ notification: Notification) {
        guard let pixelsPerSecond = notification.userInfo?["pixelsPerSecond"] as? CGFloat,
              let currentTime = notification.userInfo?["currentTime"] as? TimeInterval else {
            return
        }
        
        // Adjust cache strategy based on zoom level
        if pixelsPerSecond > 100 {
            // High zoom - need more thumbnails, increase cache size
            cache.countLimit = min(150, maxCacheSize + 50)
        } else if pixelsPerSecond < 30 {
            // Low zoom - need fewer thumbnails, decrease cache size
            cache.countLimit = max(50, maxCacheSize - 50)
        } else {
            // Normal zoom - use default cache size
            cache.countLimit = maxCacheSize
        }
        
        print("Cache limits adjusted for zoom level: \(pixelsPerSecond)x")
    }
}

// MARK: - Extensions

extension ThumbnailCache {
    /// Convenience method to get thumbnail with fallback placeholder
    func getThumbnailOrPlaceholder(for time: TimeInterval) -> UIImage {
        if let thumbnail = getThumbnail(for: time) {
            return thumbnail
        }
        
        // Generate placeholder image
        return createPlaceholderImage()
    }
    
    private func createPlaceholderImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        return renderer.image { context in
            // Gray background
            UIColor.systemGray4.setFill()
            context.fill(CGRect(origin: .zero, size: thumbnailSize))
            
            // Add film strip icon or similar placeholder
            UIColor.systemGray2.setFill()
            let iconSize: CGFloat = 24
            let iconRect = CGRect(
                x: (thumbnailSize.width - iconSize) / 2,
                y: (thumbnailSize.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            context.fill(iconRect)
        }
    }
}