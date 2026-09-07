import Foundation
import Photos
import UIKit

/// Runs PhotoKit thumbnail requests on worker queues and turns the result
/// into a `malloc` RGBA buffer described in the reply.
final class NativeImageLoader {
    private let registry = NativeImageRequestRegistry()
    private let assetCache: NSCache<NSString, PHAsset> = {
        let cache = NSCache<NSString, PHAsset>()
        cache.countLimit = 10_000
        return cache
    }()

    /// On-screen thumbnails, local only.
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "photo_manager_native_image.local"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount * 2
        return queue
    }()

    /// Requests allowed to download from iCloud; kept narrow so a download
    /// never starves the local queue.
    private let networkQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "photo_manager_native_image.network"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    func request(
        assetId: String, requestId: Int64, targetSize: CGSize, allowNetwork: Bool,
        completion: @escaping (Result<NativeImageReply?, Error>) -> Void
    ) {
        let state = NativeImageRequestState(requestId: requestId, completion: completion)
        guard registry.register(state) else {
            state.finish(.success(nil))
            return
        }
        let worker = allowNetwork ? networkQueue : queue
        worker.addOperation { [weak self] in
            guard let self = self else {
                state.finish(.success(nil))
                return
            }
            let result = self.produce(state: state, assetId: assetId, targetSize: targetSize, allowNetwork: allowNetwork)
            self.registry.remove(requestId: requestId)
            state.finish(result)
        }
    }

    func cancel(requestId: Int64) {
        registry.cancel(requestId: requestId)
    }

    func cancelAll() {
        for state in registry.cancelAll() {
            state.finish(.success(nil))
        }
        queue.cancelAllOperations()
        networkQueue.cancelAllOperations()
    }

    // MARK: - Worker

    private func produce(
        state: NativeImageRequestState, assetId: String, targetSize: CGSize, allowNetwork: Bool
    ) -> Result<NativeImageReply?, Error> {
        if state.isCancelled { return .success(nil) }
        guard let asset = fetchAsset(assetId) else {
            return .failure(NativeImageError(code: "not_found", message: "No asset with id \(assetId).", details: nil))
        }
        if state.isCancelled { return .success(nil) }

        var outcome = requestImage(asset: asset, targetSize: targetSize, allowNetwork: allowNetwork)
        if case .failure(let error) = outcome, Self.isConnectionInvalidated(error) {
            // The photo daemon dropped the XPC connection; a cached PHAsset
            // stays dead, so fetch it again and retry once.
            assetCache.removeObject(forKey: assetId as NSString)
            guard let fresh = fetchAsset(assetId) else {
                return .failure(NativeImageError(code: "not_found", message: "No asset with id \(assetId).", details: nil))
            }
            outcome = requestImage(asset: fresh, targetSize: targetSize, allowNetwork: allowNetwork)
        }

        let image: UIImage
        switch outcome {
        case .failure(let error):
            return .failure(error)
        case .success(let value):
            image = value
        }
        if state.isCancelled { return .success(nil) }

        // No cancel checks past this point: the buffer is Dart's to free.
        guard let cgImage = PixelBufferFactory.uprightCGImage(image) else {
            return .failure(NativeImageError(code: "decode_failed", message: "No CGImage.", details: nil))
        }
        do {
            let buffer = try PixelBufferFactory.make(from: cgImage, target: targetSize)
            return .success(buffer.reply)
        } catch {
            return .failure(NativeImageError(code: "decode_failed", message: "\(error)", details: nil))
        }
    }

    private func fetchAsset(_ assetId: String) -> PHAsset? {
        if let cached = assetCache.object(forKey: assetId as NSString) {
            return cached
        }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            return nil
        }
        assetCache.setObject(asset, forKey: assetId as NSString)
        return asset
    }

    private func requestImage(asset: PHAsset, targetSize: CGSize, allowNetwork: Bool) -> Result<UIImage, Error> {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = true
        options.version = .current
        options.isNetworkAccessAllowed = allowNetwork

        var result: Result<UIImage, Error> = .failure(
            NativeImageError(code: "decode_failed", message: "PhotoKit returned no image.", details: nil))
        PHImageManager.default().requestImage(
            for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options
        ) { image, info in
            if let image = image {
                result = .success(image)
                return
            }
            let error = info?[PHImageErrorKey] as? NSError
            let inCloud = (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue ?? false
            if inCloud || Self.isNetworkRequired(error) {
                result = .failure(NativeImageError(
                    code: "icloud_not_downloaded",
                    message: "The original is in iCloud; retry with allowNetwork.", details: nil))
            } else if let error = error {
                result = .failure(error)
            }
        }
        return result
    }

    static func isConnectionInvalidated(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let error = current {
            if error.domain == NSCocoaErrorDomain
                && (error.code == NSXPCConnectionInterrupted || error.code == NSXPCConnectionInvalid) {
                return true
            }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// `PHPhotosError.networkAccessRequired` (3164), spelled out because the
    /// enum case only exists from iOS 14.
    static func isNetworkRequired(_ error: NSError?) -> Bool {
        guard let error = error else { return false }
        return error.domain == PHPhotosErrorDomain && error.code == 3164
    }
}
