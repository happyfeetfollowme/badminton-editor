import SwiftUI
import AVKit

struct TopToolbarView: View {
    var onExport: () -> Void
    var onSelectVideo: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 700
            
            HStack {
                Button(action: onSelectVideo) {
                    Image(systemName: "video.badge.plus")
                        .font(isCompact ? .title2 : .title)
                        .foregroundColor(.accentColor)
                }
                
                Spacer()
                
                Button(action: onExport) {
                    Text("Export")
                        .font(isCompact ? .subheadline : .headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, isCompact ? 16 : 20)
                        .padding(.vertical, isCompact ? 6 : 8)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, isCompact ? 16 : 20)
            .padding(.vertical, isCompact ? 8 : 12)
            .background(Color.black)
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

struct PlaybackControlsView: View {
    @Binding var player: AVPlayer
    @Binding var isPlaying: Bool
    @Binding var currentTime: TimeInterval
    @Binding var totalDuration: TimeInterval
    
    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 700
            let buttonSize: CGFloat = isCompact ? 16 : 18
            let playButtonSize: CGFloat = isCompact ? 40 : 48
            let fontSize: CGFloat = isCompact ? 10 : 12
            
            HStack(spacing: 0) {
                // Current time
                Text(formatTime(currentTime))
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: isCompact ? 50 : 60, alignment: .leading)
                
                // Left controls
                HStack(spacing: isCompact ? 8 : 12) {
                    Button(action: {}) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: buttonSize, weight: .medium))
                            .foregroundColor(.white)
                    }
                    Button(action: {}) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: buttonSize, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, isCompact ? 12 : 20)
                
                // Play/Pause button
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
                        .font(.system(size: isCompact ? 16 : 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: playButtonSize, height: playButtonSize)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                }
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // Right controls
                HStack(spacing: isCompact ? 8 : 12) {
                    Button(action: {}) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: buttonSize, weight: .medium))
                            .foregroundColor(.white)
                    }
                    Button(action: {}) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: buttonSize, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, isCompact ? 12 : 20)
                
                // Total duration
                Text(formatTime(totalDuration))
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: isCompact ? 50 : 60, alignment: .trailing)
            }
            .padding(.horizontal, isCompact ? 12 : 16)
            .padding(.vertical, isCompact ? 6 : 8)
        }
    }
}

struct MainActionToolbarView: View {
    @Binding var selectedVideo: AVAsset?
    @Binding var showingVideoPicker: Bool
    @Binding var isExporting: Bool
    var onExport: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 700
            
            HStack(spacing: isCompact ? 16 : 24) {
                // Video picker button
                ToolbarButton(
                    action: { showingVideoPicker = true },
                    iconName: "video.badge.plus",
                    label: "Import Video",
                    backgroundColor: Color.blue,
                    isCompact: isCompact
                )
                
                Spacer()
                
                // Reset button
                ToolbarButton(
                    action: { selectedVideo = nil },
                    iconName: "arrow.counterclockwise",
                    label: "Reset",
                    backgroundColor: Color.orange,
                    isEnabled: selectedVideo != nil,
                    isCompact: isCompact
                )
                
                // Export button
                ToolbarButton(
                    action: onExport,
                    iconName: "square.and.arrow.up",
                    label: "Export",
                    backgroundColor: Color.green,
                    isEnabled: selectedVideo != nil && !isExporting,
                    isLoading: isExporting,
                    isCompact: isCompact
                )
            }
            .padding(.horizontal, isCompact ? 16 : 24)
            .padding(.vertical, isCompact ? 12 : 16)
        }
    }
}

struct ToolbarButton: View {
    let action: () -> Void
    let iconName: String
    let label: String
    let backgroundColor: Color
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var isCompact: Bool = false
    
    var body: some View {
        let buttonHeight: CGFloat = isCompact ? 36 : 44
        let iconSize: CGFloat = isCompact ? 16 : 18
        let fontSize: CGFloat = isCompact ? 12 : 14
        let cornerRadius: CGFloat = isCompact ? 8 : 10
        let horizontalPadding: CGFloat = isCompact ? 12 : 16
        
        Button(action: action) {
            HStack(spacing: isCompact ? 6 : 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(isCompact ? 0.8 : 1.0)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: iconSize, weight: .medium))
                }
                
                Text(label)
                    .font(.system(size: fontSize, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, horizontalPadding)
            .frame(height: buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor.opacity(isEnabled ? 1.0 : 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(!isEnabled || isLoading)
        .scaleEffect(isEnabled && !isLoading ? 1.0 : 0.95)
        .animation(.easeInOut(duration: 0.1), value: isEnabled)
        .shadow(color: backgroundColor.opacity(0.3), radius: isCompact ? 3 : 4, x: 0, y: 2)
    }
}

struct BasicLoadingIndicator: View {
    let onCancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("正在載入影片")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("請稍候...")
                        .font(.body)
                        .foregroundColor(.gray)
                }
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1.5)
                Button(action: onCancel) {
                    Text("取消")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
        }
    }
}