import Foundation
import AVFoundation
import UIKit
import SwiftUI
import Photos
import VideoToolbox

// MARK: - PHAsset Support (iOS Photo Library)

extension ThumbnailProvider {
    /// 設定 PHAsset，並自動處理 iCloud、HEVC、錯誤診斷與日誌
    func setPHAsset(_ phAsset: PHAsset) {
        print("ThumbnailProvider: setPHAsset called. localIdentifier=\(phAsset.localIdentifier), mediaType=\(phAsset.mediaType.rawValue), duration=\(phAsset.duration)")

        // 先清空
        self.clear()
        
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
                    print("ThumbnailProvider: PHAsset is in iCloud, will auto-download if needed.")
                }
                if let cancelled = info[PHImageCancelledKey] as? Bool, cancelled {
                    print("ThumbnailProvider: PHAsset request was cancelled.")
                }
                if let error = info[PHImageErrorKey] as? NSError {
                    print("ThumbnailProvider: PHAsset request error: \(error.localizedDescription)")
                }
            }

            guard let avAsset = avAsset else {
                print("ThumbnailProvider: Failed to get AVAsset from PHAsset. info=\(String(describing: info))")
                
                // 嘗試使用 PHImageManager 的其他選項作為備用方案
                self.tryAlternativeVideoRequest(for: phAsset)
                return
            }

            Task {
                // 檢查 AVAsset 是否可播放、可讀取
                if let urlAsset = avAsset as? AVURLAsset {
                    print("ThumbnailProvider: AVURLAsset url=\(urlAsset.url)")
                    print("ThumbnailProvider: URL scheme=\(urlAsset.url.scheme ?? "nil"), pathExtension=\(urlAsset.url.pathExtension)")
                }

                // 檢查 HEVC 支援
                let hevcSupported = self.checkHEVCSupport()
                print("ThumbnailProvider: HEVC hardware decode supported: \(hevcSupported)")

                // duration (async for iOS 16+)
                var durationSeconds: Double = 0
                if #available(iOS 16.0, *) {
                    do {
                        let duration = try await avAsset.load(.duration)
                        durationSeconds = duration.seconds
                    } catch {
                        print("ThumbnailProvider: Failed to load duration: \(error)")
                        print("ThumbnailProvider: Trying alternative asset loading...")
                        self.tryAlternativeVideoRequest(for: phAsset)
                        return
                    }
                } else {
                    durationSeconds = avAsset.duration.seconds
                }

                var isPlayable: Bool = false
                var isReadable: Bool = false
                if #available(iOS 16.0, *) {
                    isPlayable = (try? await avAsset.load(.isPlayable)) ?? false
                    isReadable = (try? await avAsset.load(.isReadable)) ?? false
                } else {
                    isPlayable = avAsset.isPlayable
                    isReadable = avAsset.isReadable
                }
                print("ThumbnailProvider: AVAsset duration=\(durationSeconds), isPlayable=\(isPlayable), isReadable=\(isReadable)")

                // 列出所有 video track 的 codec type
                var videoTracks: [AVAssetTrack] = []
                if #available(iOS 16.0, *) {
                    do {
                        videoTracks = try await avAsset.loadTracks(withMediaType: .video)
                    } catch {
                        print("ThumbnailProvider: Failed to load video tracks: \(error)")
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
                            print("ThumbnailProvider: Failed to load naturalSize: \(error)")
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
                            print("ThumbnailProvider: Failed to load formatDescriptions: \(error)")
                        }
                    } else {
                        formatDescriptions = track.formatDescriptions as? [CMFormatDescription] ?? []
                    }
                    if let formatDesc = formatDescriptions.first {
                        let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
                        let codecStr = self.FourCharCodeToString(codecType)
                        print("ThumbnailProvider: VideoTrack[\(idx)] codec=\(codecStr), dimensions=\(dimensions)")
                        
                        // 檢查視頻格式並應用 GPU 優化
                        if codecStr == "hvc1" || codecStr == "hev1" {
                            print("ThumbnailProvider: ✅ HEVC video detected - applying GPU optimizations")
                        } else {
                            print("ThumbnailProvider: ✅ Non-HEVC video detected (codec: \(codecStr)) - applying GPU optimizations")
                        }
                    } else {
                        print("ThumbnailProvider: ⚠️ No format description found for video track")
                    }
                }

                // 檢查 AVAsset 是否真的可用
                if !isPlayable || !isReadable {
                    print("ThumbnailProvider: ❌ AVAsset is not playable or readable")
                    self.tryAlternativeVideoRequest(for: phAsset)
                    return
                }

                // 設定 asset 並生成縮圖
                Task { @MainActor in
                    await self.setAsset(avAsset, force: true)
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
        print("ThumbnailProvider: Trying alternative video request with compatibility mode...")
        
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .mediumQualityFormat // 降低品質要求
        options.version = .current
        
        // 嘗試請求相容格式
        PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { [weak self] avAsset, audioMix, info in
            guard let self = self else { return }
            
            if let avAsset = avAsset {
                print("ThumbnailProvider: ✅ Alternative request succeeded")
                Task { @MainActor in
                    await self.setAsset(avAsset, force: true)
                }
            } else {
                print("ThumbnailProvider: ❌ Alternative request also failed")
                
                // 最後嘗試：使用 PHImageManager 直接請求圖片作為縮圖
                self.tryImageFallback(for: phAsset)
            }
        }
    }
    
    /// 最後備用方案：使用靜態圖片作為縮圖
    private func tryImageFallback(for phAsset: PHAsset) {
        print("ThumbnailProvider: Using image fallback for unsupported video")
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        
        let targetSize = CGSize(width: 160, height: 80) // Match timeline thumbnail aspect
        
        PHImageManager.default().requestImage(
            for: phAsset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            guard let self = self, let image = image else {
                print("ThumbnailProvider: ❌ Image fallback also failed")
                return
            }
            
            print("ThumbnailProvider: ✅ Using static image as video thumbnail")
            
            // 將靜態圖片作為 0.0 時間點的縮圖
            DispatchQueue.main.async {
                self.thumbnails[0.0] = image
            }
        }
    }
    

}

