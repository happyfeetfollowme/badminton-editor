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
    @State private var markers: [RallyMarker] = []
    @StateObject private var thumbnailCache = ThumbnailCache()
    @State private var showLoadingAnimation = false
    @State private var currentVideoURL: URL? // This will now store the *copied* video URL
    @State private var photoLibraryAuthorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var currentPHAsset: PHAsset? // Store the current PHAsset for direct access
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack(spacing: 0) {
                TopToolbarView(
                    onExport: { /* 導出邏輯 */ },
                    onSelectVideo: {
                        requestPhotoLibraryPermissions { granted in
                            showVideoPicker = granted
                        }
                    }
                )
                VideoPlayerView(player: $player, isPlaying: $isPlaying, currentTime: $currentTime, totalDuration: $totalDuration)
                    .onTapGesture {
                        guard player.currentItem != nil else { return }
                        isPlaying.toggle()
                        isPlaying ? player.play() : player.pause()
                    }
                VStack(spacing: 8) {
                    TimelineContainerView(
                        player: $player,
                        currentTime: $currentTime,
                        totalDuration: $totalDuration,
                        markers: $markers
                    ).frame(height: 120)
                    PlaybackControlsView(
                        player: $player,
                        isPlaying: $isPlaying,
                        currentTime: $currentTime,
                        totalDuration: $totalDuration
                    )
                }.padding(.vertical, 10)
                MainActionToolbarView()
            }
            if showLoadingAnimation {
                BasicLoadingIndicator(onCancel: { showLoadingAnimation = false })
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
            thumbnailCache: thumbnailCache,
            setCurrentPHAsset: { self.currentPHAsset = $0 },
            loadVideoAsset: { asset in
                await VideoLoader.loadVideoAsset(
                    asset: asset,
                    player: player,
                    setCurrentTime: { self.currentTime = $0 },
                    setTotalDuration: { self.totalDuration = $0 },
                    setMarkers: { self.markers = $0 },
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
                await VideoLoader.loadVideoAsset(
                    asset: asset,
                    player: player,
                    setCurrentTime: { self.currentTime = $0 },
                    setTotalDuration: { self.totalDuration = $0 },
                    setMarkers: { self.markers = $0 },
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
    
}
