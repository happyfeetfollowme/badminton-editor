import Foundation
import AVFoundation
import Photos
import VideoToolbox
import SwiftUI

class VideoLoader {
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
