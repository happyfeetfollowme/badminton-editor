import SwiftUI
import AVKit
import AVFoundation
import PhotosUI

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

    var body: some View {
        ZStack {
            // 背景色設定為深色
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // MARK: - 2. 頂部工具列 (Top Toolbar)
                TopToolbarView(onExport: {
                    // 導出邏輯
                }, onSelectVideo: {
                    showVideoPicker = true
                    // 當用戶點擊選擇影片按鈕時，預先準備動畫狀態
                    showLoadingAnimation = false
                    thumbnailCache.isTranscoding = false
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
                onFinish: { asset in
                    if let asset = asset {
                        Task {
                            print("ContentView: 開始載入影片資源...")
                            // 直接載入影片，AVFoundation 會自動處理不同編碼格式
                            await loadVideoAsset(asset)
                        }
                    }
                },
                onSelectionStart: {
                    // 用戶選擇影片的瞬間立即顯示動畫
                    print("ContentView: 影片選擇完成，立刻顯示載入動畫...")
                    showLoadingAnimation = true
                    thumbnailCache.isTranscoding = true
                    thumbnailCache.transcodingProgress = 0.0
                }
            )
        }
    }
    
    // MARK: - Helper Methods for Video Loading
    
    /// 載入影片資源到播放器
    private func loadVideoAsset(_ asset: AVAsset) async {
        print("ContentView: 開始載入影片資源...")
        
        // 確保載入動畫正在顯示
        await MainActor.run {
            if !showLoadingAnimation {
                showLoadingAnimation = true
                thumbnailCache.isTranscoding = true
                thumbnailCache.transcodingProgress = 0.0
            }
        }
        
        // 直接創建 AVPlayerItem，AVFoundation 會自動處理不同編碼格式
        let playerItem = AVPlayerItem(asset: asset)
        
        // 設置通用的播放器優化參數
        playerItem.preferredForwardBufferDuration = 3.0 // 3秒緩衝
        playerItem.audioTimePitchAlgorithm = .lowQualityZeroLatency
        
        // 設置播放器行為
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        // Use async loading for iOS 16+ compatibility
        do {
            let duration = try await asset.load(.duration)
            await MainActor.run {
                player.replaceCurrentItem(with: playerItem)
                totalDuration = duration.seconds
                markers = []
                
                // 確保 currentTime 重置為 0.0，這將觸發 timeline 對齊
                currentTime = 0.0
                
                // Configure audio settings when new video is loaded
                player.isMuted = false
                player.volume = 1.0
                
                print("ContentView: Video loaded, currentTime set to \(currentTime), totalDuration: \(totalDuration)")
            }
        } catch {
            print("Failed to load video duration: \(error)")
            // Fallback for older iOS versions or if async loading fails
            await MainActor.run {
                player.replaceCurrentItem(with: playerItem)
                totalDuration = asset.duration.seconds
                markers = []
                currentTime = 0.0
                player.isMuted = false
                player.volume = 1.0
                print("ContentView: Video loaded (fallback), currentTime set to \(currentTime), totalDuration: \(totalDuration)")
            }
        }
        
        // 設置音訊會話
        await configureAudioSession()
        
        // 等待一小段時間確保影片完全載入，然後隱藏載入動畫
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        await MainActor.run {
            showLoadingAnimation = false
            thumbnailCache.isTranscoding = false
            thumbnailCache.transcodingProgress = 0.0
            print("ContentView: 影片載入完成，隱藏載入動畫")
        }
    }
    
    /// 配置音訊會話
    private func configureAudioSession() async {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
            print("ContentView: 音訊會話配置完成")
        } catch {
            print("ContentView: 配置音訊會話失敗: \(error)")
        }
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

// MARK: - VideoPicker 修改
// 功能: 選擇影片後清空舊的標記點
struct VideoPicker: UIViewControllerRepresentable {
    var onFinish: (AVAsset?) -> Void
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
            // 立即顯示載入動畫（在 dismiss 之前）
            if !results.isEmpty {
                parent.onSelectionStart?()
            }
            
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else {
                parent.onFinish(nil)
                return
            }
            
            // Reverted to a more robust method using file representation
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    guard let url = url else {
                        DispatchQueue.main.async { self.parent.onFinish(nil) }
                        return
                    }
                    
                    // The provided URL is temporary, so we copy it to a new location
                    let tempDirectory = FileManager.default.temporaryDirectory
                    let newURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                    
                    do {
                        try FileManager.default.copyItem(at: url, to: newURL)
                        let asset = AVURLAsset(url: newURL)
                        DispatchQueue.main.async {
                            self.parent.onFinish(asset)
                        }
                    } catch {
                        print("Failed to copy video file: \(error)")
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

// MARK: - 時間軸標尺視圖
/// Timeline ruler view that displays time scale markers and labels
/// Provides visual time reference with second and 10-second intervals
struct TimelineRulerView: View {
    // MARK: - Properties
    
    /// Total duration of the video content
    let totalDuration: TimeInterval
    
    /// Current zoom level (pixels per second)
    let pixelsPerSecond: CGFloat
    
    /// Current time for reference (maintained for compatibility)
    let currentTime: TimeInterval
    
    /// Base offset for timeline alignment
    private let baseOffset: CGFloat = 500
    
    /// Boundary padding for smooth scrolling
    private let boundaryPadding: CGFloat = 1000
    
    // MARK: - Constants
    
    /// Minimum zoom level to show time labels
    private let minZoomForLabels: CGFloat = 25.0
    
    /// Height for major ruler marks (10-second intervals)
    private let majorMarkHeight: CGFloat = 20.0
    
    /// Height for minor ruler marks (1-second intervals)
    private let minorMarkHeight: CGFloat = 10.0
    
    /// Opacity for major ruler marks
    private let majorMarkOpacity: Double = 0.8
    
    /// Opacity for minor ruler marks
    private let minorMarkOpacity: Double = 0.4
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 0) {
            // Base offset padding
            Rectangle()
                .fill(Color.clear)
                .frame(width: baseOffset)
            
            // Generate ruler marks for each second
            ForEach(0..<Int(ceil(totalDuration)), id: \.self) { second in
                rulerMark(for: TimeInterval(second))
            }
            
            // Boundary padding
            Rectangle()
                .fill(Color.clear)
                .frame(width: boundaryPadding)
        }
    }
    
    // MARK: - Ruler Mark Generation
    
    /// Create a ruler mark for a specific time position
    /// - Parameter time: The time in seconds for this ruler mark
    /// - Returns: A view representing the ruler mark with optional time label
    @ViewBuilder
    private func rulerMark(for time: TimeInterval) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Determine if this is a major mark (10-second interval)
            let isMajorMark = Int(time) % 10 == 0
            let isMinorMark = Int(time) % 5 == 0 && !isMajorMark
            
            // Create the ruler mark line
            rulerMarkLine(isMajor: isMajorMark, isMinor: isMinorMark)
            
            // Add time label for major marks when zoom level is sufficient
            if isMajorMark && shouldShowTimeLabels {
                timeLabel(for: time)
            }
            
            Spacer()
        }
        .frame(width: pixelsPerSecond)
    }
    
    /// Create the visual ruler mark line
    /// - Parameters:
    ///   - isMajor: Whether this is a major (10-second) mark
    ///   - isMinor: Whether this is a minor (5-second) mark
    /// - Returns: A rectangle representing the ruler mark
    @ViewBuilder
    private func rulerMarkLine(isMajor: Bool, isMinor: Bool) -> some View {
        if isMajor {
            Rectangle()
                .fill(Color.white.opacity(majorMarkOpacity))
                .frame(width: 1, height: majorMarkHeight)
        } else if isMinor {
            Rectangle()
                .fill(Color.white.opacity(minorMarkOpacity + 0.2))
                .frame(width: 1, height: minorMarkHeight + 5)
        } else {
            Rectangle()
                .fill(Color.white.opacity(minorMarkOpacity))
                .frame(width: 1, height: minorMarkHeight)
        }
    }
    
    /// Create time label for major marks
    /// - Parameter time: The time to display
    /// - Returns: A text view with formatted time
    @ViewBuilder
    private func timeLabel(for time: TimeInterval) -> some View {
        Text(formatTime(time))
            .font(.system(size: labelFontSize, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.7))
            .padding(.top, 2)
    }
    
    // MARK: - Computed Properties
    
    /// Whether time labels should be shown based on current zoom level
    private var shouldShowTimeLabels: Bool {
        return pixelsPerSecond >= minZoomForLabels
    }
    
    /// Font size for time labels based on zoom level
    private var labelFontSize: CGFloat {
        switch pixelsPerSecond {
        case 0..<30:
            return 7
        case 30..<60:
            return 8
        case 60..<100:
            return 9
        case 100..<150:
            return 10
        default:
            return 11
        }
    }
    
    // MARK: - Helper Methods
    
    /// Format time interval for display
    /// - Parameter time: Time interval in seconds
    /// - Returns: Formatted time string (MM:SS or H:MM:SS for longer durations)
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - 影片縮圖時間軸視圖
struct VideoThumbnailTimelineView: View {
    let player: AVPlayer
    let totalDuration: TimeInterval
    let pixelsPerSecond: CGFloat
    let markers: [RallyMarker]
    
