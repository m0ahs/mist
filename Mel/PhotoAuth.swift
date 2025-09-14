import Photos

enum PhotoAuthState {
    case notDetermined, limited, authorized, denied
}

func currentPhotoAuthState() -> PhotoAuthState {
    let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    switch s {
    case .notDetermined: return .notDetermined
    case .limited:       return .limited
    case .authorized:    return .authorized
    case .denied, .restricted: return .denied
    @unknown default:    return .denied
    }
}

func requestPhotoAccessIfNeeded(_ completion: @escaping (PhotoAuthState) -> Void) {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    if status == .notDetermined {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
            DispatchQueue.main.async { completion(currentPhotoAuthState()) }
        }
    } else {
        completion(currentPhotoAuthState())
    }
}
