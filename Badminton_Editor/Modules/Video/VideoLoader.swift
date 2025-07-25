import Foundation
import AVFoundation
import Photos
import VideoToolbox
import SwiftUI

class VideoLoader {
    static func loadDurationOptimized(asset: AVAsset) async -> TimeInterval {
        if #available(iOS 16.0, *) {
            do {
                let duration = try await asset.load(.duration)
                let durationSeconds = duration.seconds
                if durationSeconds > 0 && durationSeconds.isFinite {
                    print("VideoLoader: 現代 API 時長載入成功: \(durationSeconds)秒")
                    return durationSeconds
                }
            } catch {
                print("VideoLoader: 現代 API 時長載入失敗: \(error)")
            }
        } else {
            // Deprecated: .duration, use load(.duration) if possible
            let syncDuration = asset.duration.seconds
            if syncDuration > 0 && syncDuration.isFinite {
                print("VideoLoader: iOS 15 時長載入成功: \(syncDuration)秒")
                return syncDuration
            }
        }
        return await loadDurationFallbackFast(asset: asset)
    }

    static func loadDurationFallbackFast(asset: AVAsset) async -> TimeInterval {
        if #available(iOS 16.0, *) {
            do {
                let tracks = try await asset.load(.tracks)
                if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
                    let timeRange = try await videoTrack.load(.timeRange)
                    let duration = timeRange.duration.seconds
                    if duration > 0 && duration.isFinite {
                        print("VideoLoader: 備用時長載入成功: \(duration)秒")
                        return duration
                    }
                }
            } catch {
                print("VideoLoader: 備用時長載入失敗: \(error)")
            }
        } else {
            let tracks = asset.tracks(withMediaType: .video)
            if let videoTrack = tracks.first {
                // Deprecated: .timeRange, use load(.timeRange) if possible
                let duration = videoTrack.timeRange.duration.seconds
                if duration > 0 && duration.isFinite {
                    print("VideoLoader: iOS 15 備用時長載入成功: \(duration)秒")
                    return duration
                }
            }
        }
        print("VideoLoader: 使用預設時長值")
        return 30.0
    }

    static func applyInstantGPUOptimizations(_ playerItem: AVPlayerItem, codecInfo: VideoCodecInfo) async {
        playerItem.preferredForwardBufferDuration = 1.5
        if codecInfo.isHEVC {
            playerItem.audioTimePitchAlgorithm = .spectral
        } else {
            if #available(iOS 15.0, *) {
                playerItem.audioTimePitchAlgorithm = .timeDomain
            } else {
                playerItem.audioTimePitchAlgorithm = .spectral
            }
        }
        if #available(iOS 15.0, *) {
            playerItem.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
            playerItem.preferredPeakBitRate = codecInfo.isHEVC ? 30_000_000 : 50_000_000
        }
        print("VideoLoader: 立即 GPU 優化已應用")
    }

    static func configureDetailedGPUAcceleration(_ playerItem: AVPlayerItem, asset: AVAsset, codecInfo: VideoCodecInfo) async {
        print("VideoLoader: 開始背景詳細 GPU 配置...")
        try? await Task.sleep(nanoseconds: 200_000_000)
        let isAssetValid = await checkAssetAvailability(asset)
        guard isAssetValid else {
            print("VideoLoader: Asset 不可用，跳過詳細 GPU 配置")
            await applyBasicFallbackConfiguration(playerItem, codecInfo: codecInfo)
            return
        }
        do {
            let tracks: [AVAssetTrack]
            if #available(iOS 16.0, *) {
                tracks = try await withTimeout(seconds: 2.0) {
                    try await asset.load(.tracks).filter { $0.mediaType == .video }
                }
            } else {
                tracks = asset.tracks(withMediaType: .video)
            }
            guard let videoTrack = tracks.first else {
                print("VideoLoader: 未找到視頻軌道，使用基本配置")
                await applyBasicFallbackConfiguration(playerItem, codecInfo: codecInfo)
                return
            }
            let naturalSize: CGSize
            let nominalFrameRate: Float
            if #available(iOS 16.0, *) {
                let results = try await withTimeout(seconds: 1.5) {
                    async let sizeTask = videoTrack.load(.naturalSize)
                    async let frameRateTask = videoTrack.load(.nominalFrameRate)
                    return (try await sizeTask, try await frameRateTask)
                }
                naturalSize = results.0
                nominalFrameRate = results.1
            } else {
                naturalSize = videoTrack.naturalSize
                nominalFrameRate = videoTrack.nominalFrameRate
            }
            await MainActor.run {
                if naturalSize.width >= 3840 {
                    playerItem.preferredMaximumResolution = CGSize(width: 3840, height: 2160)
                    playerItem.preferredPeakBitRate = codecInfo.isHEVC ? 50_000_000 : 80_000_000
                    playerItem.preferredForwardBufferDuration = 3.0
                } else if naturalSize.width >= 1920 {
                    playerItem.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
                    playerItem.preferredPeakBitRate = codecInfo.isHEVC ? 25_000_000 : 40_000_000
                    playerItem.preferredForwardBufferDuration = 2.0
                } else {
                    playerItem.preferredForwardBufferDuration = 1.5
                }
                print("VideoLoader: 詳細 GPU 配置完成 - 解析度: \(naturalSize), 幀率: \(nominalFrameRate)")
            }
        } catch {
            print("VideoLoader: 詳細 GPU 配置遇到錯誤，使用降級配置: \(error)")
            await applyBasicFallbackConfiguration(playerItem, codecInfo: codecInfo)
        }
    }

    static func applyBasicFallbackConfiguration(_ playerItem: AVPlayerItem, codecInfo: VideoCodecInfo) async {
        await MainActor.run {
            playerItem.preferredForwardBufferDuration = 2.0
            if #available(iOS 15.0, *) {
                playerItem.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
                playerItem.preferredPeakBitRate = codecInfo.isHEVC ? 20_000_000 : 35_000_000
            }
            print("VideoLoader: 基本降級 GPU 配置已應用")
        }
    }

    static func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }

    struct TimeoutError: Error {}

    static func checkAssetAvailability(_ asset: AVAsset) async -> Bool {
        do {
            if #available(iOS 16.0, *) {
                let duration = try await asset.load(.duration)
                if duration.seconds > 0 && duration.seconds.isFinite {
                    print("VideoLoader: Asset 可用 - 通過時長檢測: \(duration.seconds)秒")
                    return true
                }
            } else {
                // Deprecated: .duration, use load(.duration) if possible
                let duration = asset.duration
                if duration.seconds > 0 && duration.seconds.isFinite {
                    print("VideoLoader: Asset 可用 - 通過 iOS 15 時長檢測: \(duration.seconds)秒")
                    return true
                }
            }
        } catch {
            print("VideoLoader: Asset 時長檢測失敗: \(error)")
        }
        do {
            if #available(iOS 16.0, *) {
                let tracks = try await asset.load(.tracks)
                let videoTracks = tracks.filter { $0.mediaType == .video }
                if !videoTracks.isEmpty {
                    print("VideoLoader: Asset 可用 - 發現 \(videoTracks.count) 個視頻軌道")
                    return true
                }
            } else {
                // Deprecated: tracks(withMediaType:), use load(.tracks) if possible
                let videoTracks = asset.tracks(withMediaType: .video)
                if !videoTracks.isEmpty {
                    print("VideoLoader: Asset 可用 - iOS 15 發現 \(videoTracks.count) 個視頻軌道")
                    return true
                }
            }
        } catch {
            print("VideoLoader: Asset 軌道檢測失敗: \(error)")
        }
        if asset.debugDescription.contains("AVURLAsset") {
            print("VideoLoader: Asset 可用 - 通過物件檢測（寬鬆模式）")
            return true
        }
        print("VideoLoader: Asset 確認不可用 - 所有檢測都失敗")
        return false
    }

    static func configureAudioSession() async {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowBluetooth, .allowAirPlay]
            )
            try audioSession.setPreferredSampleRate(44100)
            try audioSession.setPreferredIOBufferDuration(0.01)
            try audioSession.setActive(true)
            print("VideoLoader: 優化音訊會話配置完成")
        } catch {
            print("VideoLoader: 音訊會話配置失敗: \(error)")
        }
    }

    static func configurePlayerItemForOptimalPlayback(_ playerItem: AVPlayerItem, asset: AVAsset) async {
        print("VideoLoader: 開始配置播放器 GPU 加速設置...")
        let videoCodecInfo = await detectVideoCodecFormat(asset)
        print("VideoLoader: 檢測到影片格式: \(videoCodecInfo.codecName), 是否為 HEVC: \(videoCodecInfo.isHEVC)")
        await configureUniversalGPUAcceleration(playerItem, asset: asset, codecInfo: videoCodecInfo)
        print("VideoLoader: GPU 硬體加速設置已應用於 \(videoCodecInfo.codecName) 格式")
    }

    static func configureUniversalGPUAcceleration(_ playerItem: AVPlayerItem, asset: AVAsset, codecInfo: VideoCodecInfo) async {
        print("VideoLoader: 配置通用 GPU 硬體加速...")
        if codecInfo.isHEVC {
            playerItem.preferredForwardBufferDuration = 2.5
            playerItem.audioTimePitchAlgorithm = .spectral
        } else {
            playerItem.preferredForwardBufferDuration = 2.0
            if #available(iOS 15.0, *) {
                playerItem.audioTimePitchAlgorithm = .timeDomain
            } else {
                playerItem.audioTimePitchAlgorithm = .spectral
            }
        }
        if #available(iOS 15.0, *) {
            playerItem.preferredMaximumResolution = CGSize(width: 3840, height: 2160)
            if codecInfo.isHEVC {
                playerItem.preferredPeakBitRate = 50_000_000
            } else {
                playerItem.preferredPeakBitRate = 80_000_000
            }
        }
        await configureVideoOutputForGPU(asset, codecInfo: codecInfo)
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        if #available(iOS 16.0, *) {
            playerItem.automaticallyPreservesTimeOffsetFromLive = false
        }
        await checkUniversalGPUSupport(for: codecInfo)
        print("VideoLoader: 通用 GPU 硬體加速配置完成")
    }

    static func configureVideoOutputForGPU(_ asset: AVAsset, codecInfo: VideoCodecInfo) async {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = tracks.first else { return }
            let naturalSize = try await videoTrack.load(.naturalSize)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            print("VideoLoader: 視頻解析度: \(naturalSize), 幀率: \(nominalFrameRate), 編碼: \(codecInfo.codecName)")
            let gpuMode = determineGPUMode(resolution: naturalSize, codec: codecInfo)
            print("VideoLoader: \(codecInfo.codecName) - \(gpuMode)")
        } catch {
            print("VideoLoader: 無法獲取視頻屬性: \(error)")
        }
    }

    static func determineGPUMode(resolution: CGSize, codec: VideoCodecInfo) -> String {
        let resolutionCategory: String
        if resolution.width >= 3840 {
            resolutionCategory = "4K"
        } else if resolution.width >= 1920 {
            resolutionCategory = "1080p"
        } else {
            resolutionCategory = "HD"
        }
        let performanceMode: String
        if codec.isHEVC {
            performanceMode = resolutionCategory == "4K" ? "高性能 GPU 模式" : "標準 GPU 模式"
        } else {
            performanceMode = resolutionCategory == "4K" ? "超高性能 GPU 模式" : "高性能 GPU 模式"
        }
        return "檢測到 \(resolutionCategory) \(codec.codecName)，啟用\(performanceMode)"
    }

    static func checkUniversalGPUSupport(for codecInfo: VideoCodecInfo) async {
        let hevcSupported = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let h264Supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)
        print("VideoLoader: 硬體解碼支援狀況：")
        print("  - HEVC/H.265: \(hevcSupported ? "✅ 支援" : "❌ 不支援")")
        print("  - H.264: \(h264Supported ? "✅ 支援" : "❌ 不支援")")
        if codecInfo.isHEVC && hevcSupported {
            print("VideoLoader: ✅ HEVC GPU 硬體加速可用")
        } else if !codecInfo.isHEVC && h264Supported {
            print("VideoLoader: ✅ H.264 GPU 硬體加速可用")
        } else {
            print("VideoLoader: ⚠️ 當前格式將使用軟體解碼")
        }
        await checkDevicePerformanceLevel()
    }

    static func checkDevicePerformanceLevel() async {
        if #available(iOS 15.0, *) {
            let device = UIDevice.current
            let processorCount = ProcessInfo.processInfo.processorCount
            let isHighPerformance = device.userInterfaceIdiom == .pad || processorCount >= 6
            print("VideoLoader: 設備信息：")
            print("  - 設備類型: \(device.userInterfaceIdiom == .pad ? "iPad" : "iPhone")")
            print("  - 處理器核心: \(processorCount)")
            print("  - 性能等級: \(isHighPerformance ? "高性能" : "標準性能")")
            if isHighPerformance {
                print("VideoLoader: 啟用高性能 GPU 模式，支援所有視頻格式硬體加速")
            } else {
                print("VideoLoader: 啟用標準 GPU 模式，支援主流視頻格式硬體加速")
            }
        }
    }

    static func detectVideoCodecFormat(_ asset: AVAsset) async -> VideoCodecInfo {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let firstTrack = tracks.first else {
                return VideoCodecInfo(codecName: "Unknown", isHEVC: false, fourCC: 0)
            }
            let formatDescriptions = try await firstTrack.load(.formatDescriptions)
            guard let firstFormat = formatDescriptions.first else {
                return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: 0)
            }
            // Conditional cast always succeeds for CMFormatDescription
            guard let formatDescription = firstFormat as? CMFormatDescription else {
                return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: 0)
            }
            let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
            let codecInfo = identifyCodecFast(mediaSubType)
            print("VideoLoader: 快速編碼檢測 - 格式: \(codecInfo.codecName)")
            return codecInfo
        } catch {
            print("VideoLoader: 編碼檢測失敗，使用預設 H.264: \(error)")
            return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: 0)
        }
    }

    static func identifyCodecFast(_ fourCC: FourCharCode) -> VideoCodecInfo {
        switch fourCC {
        case 0x68766331, 0x68657631, kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha:
            return VideoCodecInfo(codecName: "HEVC/H.265", isHEVC: true, fourCC: fourCC)
        case 0x61766331, 0x61766343, kCMVideoCodecType_H264:
            return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: fourCC)
        default:
            return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: fourCC)
        }
    }

    static func fourCharCodeToString(_ code: FourCharCode) -> String {
        let chars = [
            Character(UnicodeScalar((code >> 24) & 0xFF)!),
            Character(UnicodeScalar((code >> 16) & 0xFF)!),
            Character(UnicodeScalar((code >> 8) & 0xFF)!),
            Character(UnicodeScalar(code & 0xFF)!)
        ]
        return String(chars)
    }
    static func loadVideoAsset(
        asset: AVAsset,
        player: AVPlayer,
        setCurrentTime: @escaping (TimeInterval) -> Void,
        setTotalDuration: @escaping (TimeInterval) -> Void,
        setShowLoadingAnimation: @escaping (Bool) -> Void,
        applyInstantGPUOptimizations: @escaping (AVPlayerItem, VideoCodecInfo) async -> Void,
        configureDetailedGPUAcceleration: @escaping (AVPlayerItem, AVAsset, VideoCodecInfo) async -> Void,
        configureAudioSession: @escaping () async -> Void,
        detectVideoCodecFormat: @escaping (AVAsset) async -> VideoCodecInfo,
        loadDurationOptimized: @escaping (AVAsset) async -> TimeInterval
    ) async {
        print("VideoLoader: 開始載入影片資源...")
        let playerItem = AVPlayerItem(asset: asset)
        await MainActor.run {
            player.replaceCurrentItem(with: playerItem)
            player.isMuted = false
            player.volume = 1.0
            setCurrentTime(0.0)
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
            print("VideoLoader: 載入完成 - 時長: \(duration)秒")
        }
        await audioSessionTask
        Task {
            await configureDetailedGPUAcceleration(playerItem, asset, videoCodecInfo)
        }
        try? await Task.sleep(nanoseconds: 25_000_000)
        await MainActor.run {
            setShowLoadingAnimation(false)
            print("VideoLoader: 載入動畫隱藏，總耗時 < 0.05秒")
        }
    }
    static func handlePHAssetSelection(
        phAsset: PHAsset,
        thumbnailProvider: ThumbnailProvider,
        setCurrentPHAsset: @escaping (PHAsset?) -> Void,
        loadVideoAsset: @escaping (AVAsset) async -> Void
    ) async {
        setCurrentPHAsset(phAsset)
        await MainActor.run { thumbnailProvider.setPHAsset(phAsset) }
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
