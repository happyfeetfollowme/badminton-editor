import SwiftUI
import Photos
@preconcurrency import PhotosUI

/// 使用 PhotosUI 的現代化影片選擇器
@available(iOS 16.0, *)
struct ModernVideoPickerView: View {
    @State private var selectedItem: PhotosPickerItem?
    let onVideoPicked: (PHAsset) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos
                ) {
                    VStack(spacing: 16) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        
                        Text("選擇影片")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                            )
                    )
                }
                .onChange(of: selectedItem) { newItem in
                    Task {
                        if let newItem = newItem,
                           let assetIdentifier = newItem.itemIdentifier {
                            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
                            if let asset = fetchResult.firstObject {
                                await MainActor.run {
                                    onVideoPicked(asset)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("選擇影片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 兼容性的影片選擇器包裝器
struct CompatibleVideoPickerView: View {
    let onVideoPicked: (PHAsset) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        if #available(iOS 16.0, *) {
            ModernVideoPickerView(onVideoPicked: onVideoPicked)
        } else {
            LegacyVideoPickerView(onVideoPicked: onVideoPicked)
        }
    }
}

/// iOS 15 及以下版本的影片選擇器
struct LegacyVideoPickerView: UIViewControllerRepresentable {
    let onVideoPicked: (PHAsset) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UINavigationController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        
        let navigationController = UINavigationController(rootViewController: picker)
        return navigationController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: LegacyVideoPickerView
        
        init(_ parent: LegacyVideoPickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            Task { @MainActor in
                picker.dismiss(animated: true) {
                    self.parent.dismiss()
                }
                
                guard let result = results.first else { return }
                
                if let assetIdentifier = result.assetIdentifier {
                    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
                    if let asset = fetchResult.firstObject {
                        self.parent.onVideoPicked(asset)
                    }
                }
            }
        }
    }
}