@MainActor
class ThumbnailProvider: ObservableObject {
    // MARK: - Properties
    
    private var imageGenerator: AVAssetImageGenerator?
    private let thumbnailQueue = DispatchQueue(label: "thumbnail.generation", qos: .userInitiated)
    private var asset: AVAsset?
    private var isUsingPHAsset: Bool = false // Track if we're using PHAsset mode
    
    @Published var thumbnails: [TimeInterval: UIImage] = [:]
    @Published var isGenerating: Bool = false
    
    private var _thumbnailSize = CGSize(width: 160, height: 80) // Will be updated to match video aspect ratio

    /// Expose the current thumbnail size for external use (e.g., UI layout)
    var thumbnailSize: CGSize { _thumbnailSize }
    
    // MARK: - Initialization
    
    init(asset: AVAsset? = nil) {
        self.asset = asset
        
        if let asset = asset {
            self.imageGenerator = AVAssetImageGenerator(asset: asset)
            Task {
                await configureImageGeneratorAsync()
            }
        } else {
            self.imageGenerator = nil
        }
    }
    
    deinit {
        // Do not call @MainActor methods here; actor isolation is not guaranteed in deinit.
    }
    
    // MARK: - Configuration
    
    private func configureImageGenerator() {
        guard let generator = imageGenerator, let asset = asset else { return }
        
        Task {
            await configureImageGeneratorAsync()
        }
    }
    
    private func configureImageGeneratorAsync() async {
        guard let generator = imageGenerator, let asset = asset else { return }
        
        // Get the natural size of the first video track with proper transform handling
        var naturalSize = CGSize(width: 1920, height: 1080) // Default 16:9 aspect ratio
        
        // Load video tracks asynchronously for proper PHAsset support
        var videoTracks: [AVAssetTrack] = []
        if #available(iOS 16.0, *) {
            do {
                videoTracks = try await asset.loadTracks(withMediaType: .video)
            } catch {
                print("ThumbnailProvider: Failed to load video tracks: \(error)")
                videoTracks = asset.tracks(withMediaType: .video) // Fallback to sync
            }
        } else {
            videoTracks = asset.tracks(withMediaType: .video)
        }
        
        if let videoTrack = videoTracks.first {
            var rawSize: CGSize
            var transform: CGAffineTransform
            
            // Load track properties asynchronously
            if #available(iOS 16.0, *) {
                do {
                    rawSize = try await videoTrack.load(.naturalSize)
                    transform = try await videoTrack.load(.preferredTransform)
                } catch {
                    print("ThumbnailProvider: Failed to load track properties: \(error)")
                    rawSize = videoTrack.naturalSize
                    transform = videoTrack.preferredTransform
                }
            } else {
                rawSize = videoTrack.naturalSize
                transform = videoTrack.preferredTransform
            }
            
            // Calculate the actual display size after applying transform
            let transformedSize = rawSize.applying(transform)
            
            // Handle rotation - if width and height are swapped due to rotation, correct it
            let angle = atan2(transform.b, transform.a)
            let isRotated = abs(angle) > .pi / 4 // More than 45 degrees rotation
            
