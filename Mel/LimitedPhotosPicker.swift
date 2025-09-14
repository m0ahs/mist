import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

struct LimitedPhotosPicker: UIViewControllerRepresentable {
    let maxSelection: Int
    let onPicked: ([Data]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = max(0, maxSelection)
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: LimitedPhotosPicker
        init(_ parent: LimitedPhotosPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.dismiss()
                return
            }

            var datas: [Data] = []
            let group = DispatchGroup()

            for result in results {
                let provider = result.itemProvider
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        if let data {
                            if let downsized = earlyDownscale(data: data) { datas.append(downsized) }
                            else { datas.append(data) }
                        }
                        group.leave()
                    }
                } else if provider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    provider.loadObject(ofClass: UIImage.self) { obj, _ in
                        defer { group.leave() }
                        guard let img = obj as? UIImage else { return }
                        if let cg = img.cgImage {
                            let out = CFDataCreateMutable(nil, 0)!
                            if let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) {
                                let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.82]
                                CGImageDestinationAddImage(dest, cg, opts as CFDictionary)
                                if CGImageDestinationFinalize(dest) {
                                    let d = out as Data
                                    if let downsized = earlyDownscale(data: d) { datas.append(downsized) }
                                    else { datas.append(d) }
                                }
                            }
                        }
                    }
                }
            }

            group.notify(queue: .main) {
                self.parent.onPicked(datas)
                self.parent.dismiss()
            }
        }
    }
}
