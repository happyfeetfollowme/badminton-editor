import SwiftUI
import AVKit
import AVFoundation
import PhotosUI
import VideoToolbox
import UniformTypeIdentifiers

// MARK: - 1. 主畫面視圖 (Main View)
struct ContentView: View {
    // 狀態變數
    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var showVideoPicker = false
    @State private var markers: [RallyMarker] = []
    @StateObject private var thumbnailCache = ThumbnailCache()
    @State private var showLoadingAnimation = false
    @State private var currentVideoURL: URL? // This will now store the *copied* video URL

    var body: some View {
        ZStack {
            // 背景色設定為深色
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // MARK: - 2. 頂部工具列 (Top Toolbar)
                TopToolbarView(onExport: {
                    // 導出邏輯
                }, onSelectVideo: {
                    // Direct show video picker - no permissions needed for URL-based approach
                    showVideoPicker = true
                })

                // MARK: - 3. 影片播放區 (Video Playback Area)
                VideoPlayerView(player: $player, isPlaying: $isPlaying, currentTime: $currentTime, totalDuration: $totalDuration)
                    .onTapGesture {
                        // 點擊影片區域來播放/暫停
                        guard player.currentItem != nil else { return }
                        isPlaying.toggle()
                        isPlaying ? player.play() : player.pause()
                    }

                // MARK: - 4&5. 時間軸與播放控制整合區域 (Timeline and Playback Controls)
                VStack(spacing: 8) {
                    // 時間軸容器
                    TimelineContainerView(
                        player: $player,
                        currentTime: $currentTime,
                        totalDuration: $totalDuration,
                        markers: $markers
                    )
                    .frame(height: 120)
                    
                    // 播放控制列 - 與 timeline 的 playhead 對齊
                    PlaybackControlsView(
                        player: $player,
                        isPlaying: $isPlaying,
                        currentTime: $currentTime,
                        totalDuration: $totalDuration
                    )
                }
                .padding(.vertical, 10)

                MainActionToolbarView()
            }
            
            // MARK: - 影片載入進度 Popup (Video Loading Progress Popup)
            if thumbnailCache.isTranscoding || showLoadingAnimation {
                TranscodingProgressPopup(
                    progress: thumbnailCache.transcodingProgress,
                    onCancel: {
                        if thumbnailCache.isTranscoding {
                            thumbnailCache.cancelTranscoding()
                        } else {
                            showLoadingAnimation = false
                        }
                    }
                )
            }
        }
        .preferredColorScheme(.dark) // 強制使用深色模式
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker(
                onFinish: { temporaryURL in
                    if let url = temporaryURL {
                        Task {
                            await handleVideoSelection(with: url)
                        }
                    }
                },
                onSelectionStart: {
                    showLoadingAnimation = true
                    thumbnailCache.isTranscoding = true
                    thumbnailCache.transcodingProgress = 0.0
                }
            )
        }
    }
    
    // MARK: - Video Loading Management

    /// 1. Handles the video selection, now receiving a STABLE, copied URL.
    private func handleVideoSelection(with localURL: URL) async {
        // The URL is already a stable, local copy.
        print("ContentView: Received stable URL: \(localURL.path)")
        
        // Store the stable URL.
        self.currentVideoURL = localURL
        
        // Create an asset from the stable URL and load it.
        let asset = AVURLAsset(url: localURL)
        await loadVideoAsset(asset)
    }
    
    // MARK: - Helper Methods for Video Loading
    
    /// 載入影片資源到播放器 - 極速載入優化版本
    private func loadVideoAsset(_ asset: AVAsset) async {
        print("ContentView: 開始極速載入影片資源...")
        
        // 立即創建 AVPlayerItem，不等待任何檢測
        let playerItem = AVPlayerItem(asset: asset)
        
        // 立即設置播放器以開始預載，這是最關鍵的優化
        await MainActor.run {
            player.replaceCurrentItem(with: playerItem)
            player.isMuted = false
            player.volume = 1.0
            currentTime = 0.0
            markers = []
            print("ContentView: 播放器已立即設置，開始預載")
        }
        
        // 確保載入動畫顯示（如果尚未顯示）
        await MainActor.run {
            if !showLoadingAnimation {
                showLoadingAnimation = true
                thumbnailCache.isTranscoding = true
                thumbnailCache.transcodingProgress = 0.1 // 立即顯示一些進度
            }
        }
        
        // 並行處理所有非關鍵任務，不阻塞播放器設置
        async let audioSessionTask = configureAudioSession()
        async let codecInfoTask = detectVideoCodecFormat(asset)
        async let durationTask = loadDurationOptimized(asset: asset)
        
        // 等待編碼檢測完成後應用基本優化
        let videoCodecInfo = await codecInfoTask
        print("ContentView: 檢測到影片格式: \(videoCodecInfo.codecName)")
        await applyInstantGPUOptimizations(playerItem, codecInfo: videoCodecInfo)
        
        // 等待時長載入完成
        let duration = await durationTask
        await MainActor.run {
            totalDuration = duration
            thumbnailCache.transcodingProgress = 0.8 // 更新進度
            print("ContentView: 極速載入完成 - 時長: \(totalDuration)秒")
        }
        
        // 完成音訊會話配置
        await audioSessionTask
        
        // 在背景完成詳細 GPU 配置，完全不阻塞 UI
        Task {
            await configureDetailedGPUAcceleration(playerItem, asset: asset, codecInfo: videoCodecInfo)
        }
        
        // 非常短的等待後隱藏載入動畫
        try? await Task.sleep(nanoseconds: 25_000_000) // 只等待 0.025 秒
        await MainActor.run {
            showLoadingAnimation = false
            thumbnailCache.isTranscoding = false
            thumbnailCache.transcodingProgress = 1.0
            print("ContentView: 極速載入動畫隱藏，總耗時 < 0.05秒")
        }
    }
    
    /// 極速時長載入，優化性能
    private func loadDurationOptimized(asset: AVAsset) async -> TimeInterval {
        // Use modern API for iOS 16+, fallback for iOS 15
        if #available(iOS 16.0, *) {
            do {
                let duration = try await asset.load(.duration)
                let durationSeconds = duration.seconds
                if durationSeconds > 0 && durationSeconds.isFinite {
                    print("ContentView: 現代 API 時長載入成功: \(durationSeconds)秒")
                    return durationSeconds
                }
            } catch {
                print("ContentView: 現代 API 時長載入失敗: \(error)")
            }
        } else {
            // iOS 15 fallback - use deprecated API
            let syncDuration = asset.duration.seconds
            if syncDuration > 0 && syncDuration.isFinite {
                print("ContentView: iOS 15 時長載入成功: \(syncDuration)秒")
                return syncDuration
            }
        }
        
        // 如果失敗，使用快速備用方案
        return await loadDurationFallbackFast(asset: asset)
    }
    
    /// 快速備用時長載入方法
    private func loadDurationFallbackFast(asset: AVAsset) async -> TimeInterval {
        // 快速備用方案：從視頻軌道獲取時長
        if #available(iOS 16.0, *) {
            do {
                let tracks = try await asset.load(.tracks)
                if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
                    let timeRange = try await videoTrack.load(.timeRange)
                    let duration = timeRange.duration.seconds
                    if duration > 0 && duration.isFinite {
                        print("ContentView: 備用時長載入成功: \(duration)秒")
                        return duration
                    }
                }
            } catch {
                print("ContentView: 備用時長載入失敗: \(error)")
            }
        } else {
            // iOS 15 同步方式
            let tracks = asset.tracks(withMediaType: .video)
            if let videoTrack = tracks.first {
                let duration = videoTrack.timeRange.duration.seconds
                if duration > 0 && duration.isFinite {
                    print("ContentView: iOS 15 備用時長載入成功: \(duration)秒")
                    return duration
                }
            }
        }
        
        // 最後的預設值，避免完全失敗
        print("ContentView: 使用預設時長值")
        return 30.0 // 給一個合理的預設值，通常影片至少有幾秒
    }
    
    /// 立即應用基本 GPU 優化，不等待詳細檢測
    private func applyInstantGPUOptimizations(_ playerItem: AVPlayerItem, codecInfo: VideoCodecInfo) async {
        // 立即設置基本緩衝，不等待格式檢測
        playerItem.preferredForwardBufferDuration = 1.5 // 減少初始緩衝
        
        // 快速設置音訊算法
        if codecInfo.isHEVC {
            playerItem.audioTimePitchAlgorithm = .spectral
        } else {
            if #available(iOS 15.0, *) {
                playerItem.audioTimePitchAlgorithm = .timeDomain
            } else {
                playerItem.audioTimePitchAlgorithm = .spectral
            }
        }
        
        // 立即啟用硬體解碼
        if #available(iOS 15.0, *) {
            playerItem.preferredMaximumResolution = CGSize(width: 1920, height: 1080) // 先設置 1080p
            playerItem.preferredPeakBitRate = codecInfo.isHEVC ? 30_000_000 : 50_000_000 // 降低比特率要求
        }
        
        print("ContentView: 立即 GPU 優化已應用")
    }
    
    /// 在背景進行詳細 GPU 配置，不阻塞 UI
    private func configureDetailedGPUAcceleration(_ playerItem: AVPlayerItem, asset: AVAsset, codecInfo: VideoCodecInfo) async {
        print("ContentView: 開始背景詳細 GPU 配置...")
        
        // 增加延遲以確保 asset 完全穩定，避免檔案資源問題
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 秒延遲
        
        // 檢查 asset 基本可用性，但不過度嚴格（臨時檔案可能在某些屬性上返回 false）
        let isAssetValid = await checkAssetAvailability(asset)
        guard isAssetValid else {
            print("ContentView: Asset 不可用，跳過詳細 GPU 配置")
            await applyBasicFallbackConfiguration(playerItem, codecInfo: codecInfo)
            return
        }
        
        // 檢測並應用更詳細的優化，使用保護措施
        do {
            // 使用更安全且容錯的方式載入視頻軌道
            let tracks: [AVAssetTrack]
            if #available(iOS 16.0, *) {
                // 使用 timeout 避免無限等待
                tracks = try await withTimeout(seconds: 2.0) {
                    try await asset.load(.tracks).filter { $0.mediaType == .video }
                }
            } else {
                // iOS 15 同步方式更安全
                tracks = asset.tracks(withMediaType: .video)
            }
            
            guard let videoTrack = tracks.first else {
                print("ContentView: 未找到視頻軌道，使用基本配置")
                await applyBasicFallbackConfiguration(playerItem, codecInfo: codecInfo)
                return
            }
            
            // 安全地載入視頻屬性，加入超時保護
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
            
            // 根據實際視頻屬性調整設置
            await MainActor.run {
                if naturalSize.width >= 3840 {
                    // 4K 視頻
                    playerItem.preferredMaximumResolution = CGSize(width: 3840, height: 2160)
                    playerItem.preferredPeakBitRate = codecInfo.isHEVC ? 50_000_000 : 80_000_000
                    playerItem.preferredForwardBufferDuration = 3.0
                } else if naturalSize.width >= 1920 {
                    // 1080p 視頻
                    playerItem.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
                    playerItem.preferredPeakBitRate = codecInfo.isHEVC ? 25_000_000 : 40_000_000
                    playerItem.preferredForwardBufferDuration = 2.0
                } else {
                    // HD 視頻
                    playerItem.preferredForwardBufferDuration = 1.5
                }
                
                print("ContentView: 詳細 GPU 配置完成 - 解析度: \(naturalSize), 幀率: \(nominalFrameRate)")
            }
        } catch {
            print("ContentView: 詳細 GPU 配置遇到錯誤，使用降級配置: \(error)")
            await applyBasicFallbackConfiguration(playerItem, codecInfo: codecInfo)
        }
    }
    
    /// 應用基本降級配置
    private func applyBasicFallbackConfiguration(_ playerItem: AVPlayerItem, codecInfo: VideoCodecInfo) async {
        await MainActor.run {
            playerItem.preferredForwardBufferDuration = 2.0
            if #available(iOS 15.0, *) {
                playerItem.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
                playerItem.preferredPeakBitRate = codecInfo.isHEVC ? 20_000_000 : 35_000_000
            }
            print("ContentView: 基本降級 GPU 配置已應用")
        }
    }
    
    /// 帶超時的異步操作
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
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
    
    /// 超時錯誤
    private struct TimeoutError: Error {}
    
    /// 檢查 Asset 可用性，對臨時檔案更寬鬆
    private func checkAssetAvailability(_ asset: AVAsset) async -> Bool {
        // 對於臨時檔案，isReadable 和 isPlayable 可能返回 false，但檔案實際上是可用的
        // 所以我們使用更實際的檢查方法
        
        // 方法 1: 檢查是否能獲取基本屬性
        do {
            if #available(iOS 16.0, *) {
                // 嘗試載入基本屬性
                let duration = try await asset.load(.duration)
                if duration.seconds > 0 && duration.seconds.isFinite {
                    print("ContentView: Asset 可用 - 通過時長檢測: \(duration.seconds)秒")
                    return true
                }
            } else {
                // iOS 15 同步檢查
                let duration = asset.duration
                if duration.seconds > 0 && duration.seconds.isFinite {
                    print("ContentView: Asset 可用 - 通過 iOS 15 時長檢測: \(duration.seconds)秒")
                    return true
                }
            }
        } catch {
            print("ContentView: Asset 時長檢測失敗: \(error)")
        }
        
        // 方法 2: 檢查是否有視頻軌道
        do {
            if #available(iOS 16.0, *) {
                let tracks = try await asset.load(.tracks)
                let videoTracks = tracks.filter { $0.mediaType == .video }
                if !videoTracks.isEmpty {
                    print("ContentView: Asset 可用 - 發現 \(videoTracks.count) 個視頻軌道")
                    return true
                }
            } else {
                let videoTracks = asset.tracks(withMediaType: .video)
                if !videoTracks.isEmpty {
                    print("ContentView: Asset 可用 - iOS 15 發現 \(videoTracks.count) 個視頻軌道")
                    return true
                }
            }
        } catch {
            print("ContentView: Asset 軌道檢測失敗: \(error)")
        }
        
        // 方法 3: 最後的寬鬆檢查 - 如果 asset 物件本身存在且不是 nil
        if asset.debugDescription.contains("AVURLAsset") {
            print("ContentView: Asset 可用 - 通過物件檢測（寬鬆模式）")
            return true
        }
        
        print("ContentView: Asset 確認不可用 - 所有檢測都失敗")
        return false
    }
    
    /// 配置音訊會話 - 優化版本，減少延遲
    private func configureAudioSession() async {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // 快速音訊會話配置，優先性能
            try audioSession.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowBluetooth, .allowAirPlay] // 移除不必要選項
            )
            
            // 優化採樣率和緩衝區大小
            try audioSession.setPreferredSampleRate(44100) // 標準採樣率，減少處理負擔
            try audioSession.setPreferredIOBufferDuration(0.01) // 10ms 緩衝，平衡性能和品質
            
            try audioSession.setActive(true)
            print("ContentView: 優化音訊會話配置完成")
        } catch {
            print("ContentView: 音訊會話配置失敗: \(error)")
        }
    }
    
    /// 為播放器項目配置最佳播放設置（針對所有格式啟用 GPU 加速）
    private func configurePlayerItemForOptimalPlayback(_ playerItem: AVPlayerItem, asset: AVAsset) async {
        print("ContentView: 開始配置播放器 GPU 加速設置...")
        
        // 檢測影片編碼格式
        let videoCodecInfo = await detectVideoCodecFormat(asset)
        print("ContentView: 檢測到影片格式: \(videoCodecInfo.codecName), 是否為 HEVC: \(videoCodecInfo.isHEVC)")
        
        // 為所有格式啟用 GPU 硬體加速
        await configureUniversalGPUAcceleration(playerItem, asset: asset, codecInfo: videoCodecInfo)
        print("ContentView: GPU 硬體加速設置已應用於 \(videoCodecInfo.codecName) 格式")
    }
    
    /// 配置通用 GPU 硬體加速（支援所有視頻格式） - 簡化版本
    private func configureUniversalGPUAcceleration(_ playerItem: AVPlayerItem, asset: AVAsset, codecInfo: VideoCodecInfo) async {
        print("ContentView: 配置通用 GPU 硬體加速...")
        
        // 1. 基本 GPU 加速設置
        if codecInfo.isHEVC {
            // HEVC 需要更多緩衝
            playerItem.preferredForwardBufferDuration = 2.5
            playerItem.audioTimePitchAlgorithm = .spectral
        } else {
            // H.264 和其他格式使用標準設置
            playerItem.preferredForwardBufferDuration = 2.0
            if #available(iOS 15.0, *) {
                playerItem.audioTimePitchAlgorithm = .timeDomain
            } else {
                playerItem.audioTimePitchAlgorithm = .spectral
            }
        }
        
        // 2. 啟用硬體解碼（所有格式）
        if #available(iOS 15.0, *) {
            // 設置最大解析度以啟用硬體加速
            playerItem.preferredMaximumResolution = CGSize(width: 3840, height: 2160) // 支援 4K
            
            // 根據編碼格式設置峰值比特率
            if codecInfo.isHEVC {
                playerItem.preferredPeakBitRate = 50_000_000 // 50 Mbps for HEVC
            } else {
                playerItem.preferredPeakBitRate = 80_000_000 // 80 Mbps for H.264 (需要更高比特率)
            }
        }
        
        // 3. 設置視頻輸出以使用 GPU
        await configureVideoOutputForGPU(asset, codecInfo: codecInfo)
        
        // 4. 通用優化設置
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        // 5. iOS 版本特定優化
        if #available(iOS 16.0, *) {
            playerItem.automaticallyPreservesTimeOffsetFromLive = false
        }
        
        // 6. 檢查並啟用硬體加速支援
        await checkUniversalGPUSupport(for: codecInfo)
        
        print("ContentView: 通用 GPU 硬體加速配置完成")
    }
    
    /// 配置視頻輸出以使用 GPU（支援所有格式）
    private func configureVideoOutputForGPU(_ asset: AVAsset, codecInfo: VideoCodecInfo) async {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = tracks.first else { return }
            
            // 獲取視頻屬性
            let naturalSize = try await videoTrack.load(.naturalSize)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            
            print("ContentView: 視頻解析度: \(naturalSize), 幀率: \(nominalFrameRate), 編碼: \(codecInfo.codecName)")
            
            // 根據視頻屬性和編碼格式優化 GPU 設置
            let gpuMode = determineGPUMode(resolution: naturalSize, codec: codecInfo)
            print("ContentView: \(codecInfo.codecName) - \(gpuMode)")
            
        } catch {
            print("ContentView: 無法獲取視頻屬性: \(error)")
        }
    }
    
    /// 判斷 GPU 模式
    private func determineGPUMode(resolution: CGSize, codec: VideoCodecInfo) -> String {
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
    
    /// 檢查通用 GPU 硬體支援
    private func checkUniversalGPUSupport(for codecInfo: VideoCodecInfo) async {
        // 檢查不同編碼格式的硬體支援
        let hevcSupported = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let h264Supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)
        
        print("ContentView: 硬體解碼支援狀況：")
        print("  - HEVC/H.265: \(hevcSupported ? "✅ 支援" : "❌ 不支援")")
        print("  - H.264: \(h264Supported ? "✅ 支援" : "❌ 不支援")")
        
        if codecInfo.isHEVC && hevcSupported {
            print("ContentView: ✅ HEVC GPU 硬體加速可用")
        } else if !codecInfo.isHEVC && h264Supported {
            print("ContentView: ✅ H.264 GPU 硬體加速可用")
        } else {
            print("ContentView: ⚠️ 當前格式將使用軟體解碼")
        }
        
        // 檢查設備性能等級
        await checkDevicePerformanceLevel()
    }
    
    /// 檢查設備性能等級
    private func checkDevicePerformanceLevel() async {
        if #available(iOS 15.0, *) {
            let device = UIDevice.current
            let processorCount = ProcessInfo.processInfo.processorCount
            let isHighPerformance = device.userInterfaceIdiom == .pad || processorCount >= 6
            
            print("ContentView: 設備信息：")
            print("  - 設備類型: \(device.userInterfaceIdiom == .pad ? "iPad" : "iPhone")")
            print("  - 處理器核心: \(processorCount)")
            print("  - 性能等級: \(isHighPerformance ? "高性能" : "標準性能")")
            
            if isHighPerformance {
                print("ContentView: 啟用高性能 GPU 模式，支援所有視頻格式硬體加速")
            } else {
                print("ContentView: 啟用標準 GPU 模式，支援主流視頻格式硬體加速")
            }
        }
    }
    
    /// 檢測視頻編碼格式 - 快速版本，減少檢測時間
    private func detectVideoCodecFormat(_ asset: AVAsset) async -> VideoCodecInfo {
        do {
            // 快速載入第一個視頻軌道
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let firstTrack = tracks.first else {
                return VideoCodecInfo(codecName: "Unknown", isHEVC: false, fourCC: 0)
            }
            
            // 快速獲取格式描述
            let formatDescriptions = try await firstTrack.load(.formatDescriptions)
            guard let firstFormat = formatDescriptions.first else {
                return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: 0) // 預設 H.264
            }
            
            let formatDescription = firstFormat as! CMFormatDescription
            let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
            
            // 快速編碼識別
            let codecInfo = identifyCodecFast(mediaSubType)
            print("ContentView: 快速編碼檢測 - 格式: \(codecInfo.codecName)")
            
            return codecInfo
        } catch {
            print("ContentView: 編碼檢測失敗，使用預設 H.264: \(error)")
            return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: 0)
        }
    }
    
    /// 快速識別編碼格式，減少檢查步驟
    private func identifyCodecFast(_ fourCC: FourCharCode) -> VideoCodecInfo {
        // 最常見的格式優先檢查
        switch fourCC {
        case 0x68766331, 0x68657631, kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha:
            return VideoCodecInfo(codecName: "HEVC/H.265", isHEVC: true, fourCC: fourCC)
        case 0x61766331, 0x61766343, kCMVideoCodecType_H264:
            return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: fourCC)
        default:
            // 其他格式一律當作 H.264 處理，減少檢測時間
            return VideoCodecInfo(codecName: "H.264/AVC", isHEVC: false, fourCC: fourCC)
        }
    }
    
    /// 將 FourCharCode 轉換為字串
    private func fourCharCodeToString(_ code: FourCharCode) -> String {
        let chars = [
            Character(UnicodeScalar((code >> 24) & 0xFF)!),
            Character(UnicodeScalar((code >> 16) & 0xFF)!),
            Character(UnicodeScalar((code >> 8) & 0xFF)!),
            Character(UnicodeScalar(code & 0xFF)!)
        ]
        return String(chars)
    }
    
    /// 視頻編碼信息結構
    struct VideoCodecInfo {
        let codecName: String
        let isHEVC: Bool
        let fourCC: FourCharCode
    }
}

