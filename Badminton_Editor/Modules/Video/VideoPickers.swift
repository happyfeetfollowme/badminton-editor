import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

// MARK: - PHAssetVideoPicker: Direct PHAsset access without copying data
struct PHAssetVideoPicker: UIViewControllerRepresentable {
    var onFinish: (PHAsset?) -> Void
    var onSelectionStart: (() -> Void)?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHAssetVideoPicker
        init(_ parent: PHAssetVideoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if !results.isEmpty { parent.onSelectionStart?() }
            picker.dismiss(animated: true)
            guard let result = results.first else { parent.onFinish(nil); return }
            if let assetIdentifier = result.assetIdentifier {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
                if let phAsset = fetchResult.firstObject {
                    parent.onFinish(phAsset)
                } else {
                    parent.onFinish(nil)
                }
            } else {
                parent.onFinish(nil)
            }
        }
    }
}

// MARK: - Legacy VideoPicker (kept for reference/fallback)
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
            if !results.isEmpty { parent.onSelectionStart?() }
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { parent.onFinish(nil); return }
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    guard let sourceURL = url, error == nil else {
                        DispatchQueue.main.async { self.parent.onFinish(nil) }
                        return
                    }
                    let fileManager = FileManager.default
                    let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + sourceURL.pathExtension)
                    do {
                        try fileManager.copyItem(at: sourceURL, to: destinationURL)
                        DispatchQueue.main.async { self.parent.onFinish(destinationURL) }
                    } catch {
                        DispatchQueue.main.async { self.parent.onFinish(nil) }
                    }
                }
            } else {
                DispatchQueue.main.async { self.parent.onFinish(nil) }
            }
        }
    }
}