    @State private var thumbnails: [TimeInterval: UIImage] = [:]
    @State private var thumbnailTimes: [TimeInterval] = []
    private static let thumbnailCache = NSCache<NSNumber, UIImage>()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Rectangle()
                    .fill(Color.black.opacity(0.8))
                    .cornerRadius(4)
                
                // 縮圖片段
                HStack(spacing: 0) {
                    ForEach(Array(thumbnailTimes.enumerated()), id: \.offset) { index, time in
                        thumbnailCell(index: index, time: time)
                    }
                }
                .offset(x: 500) // 與時間軸對齊
            }
        }
        .onAppear {
            updateAndGenerateThumbnails()
        }
        .onChange(of: player.currentItem) { _ in
            thumbnails.removeAll()
            Self.thumbnailCache.removeAllObjects()
            updateAndGenerateThumbnails()
        }
        .onChange(of: pixelsPerSecond) { _ in
            // 縮放變化時，重新計算並生成縮圖
            updateAndGenerateThumbnails()
        }
        .onChange(of: totalDuration) { _ in
            updateAndGenerateThumbnails()
        }
    }
    
    @ViewBuilder
    private func thumbnailCell(index: Int, time: TimeInterval) -> some View {
        let nextTime = (index + 1 < thumbnailTimes.count) ? thumbnailTimes[index + 1] : totalDuration
        let durationOfSegment = nextTime - time
        let thumbnailWidth = CGFloat(durationOfSegment) * pixelsPerSecond

        if let image = thumbnails[time] {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: thumbnailWidth, height: 60)
                .clipped()
                .overlay(
                    // 回合片段高亮
                    isInRallySegment(time: time) ?
                        Color.clear :
                        Color.black.opacity(0.6)
                )
        } else {
            Rectangle()
                .fill(Color.gray)
                .frame(width: thumbnailWidth, height: 60)
        }
    }
    
    private func updateAndGenerateThumbnails() {
        updateThumbnailTimes()
        generateThumbnails()
    }

    private func updateThumbnailTimes() {
        guard totalDuration > 0, pixelsPerSecond > 0 else {
            thumbnailTimes = []
            return
        }
        
        let thumbnailWidth: CGFloat = 80.0 // 固定縮圖寬度
        let timePerThumbnail = thumbnailWidth / pixelsPerSecond
        let numberOfThumbnails = Int(ceil(totalDuration / timePerThumbnail))
        
        let newThumbnailTimes = (0..<numberOfThumbnails).map { i in
            Double(i) * Double(timePerThumbnail)
        }
        
        // Filter the existing thumbnails to keep only the ones that are still relevant
        let newTimesSet = Set(newThumbnailTimes)
        thumbnails = thumbnails.filter { newTimesSet.contains($0.key) }
        
        self.thumbnailTimes = newThumbnailTimes
    }
    
    private func isInRallySegment(time: TimeInterval) -> Bool {
        let rallySegments = getRallySegments()
        return rallySegments.contains { $0.start <= time && time < $0.end }
    }
    
    private func getRallySegments() -> [(start: TimeInterval, end: TimeInterval)] {
        var segments: [(TimeInterval, TimeInterval)] = []
        let starts = markers.filter { $0.type == .start }.sorted { $0.time < $1.time }
        let ends = markers.filter { $0.type == .end }.sorted { $0.time < $1.time }
        
        var i = 0, j = 0
        while i < starts.count && j < ends.count {
            if starts[i].time < ends[j].time {
                segments.append((starts[i].time, ends[j].time))
                i += 1
                j += 1
            } else {
                j += 1
            }
        }
        return segments
    }
    
    private func generateThumbnails() {
        guard let asset = player.currentItem?.asset else {
            return
        }
        
        let timesToGenerate = thumbnailTimes.filter { time in
            thumbnails[time] == nil && Self.thumbnailCache.object(forKey: NSNumber(value: time)) == nil
        }
        
        guard !timesToGenerate.isEmpty else { return }

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 320, height: 180) // 提升解析度到 2x
        
        // 提升圖像品質設定
        imageGenerator.apertureMode = .cleanAperture
        if #available(iOS 16.0, *) {
            imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
            imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        } else {
            // Allow a small tolerance to find the nearest valid frame, preventing black thumbnails
            let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
            imageGenerator.requestedTimeToleranceBefore = tolerance
            imageGenerator.requestedTimeToleranceAfter = tolerance
        }

        let timeValues = timesToGenerate.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }
        
        imageGenerator.generateCGImagesAsynchronously(forTimes: timeValues) { requestedTime, cgImage, actualTime, result, error in
            let timeInSeconds = requestedTime.seconds
            
            if let cgImage = cgImage, result == .succeeded {
                let image = UIImage(cgImage: cgImage)
                Self.thumbnailCache.setObject(image, forKey: NSNumber(value: timeInSeconds))
                DispatchQueue.main.async {
                    self.thumbnails[timeInSeconds] = image
                }
            } else {
                // 生成失敗或錯誤，使用默認縮圖
                let defaultImage = generateDefaultThumbnail()
                Self.thumbnailCache.setObject(defaultImage, forKey: NSNumber(value: timeInSeconds))
                DispatchQueue.main.async {
                    self.thumbnails[timeInSeconds] = defaultImage
                }
            }
        }
    }
    
    private func generateDefaultThumbnail() -> UIImage {
        let size = CGSize(width: 320, height: 180) // 提升解析度到 2x
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIColor.darkGray.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
}

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