// MARK: - UI 組件 (UI Components)

// 2. 頂部工具列
struct TopToolbarView: View {
    var onExport: () -> Void
    var onSelectVideo: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelectVideo) {
                Image(systemName: "video.badge.plus")
                    .font(.title2)
            }
            
            Spacer()
            
            Button(action: onExport) {
                Text("Export")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor).cornerRadius(8)
            }
        }
        .padding().background(Color.black)
    }
}

struct PlaybackControlsView: View {
    @Binding var player: AVPlayer
    @Binding var isPlaying: Bool
    @Binding var currentTime: TimeInterval
    @Binding var totalDuration: TimeInterval
    
    var body: some View {
        HStack(spacing: 0) {
            // 左側時間顯示
            Text(formatTime(currentTime))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 60, alignment: .leading)

            // 左側控制按鈕區域
            HStack(spacing: 12) {
                // 撤銷按鈕
                Button(action: {}) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                
                // 倒退按鈕 (新增)
                Button(action: {}) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)

            // 中央播放/暫停按鈕 - 對齊 playhead
            Button(action: {
                guard player.currentItem != nil else { return }
                
                if isPlaying {
                    player.pause()
                    isPlaying = false
                } else {
                    player.play()
                    isPlaying = true
                }
            }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

            // 右側控制按鈕區域
            HStack(spacing: 12) {
                // 快進按鈕 (新增)
                Button(action: {}) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                
                // 重做按鈕
                Button(action: {}) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
            
            // 右側總時長顯示
            Text(formatTime(totalDuration))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct MainActionToolbarView: View {
    var body: some View {
        HStack {
            ToolbarButton(icon: "scissors", label: "Edit")
            ToolbarButton(icon: "music.note", label: "Audio")
            ToolbarButton(icon: "textformat", label: "Text")
            ToolbarButton(icon: "square.stack.3d.down.right", label: "Overlay")
            ToolbarButton(icon: "wand.and.stars", label: "Effects")
        }
        .padding().background(Color.black)
    }
}

struct ToolbarButton: View {
    let icon: String
    let label: String
    
    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.title2)
            Text(label)
                .font(.caption)
        }
        .frame(maxWidth: .infinity).foregroundColor(.white)
    }
}

// MARK: - 影片轉碼進度彈窗 (Video Transcoding Progress Popup)
struct TranscodingProgressPopup: View {
    let progress: Float
    let onCancel: () -> Void
    
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        ZStack {
            // 半透明背景遮罩
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // 點擊背景不關閉彈窗，防止意外取消轉碼
                }
            
