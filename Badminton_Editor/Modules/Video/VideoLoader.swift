import Foundation
import AVFoundation
import Photos
import VideoToolbox
import SwiftUI

class VideoLoader {
    static func loadVideoAsset(
        asset: AVAsset,
        player: AVPlayer,
        setCurrentTime: @escaping (TimeInterval) -> Void,
        setTotalDuration: @escaping (TimeInterval) -> Void,
        setMarkers: @escaping ([RallyMarker]) -> Void,
        setShowLoadingAnimation: @escaping (Bool) -> Void,
        applyInstantGPUOptimizations: @escaping (AVPlayerItem, VideoCodecInfo) async -> Void,
        configureDetailedGPUAcceleration: @escaping (AVPlayerItem, AVAsset, VideoCodecInfo) async -> Void,
        configureAudioSession: @escaping () async -> Void,
        detectVideoCodecFormat: @escaping (AVAsset) async -> VideoCodecInfo,
        loadDurationOptimized: @escaping (AVAsset) async -> TimeInterval
    ) async {
        print("VideoLoader: 開始極速載入影片資源...")
        let playerItem = AVPlayerItem(asset: asset)
        await MainActor.run {
            player.replaceCurrentItem(with: playerItem)
            player.isMuted = false
            player.volume = 1.0
            setCurrentTime(0.0)
            setMarkers([])
            print("VideoLoader: 播放器已立即設置，開始預載")
        }
        await MainActor.run {
            setShowLoadingAnimation(true)
        }
        async let audioSessionTask = configureAudioSession()
        async let codecInfoTask = detectVideoCodecFormat(asset)
        async let durationTask = loadDurationOptimized(asset)
        let videoCodecInfo = await codecInfoTask
        print("VideoLoader: 檢測到影片格式: \(videoCodecInfo.codecName)")
        await applyInstantGPUOptimizations(playerItem, videoCodecInfo)
        let duration = await durationTask
        await MainActor.run {
            setTotalDuration(duration)
            print("VideoLoader: 極速載入完成 - 時長: \(duration)秒")
        }
        await audioSessionTask
        Task {
            await configureDetailedGPUAcceleration(playerItem, asset, videoCodecInfo)
        }
        try? await Task.sleep(nanoseconds: 25_000_000)
        await MainActor.run {
            setShowLoadingAnimation(false)
            print("VideoLoader: 極速載入動畫隱藏，總耗時 < 0.05秒")
        }
    }
    static func handlePHAssetSelection(
        phAsset: PHAsset,
        thumbnailCache: ThumbnailCache,
        setCurrentPHAsset: @escaping (PHAsset?) -> Void,
        loadVideoAsset: @escaping (AVAsset) async -> Void
    ) async {
        setCurrentPHAsset(phAsset)
        await MainActor.run { thumbnailCache.setPHAsset(phAsset) }
        await requestAVAssetFromPHAsset(phAsset, loadVideoAsset: loadVideoAsset)
    }

    static func requestAVAssetFromPHAsset(
        _ phAsset: PHAsset,
        loadVideoAsset: @escaping (AVAsset) async -> Void
    ) async {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { (avAsset, _, _) in
                DispatchQueue.main.async {
                    if let asset = avAsset {
                        Task { await loadVideoAsset(asset) }
                    }
                    continuation.resume()
                }
            }
        }
    }

    static func handleVideoSelection(
        localURL: URL,
        setCurrentVideoURL: @escaping (URL?) -> Void,
        loadVideoAsset: @escaping (AVAsset) async -> Void
    ) async {
        setCurrentVideoURL(localURL)
        let asset = AVURLAsset(url: localURL)
        await loadVideoAsset(asset)
    }
}
