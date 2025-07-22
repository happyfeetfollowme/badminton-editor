import SwiftUI
import AVKit

struct TopToolbarView: View {
    var onExport: () -> Void
    var onSelectVideo: () -> Void
    var body: some View {
        HStack {
            Button(action: onSelectVideo) {
                Image(systemName: "video.badge.plus").font(.title2)
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
        HStack(spacing: 0) {
            Text(formatTime(currentTime))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 60, alignment: .leading)
            HStack(spacing: 12) {
                Button(action: {}) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                Button(action: {}) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
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
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            HStack(spacing: 12) {
                Button(action: {}) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                Button(action: {}) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
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
            Image(systemName: icon).font(.title2)
            Text(label).font(.caption)
        }
        .frame(maxWidth: .infinity).foregroundColor(.white)
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