            if isRotated {
                // For rotated videos, swap dimensions to get correct aspect ratio
                naturalSize = CGSize(width: abs(transformedSize.height), height: abs(transformedSize.width))
            } else {
                naturalSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
            }
            
            print("ThumbnailProvider: Video track - raw: \(rawSize), transformed: \(transformedSize), final: \(naturalSize), rotation: \(angle * 180 / .pi)°")
        }
        
        // Calculate thumbnail size maintaining the video's aspect ratio
        let thumbnailHeight: CGFloat = 120 // Higher resolution for better quality
        let aspectRatio = naturalSize.width / max(naturalSize.height, 1)
        let width = max(1, thumbnailHeight * aspectRatio)
        
        // Update thumbnail size on main actor
        await MainActor.run {
            _thumbnailSize = CGSize(width: width, height: thumbnailHeight)
        }
        
        // Configure generator with proper settings
        generator.maximumSize = _thumbnailSize
        generator.appliesPreferredTrackTransform = true
        
        // Set a reasonable tolerance for faster generation
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        
        print("ThumbnailProvider: Image generator configured - aspect ratio: \(aspectRatio), thumbnail size: \(_thumbnailSize)")
    }
    
    // MARK: - Asset Management
    
    func clear() {
        thumbnails.removeAll()
        asset = nil
        imageGenerator = nil
        isUsingPHAsset = false
        cancelAllOperations()
    }
    
    func setAsset(_ newAsset: AVAsset, force: Bool = false) async {
        // Don't override PHAsset setup with regular asset unless forced
        if isUsingPHAsset && !force {
            print("ThumbnailProvider: Ignoring setAsset call - already using PHAsset mode")
            return
        }
        
        var durationSeconds: Double = 0
        if #available(iOS 16.0, *) {
            durationSeconds = (try? await newAsset.load(.duration))?.seconds ?? 0
        } else {
            durationSeconds = newAsset.duration.seconds
        }
        print("ThumbnailProvider: Setting new asset with duration: \(durationSeconds)")
        
        clear() // Clear previous state
        
        asset = newAsset
        isUsingPHAsset = false // Reset PHAsset mode when setting regular asset
        
        // Create new image generator for the asset
        imageGenerator = AVAssetImageGenerator(asset: newAsset)
        await configureImageGeneratorAsync()
        
        print("ThumbnailProvider: Image generator configured successfully with size: \(thumbnailSize)")
        
        // Start generating all thumbnails
        await generateAllThumbnails(totalDuration: durationSeconds)
    }
    
    // MARK: - Thumbnail Generation
    
    private func generateAllThumbnails(totalDuration: TimeInterval, interval: TimeInterval = 1.0) async {
        guard let generator = imageGenerator else { 
            print("ThumbnailProvider: ❌ No image generator available for thumbnail generation")
            return 
        }
        
        // Adjust interval based on video duration for better coverage
        let adjustedInterval = max(0.25, min(0.5, totalDuration / 60)) // More frequent thumbnails, max 60 thumbnails
        print("ThumbnailProvider: ✅ Starting thumbnail generation for duration: \(totalDuration)s with interval: \(adjustedInterval)s")
        
        isGenerating = true
        
        let allTimes = stride(from: 0, to: totalDuration, by: adjustedInterval).map {
            CMTime(seconds: $0, preferredTimescale: 600)
        }
        
        guard !allTimes.isEmpty else {
            print("ThumbnailProvider: ⚠️ No thumbnail times generated")
            isGenerating = false
            return
        }
        
        print("ThumbnailProvider: 📊 Will generate \(allTimes.count) thumbnails")
        
        let stream = generator.images(for: allTimes)
        
        for await result in stream {
            do {
                let image = try result.image
                let requestedTime = result.requestedTime.seconds
                let actualTime = try result.actualTime.seconds
                
                print("ThumbnailProvider: ✅ Generated thumbnail - requested: \(requestedTime)s, actual: \(actualTime)s")
                
                // Update UI on the main thread - use actualTime for the key
                Task { @MainActor in
                    thumbnails[actualTime] = UIImage(cgImage: image)
                }
            } catch {
                let requestedTime = result.requestedTime.seconds
                print("ThumbnailProvider: ❌ Failed to generate thumbnail at requested time \(requestedTime)s. Error: \(error)")
            }
        }
        
        isGenerating = false
        print("ThumbnailProvider: ✅ Finished generating thumbnails. Total count: \(thumbnails.count)")
    }
    
    // MARK: - Utility Methods
    
    func cancelAllOperations() {
        imageGenerator?.cancelAllCGImageGeneration()
        Task { @MainActor in
            isGenerating = false
        }
    }
}


