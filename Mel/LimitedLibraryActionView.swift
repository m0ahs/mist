import SwiftUI
import Photos
import UIKit

struct LimitedLibraryActionView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Accès limité aux photos")
                .font(.subheadline.weight(.semibold))
            Text("Tu ne vois que les images déjà autorisées. Ajoute d’autres photos ou autorise l’accès complet.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button("Choisir d’autres photos") {
                    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let root = scene.keyWindow?.rootViewController else { return }
                    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
                }
                .buttonStyle(.bordered)

                Button("Autoriser toutes les photos") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { self.windows.first { $0.isKeyWindow } }
}
