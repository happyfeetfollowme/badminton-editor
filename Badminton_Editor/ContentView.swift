import SwiftUI
import AVKit
import AVFoundation
import PhotosUI
import Photos
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
    @StateObject private var thumbnailProvider = ThumbnailProvider()
    @State private var showLoadingAnimation = false
    @State private var currentVideoURL: URL? // This will now store the *copied* video URL
    @State private var photoLibraryAuthorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var currentPHAsset: PHAsset? // Store the current PHAsset for direct access
    @State private var selectedVideo: AVAsset? // Selected video asset
    @State private var isExporting = false // Export state
    
    // MARK: - Responsive Layout Functions
    
    /// Calculate responsive toolbar height based on screen size
    private func responsiveToolbarHeight(for screenSize: CGSize, isCompact: Bool) -> CGFloat {
        let availableHeight = screenSize.height

        return availableHeight * 0.05 // 5% of screen height
    }
    
    /// Calculate responsive video player height based on screen size and orientation
    private func responsiveVideoPlayerHeight(for screenSize: CGSize, isCompact: Bool, isLandscape: Bool) -> CGFloat {
        let availableHeight = screenSize.height
        
        if isCompact {
            // iPhone sizing
            if isLandscape {
                return availableHeight * 0.5 // 50% in landscape for more timeline space
            } else {
                return availableHeight * 0.4 // 40% in portrait
            }
        } else {
            // iPad sizing
            if isLandscape {
                return availableHeight * 0.6 // 60% in landscape
            } else {
                return availableHeight * 0.5 // 50% in portrait
            }
        }
    }
    
    /// Calculate responsive timeline height based on screen size
    private func responsiveTimelineHeight(for screenSize: CGSize, isCompact: Bool) -> CGFloat {
        let availableHeight = screenSize.height
        
        if isCompact {
            return availableHeight * 0.35 // 40% with min/max constraints
        } else {
            return availableHeight * 0.4 // 50% with min/max constraints
        }
    }
    
    /// Calculate responsive controls height
    private func responsiveControlsHeight(for screenSize: CGSize, isCompact: Bool) -> CGFloat {
        let availableHeight = screenSize.height
        return isCompact ? availableHeight * 0.05 : availableHeight * 0.1
    }

    /// Calculate responsive action toolbar height
    private func responsiveActionToolbarHeight(for screenSize: CGSize, isCompact: Bool) -> CGFloat {
        let availableHeight = screenSize.height
        return isCompact ? availableHeight * 0.05 : availableHeight * 0.1
    }
    
    /// Calculate responsive spacing between controls
    private func responsiveControlSpacing(isCompact: Bool) -> CGFloat {
        return isCompact ? 8 : 12
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size
            let isCompact = screenSize.width < 700 // iPhone and compact sizes
            let isLandscape = screenSize.width > screenSize.height
            
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Top Toolbar - responsive height
                    TopToolbarView(
                        onExport: { /* 導出邏輯 */ },
                        onSelectVideo: {
                            requestPhotoLibraryPermissions { granted in
                                showVideoPicker = granted
                            }
                        }
                    )
                    .frame(height: responsiveToolbarHeight(for: screenSize, isCompact: isCompact))
                    
                    // Main content (video player, timeline, controls)
                    VStack(spacing: responsiveControlSpacing(isCompact: isCompact)) {
                        VideoPlayerView(
                            player: $player,
                            isPlaying: $isPlaying,
                            currentTime: $currentTime,
                            totalDuration: $totalDuration
                        )
                        .frame(height: responsiveVideoPlayerHeight(for: screenSize, isCompact: isCompact, isLandscape: isLandscape))
                        .onTapGesture {
                            guard player.currentItem != nil else { return }
                            isPlaying.toggle()
                            isPlaying ? player.play() : player.pause()
                        }

                        TimelineContainerView(
                            player: $player,
                            currentTime: $currentTime,
                            totalDuration: $totalDuration,
                            // ...existing code...
                            thumbnailProvider: thumbnailProvider
                        )
                        .frame(height: responsiveTimelineHeight(for: screenSize, isCompact: isCompact))

                        PlaybackControlsView(
                            player: $player,
                            isPlaying: $isPlaying,
                            currentTime: $currentTime,
                            totalDuration: $totalDuration
                        )
                        .frame(height: responsiveControlsHeight(for: screenSize, isCompact: isCompact))
                    }
                    .frame(maxWidth: .infinity)

                    Spacer() // Pushes the Main Action Toolbar to the bottom
                    
                    // Main Action Toolbar - responsive height
                    MainActionToolbarView(
                        selectedVideo: $selectedVideo,
                        showingVideoPicker: $showVideoPicker,
                        isExporting: $isExporting,
                        onExport: {
                            exportVideo()
                        }
                    )
                    .frame(height: responsiveActionToolbarHeight(for: screenSize, isCompact: isCompact))
                    .onChange(of: selectedVideo) { oldValue, newValue in
                        // If selectedVideo is set to nil and it had a value before, perform full reset
                        if oldValue != nil && newValue == nil {
                            resetVideo()
                        }
                    }
                    .background(Color(red: 33/255, green: 31/255, blue: 31/255))
                }
                .frame(maxHeight: .infinity, alignment: .top)
                
                if showLoadingAnimation {
                    BasicLoadingIndicator(onCancel: { showLoadingAnimation = false })
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showVideoPicker) {
            PHAssetVideoPicker(
                onFinish: { phAsset in
                    if let asset = phAsset {
                        Task { await handlePHAssetSelection(with: asset) }
                    }
                },
                onSelectionStart: { showLoadingAnimation = true }
            )
        }
    }
    
    // MARK: - Video Loading Management

    /// Request photo library permissions for direct PHAsset access
    private func requestPhotoLibraryPermissions(completion: @escaping (Bool) -> Void) {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch currentStatus {
        case .authorized, .limited:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    self.photoLibraryAuthorizationStatus = status
                    completion(status == .authorized || status == .limited)
                }
            }
        @unknown default:
            completion(false)
        }
    }

    /// Handles the PHAsset selection, loading AVAsset directly without copying data
    private func handlePHAssetSelection(with phAsset: PHAsset) async {
        await VideoLoader.handlePHAssetSelection(
            phAsset: phAsset,
            thumbnailProvider: thumbnailProvider,
            setCurrentPHAsset: { self.currentPHAsset = $0 },
            loadVideoAsset: { asset in
                self.selectedVideo = asset // Set the selected video
                await VideoLoader.loadVideoAsset(
                    asset: asset,
                    player: player,
                    setCurrentTime: { self.currentTime = $0 },
                    setTotalDuration: { self.totalDuration = $0 },
                    // ...existing code...
                    setShowLoadingAnimation: { self.showLoadingAnimation = $0 },
                    applyInstantGPUOptimizations: VideoLoader.applyInstantGPUOptimizations,
                    configureDetailedGPUAcceleration: VideoLoader.configureDetailedGPUAcceleration,
                    configureAudioSession: VideoLoader.configureAudioSession,
                    detectVideoCodecFormat: VideoLoader.detectVideoCodecFormat,
                    loadDurationOptimized: VideoLoader.loadDurationOptimized
                )
            }
        )
    }

    /// Handles the video selection, now receiving a STABLE, copied URL.
    private func handleVideoSelection(with localURL: URL) async {
        await VideoLoader.handleVideoSelection(
            localURL: localURL,
            setCurrentVideoURL: { self.currentVideoURL = $0 },
            loadVideoAsset: { asset in
                self.selectedVideo = asset // Set the selected video
                await VideoLoader.loadVideoAsset(
                    asset: asset,
                    player: player,
                    setCurrentTime: { self.currentTime = $0 },
                    setTotalDuration: { self.totalDuration = $0 },
                    // ...existing code...
                    setShowLoadingAnimation: { self.showLoadingAnimation = $0 },
                    applyInstantGPUOptimizations: VideoLoader.applyInstantGPUOptimizations,
                    configureDetailedGPUAcceleration: VideoLoader.configureDetailedGPUAcceleration,
                    configureAudioSession: VideoLoader.configureAudioSession,
                    detectVideoCodecFormat: VideoLoader.detectVideoCodecFormat,
                    loadDurationOptimized: VideoLoader.loadDurationOptimized
                )
            }
        )
    }
    
    /// Exports the current video with applied edits
    private func exportVideo() {
        guard selectedVideo != nil else { return }
        
        isExporting = true
        
        // TODO: Implement actual video export functionality
        // This is a placeholder that simulates export process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isExporting = false
            // Show success message or handle export completion
        }
    }
    
    /// Resets the video editor to initial state
    private func resetVideo() {
        // Reset player
        player.pause()
        player.replaceCurrentItem(with: nil)
        
        // Reset state variables
        selectedVideo = nil
        isPlaying = false
        currentTime = 0
        totalDuration = 0
        // ...existing code...
        currentVideoURL = nil
        currentPHAsset = nil
        
        // Reset thumbnail provider
        thumbnailProvider.clear()
    }
    
}
