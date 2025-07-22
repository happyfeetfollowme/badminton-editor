import Foundation
import AVFoundation
import UIKit
import SwiftUI
import Photos
import VideoToolbox

// MARK: - PHAsset Support (iOS Photo Library)

extension ThumbnailCache {
    /// 設定 PHAsset，並自動處理 iCloud、HEVC、錯誤診斷與日誌
    func setPHAsset(_ phAsset: PHAsset) {
        print("ThumbnailCache: setPHAsset called. localIdentifier=\(phAsset.localIdentifier), mediaType=\(phAsset.mediaType.rawValue), duration=\(phAsset.duration)")

        // 先清空快取
        self.clearCache()
        
        // Set PHAsset mode flag
        self.isUsingPHAsset = true

        // 取得 AVAsset
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true // 允許自動下載 iCloud 影片
        options.deliveryMode = .highQualityFormat
        options.version = .current

        PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { [weak self] avAsset, audioMix, info in
            guard let self = self else { return }

            if let info = info {
                if let isInCloud = info[PHImageResultIsInCloudKey] as? Bool, isInCloud {
                    print("ThumbnailCache: PHAsset is in iCloud, will auto-download if needed.")
                }
                if let cancelled = info[PHImageCancelledKey] as? Bool, cancelled {
                    print("ThumbnailCache: PHAsset request was cancelled.")
                }
                if let error = info[PHImageErrorKey] as? NSError {
                    print("ThumbnailCache: PHAsset request error: \(error.localizedDescription)")
                }
            }

            guard let avAsset = avAsset else {
                print("ThumbnailCache: Failed to get AVAsset from PHAsset. info=\(String(describing: info))")
                
                // 嘗試使用 PHImageManager 的其他選項作為備用方案
                self.tryAlternativeVideoRequest(for: phAsset)
                return
            }

            Task {
                // 檢查 AVAsset 是否可播放、可讀取
                if let urlAsset = avAsset as? AVURLAsset {
                    print("ThumbnailCache: AVURLAsset url=\(urlAsset.url)")
                    print("ThumbnailCache: URL scheme=\(urlAsset.url.scheme ?? "nil"), pathExtension=\(urlAsset.url.pathExtension)")
                }

                // 檢查 HEVC 支援
                let hevcSupported = self.checkHEVCSupport()
                print("ThumbnailCache: HEVC hardware decode supported: \(hevcSupported)")

                // duration (async for iOS 16+)
                var durationSeconds: Double = 0
                if #available(iOS 16.0, *) {
                    do {
                        let duration = try await avAsset.load(.duration)
                        durationSeconds = duration.seconds
                    } catch {
                        print("ThumbnailCache: Failed to load duration: \(error)")
                        print("ThumbnailCache: Trying alternative asset loading...")
                        self.tryAlternativeVideoRequest(for: phAsset)
                        return
                    }
                } else {
                    durationSeconds = avAsset.duration.seconds
                }

                print("ThumbnailCache: AVAsset duration=\(durationSeconds), isPlayable=\(avAsset.isPlayable), isReadable=\(avAsset.isReadable)")

                // 列出所有 video track 的 codec type
                var videoTracks: [AVAssetTrack] = []
                if #available(iOS 16.0, *) {
                    do {
                        videoTracks = try await avAsset.loadTracks(withMediaType: .video)
                    } catch {
                        print("ThumbnailCache: Failed to load video tracks: \(error)")
                    }
                } else {
                    videoTracks = avAsset.tracks(withMediaType: .video)
                }
                for (idx, track) in videoTracks.enumerated() {
                    var dimensions = CGSize.zero
                    if #available(iOS 16.0, *) {
                        do {
                            dimensions = try await track.load(.naturalSize)
                        } catch {
                            print("ThumbnailCache: Failed to load naturalSize: \(error)")
                        }
                    } else {
                        dimensions = track.naturalSize
                    }
                    var formatDescriptions: [CMFormatDescription] = []
                    if #available(iOS 16.0, *) {
                        do {
                            let rawFormats = try await track.load(.formatDescriptions)
                            formatDescriptions = rawFormats.compactMap { $0 as? CMFormatDescription }
                        } catch {
                            print("ThumbnailCache: Failed to load formatDescriptions: \(error)")
                        }
                    } else {
                        formatDescriptions = track.formatDescriptions as? [CMFormatDescription] ?? []
                    }
                    if let formatDesc = formatDescriptions.first {
                        let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
                        let codecStr = self.FourCharCodeToString(codecType)
                        print("ThumbnailCache: VideoTrack[\(idx)] codec=\(codecStr), dimensions=\(dimensions)")
                        
                        // 檢查視頻格式並應用 GPU 優化
                        if codecStr == "hvc1" || codecStr == "hev1" {
                            print("ThumbnailCache: ✅ HEVC video detected - applying GPU optimizations")
                        } else {
                            print("ThumbnailCache: ✅ Non-HEVC video detected (codec: \(codecStr)) - applying GPU optimizations")
                        }
                    } else {
                        print("ThumbnailCache: ⚠️ No format description found for video track")
                    }
                }

                // 檢查 AVAsset 是否真的可用
                if !avAsset.isPlayable || !avAsset.isReadable {
                    print("ThumbnailCache: ❌ AVAsset is not playable or readable")
                    self.tryAlternativeVideoRequest(for: phAsset)
                    return
                }

                // 設定 asset 並生成縮圖
                DispatchQueue.main.async {
                    self.setAsset(avAsset)
                }
            }
        }
    }

    /// FourCharCode 轉 String (for codec type)
    func FourCharCodeToString(_ code: FourCharCode) -> String {
        let n = Int(code)
        var s: String = ""
        s.append(Character(UnicodeScalar((n >> 24) & 255)!))
        s.append(Character(UnicodeScalar((n >> 16) & 255)!))
        s.append(Character(UnicodeScalar((n >> 8) & 255)!))
        s.append(Character(UnicodeScalar(n & 255)!))
        return s
    }
    
    /// 檢查 HEVC 硬體解碼支援
    private func checkHEVCSupport() -> Bool {
        // 檢查設備是否支援 HEVC 硬體解碼
        if #available(iOS 11.0, *) {
            return VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        }
        return false
    }
    

    
    /// 嘗試替代的影片請求方法
    private func tryAlternativeVideoRequest(for phAsset: PHAsset) {
        print("ThumbnailCache: Trying alternative video request with compatibility mode...")
        
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .mediumQualityFormat // 降低品質要求
        options.version = .current
        
        // 嘗試請求相容格式
        PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { [weak self] avAsset, audioMix, info in
            guard let self = self else { return }
            
            if let avAsset = avAsset {
                print("ThumbnailCache: ✅ Alternative request succeeded")
                DispatchQueue.main.async {
                    self.setAsset(avAsset)
                }
            } else {
                print("ThumbnailCache: ❌ Alternative request also failed")
                
                // 最後嘗試：使用 PHImageManager 直接請求圖片作為縮圖
                self.tryImageFallback(for: phAsset)
            }
        }
    }
    
    /// 最後備用方案：使用靜態圖片作為縮圖
    private func tryImageFallback(for phAsset: PHAsset) {
        print("ThumbnailCache: Using image fallback for unsupported video")
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        
        let targetSize = CGSize(width: 240, height: 135)
        
        PHImageManager.default().requestImage(
            for: phAsset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            guard let self = self, let image = image else {
                print("ThumbnailCache: ❌ Image fallback also failed")
                return
            }
            
            print("ThumbnailCache: ✅ Using static image as video thumbnail")
            
            // 將靜態圖片作為 0.0 時間點的縮圖
            DispatchQueue.main.async {
                let key = NSNumber(value: 0.0)
                let cost = Int(self.thumbnailSize.width * self.thumbnailSize.height * 4)
                self.cache.setObject(image, forKey: key, cost: cost)
                self.thumbnails[0.0] = image
            }
        }
    }
    

}

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
    private var isUsingPHAsset: Bool = false // Track if we're using PHAsset mode
    
    @Published var thumbnails: [TimeInterval: UIImage] = [:]
    @Published var isGenerating: Bool = false
    

    
    // Cache configuration
    private let maxCacheSize: Int = 80 // 減少快取數量以因應更高解析度
    private let thumbnailSize = CGSize(width: 240, height: 135) // 16:9 aspect ratio, 2x resolution
    
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
        
        // 極速配置，減少品質要求以提升載入速度
        generator.maximumSize = CGSize(width: 160, height: 90) // 大幅減小尺寸以提升速度
        
        // 設置較大的時間容差以加快生成速度
        let fastTolerance = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = fastTolerance
        generator.requestedTimeToleranceAfter = fastTolerance
        
        generator.appliesPreferredTrackTransform = true
        
        // 快速模式設定，犧牲品質換取速度
        generator.apertureMode = .productionAperture // 使用較快的模式
        
        // 停用複雜處理
        if #available(iOS 16.0, *) {
            generator.videoComposition = nil // 減少處理複雜度
        }
        
        print("ThumbnailCache: Image generator configured for maximum speed")
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
        // Note: Don't reset isUsingPHAsset here as it's used by setPHAsset
    }
    
    // MARK: - Asset Management
    
    func setAsset(_ newAsset: AVAsset, force: Bool = false) {
        // Don't override PHAsset setup with regular asset unless forced
        if isUsingPHAsset && !force {
            print("ThumbnailCache: Ignoring setAsset call - already using PHAsset mode")
            return
        }
        
        print("ThumbnailCache: Setting new asset with duration: \(newAsset.duration.seconds)")
        asset = newAsset
        isUsingPHAsset = false // Reset PHAsset mode when setting regular asset
        clearCache()
        
        // Create new image generator for the asset
        imageGenerator = AVAssetImageGenerator(asset: newAsset)
        configureImageGenerator()
        
        print("ThumbnailCache: Image generator configured successfully")
        
        // 延遲縮圖生成，優先載入播放器
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 延遲 0.1 秒
            
            // 立即生成第一個縮圖 (0.0 時間點) 確保快速顯示
            print("ThumbnailCache: Generating first thumbnail at 0.0")
            generateSingleThumbnail(for: 0.0) { image in
                if let _ = image {
                    print("ThumbnailCache: First thumbnail (0.0) generated successfully")
                } else {
                    print("ThumbnailCache: Failed to generate first thumbnail (0.0)")
                }
            }
            
            // 延遲生成關鍵縮圖，不阻塞主要載入流程
            try? await Task.sleep(nanoseconds: 200_000_000) // 再延遲 0.2 秒
            
            let duration = newAsset.duration.seconds
            if duration > 0 && duration.isFinite {
                // 減少預生成的縮圖數量
                let keyTimes: [TimeInterval] = [min(1.0, duration/2)] // 只生成中間點縮圖
                print("ThumbnailCache: Pre-generating minimal key thumbnails at times: \(keyTimes)")
                
                for time in keyTimes where time < duration {
                    generateSingleThumbnail(for: time) { image in
                        if let _ = image {
                            print("ThumbnailCache: Key thumbnail at \(time) generated successfully")
                        }
                    }
                }
            }
        }
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
        
        // 提升圖像品質設定
        configuredGenerator.apertureMode = .cleanAperture
        
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
            
            // Add time text
            let timeText = formatTimeForFallback(time)
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .font: UIFont.systemFont(ofSize: 9, weight: .medium),
                .strokeColor: UIColor.black.withAlphaComponent(0.5),
                .strokeWidth: -1.0
            ]
            
            let textSize = timeText.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (thumbnailSize.width - textSize.width) / 2,
                y: thumbnailSize.height - textSize.height - 4,
                width: textSize.width,
                height: textSize.height
            )
            
            timeText.draw(in: textRect, withAttributes: attributes)
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
        // Note: AVAssetImageGenerator doesn't provide direct cancellation
        // This method is here for future enhancement if needed
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