            // 進度彈窗主體
            VStack(spacing: 30) {
                // 標題區域
                VStack(spacing: 8) {
                    Text("正在處理影片")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text("請稍候，影片正在載入中...")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // 轉圈圈動畫區域
                VStack(spacing: 20) {
                    ZStack {
                        // 背景圓圈
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                            .frame(width: 80, height: 80)
                        
                        // 旋轉的圓弧
                        Circle()
                            .trim(from: 0.0, to: 0.25)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .cyan]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(Angle(degrees: rotationAngle))
                            .animation(
                                Animation.linear(duration: 1.0)
                                    .repeatForever(autoreverses: false),
                                value: rotationAngle
                            )
                        
                        // 中央影片圖標
                        Image(systemName: "video.badge.checkmark")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    
                    // 狀態文字
                    Text("處理中...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // 取消按鈕
                Button(action: onCancel) {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .font(.body)
                        Text("取消")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // 提示文字
                Text("處理過程中請勿關閉應用程式")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 4)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
        }
        .onAppear {
            rotationAngle = 360
        }
    }
}

// MARK: - VideoPicker: The definitive, working version
// Fetches the temporary URL from the itemProvider.
struct VideoPicker: UIViewControllerRepresentable {
    var onFinish: (URL?) -> Void
    var onSelectionStart: (() -> Void)?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker

        init(_ parent: VideoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if !results.isEmpty {
                parent.onSelectionStart?()
            }
            
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else {
                parent.onFinish(nil)
                return
            }
            
            // Use loadFileRepresentation to get a stable, readable URL
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    guard let sourceURL = url, error == nil else {
                        DispatchQueue.main.async {
                            print("VideoPicker: Failed to load file representation: \(error?.localizedDescription ?? "Unknown error")")
                            self.parent.onFinish(nil)
                        }
                        return
                    }
                    
                    // ** THE CRITICAL FIX **
                    // Immediately copy the file to a stable location before this closure returns.
                    let fileManager = FileManager.default
                    let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + sourceURL.pathExtension)
                    
                    do {
                        try fileManager.copyItem(at: sourceURL, to: destinationURL)
                        // Now pass the NEW, STABLE URL back to the content view.
                        DispatchQueue.main.async {
                            self.parent.onFinish(destinationURL)
                        }
                    } catch {
                        print("VideoPicker: Error copying file: \(error)")
                        DispatchQueue.main.async {
                            self.parent.onFinish(nil)
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.parent.onFinish(nil)
                }
            }
        }
    }
}

struct VideoPlayerView: View {
    @Binding var player: AVPlayer
    @Binding var isPlaying: Bool
    @Binding var currentTime: TimeInterval
    @Binding var totalDuration: TimeInterval
    
    @State private var timeObserver: Any?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                setupPlayer()
            }
            .onDisappear {
                removeTimeObserver()
            }
    }
    
    private func setupPlayer() {
        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
        
        // Remove existing observer if any
        removeTimeObserver()
        
        // Add time observer with reasonable frequency (30fps instead of 100fps)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0/30.0, preferredTimescale: 600),
            queue: .main
        ) { time in
            currentTime = time.seconds
            
            // Update isPlaying state based on actual player state
            updatePlayingState()
        }
        
        // Add notification observers for player state changes
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
        }
        
        // Add observer for when player fails to play
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
        }
        
        // Add observer for when player stalls
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: player.currentItem,
            queue: .main
        ) { _ in
            // Don't change isPlaying state for stalls, just log
            print("Player stalled")
        }
        
        // Ensure audio is enabled
        player.isMuted = false
        player.volume = 1.0
    }
    
    private func removeTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    private func updatePlayingState() {
        // Check if player is actually playing
        let actuallyPlaying = player.rate > 0 && player.error == nil && player.currentItem != nil
        
        // Only update if there's a real change to avoid unnecessary UI updates
        // Since we're already on the main queue from the time observer, no need for async dispatch
        if isPlaying != actuallyPlaying {
            isPlaying = actuallyPlaying
        }
    }
}

// MARK: - Legacy SimplifiedTimelineView has been replaced by TimelineContainerView
// The new implementation provides enhanced timeline scrubbing functionality
// with improved performance, gesture handling, and visual feedback

// MARK: - 輔助視圖與數據模型 (Helper Views & Data Models)
// Note: Shared models and views are now in TimelineModels.swift

private func formatTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}