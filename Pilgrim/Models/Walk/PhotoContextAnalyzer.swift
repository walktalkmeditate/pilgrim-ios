import UIKit
import Vision
import CoreImage
import Photos

/// Structured visual context extracted from a pinned reliquary photo
/// via on-device Vision framework analysis. Every field is derived
/// locally — nothing leaves the device. Fed into `PromptAssembler`
/// so the AI prompt references what the walker actually SAW, not
/// just where they went.
struct PhotoContext: Codable, Equatable {
    let tags: [String]
    let detectedText: [String]
    let people: Int
    let animals: [String]
    let outdoor: Bool
    let salientRegion: String
    let dominantColor: String
}

/// Runs all Vision + Core Image analysis on a single photo and
/// returns a `PhotoContext`. Results are cached in UserDefaults
/// keyed by the photo's `localIdentifier` so repeated calls
/// (e.g. re-opening the prompt screen) resolve instantly.
///
/// All processing is on-device. The analyzer is stateless — call
/// `analyze(localIdentifier:)` from any context; it dispatches
/// to a background queue internally and calls back on main.
enum PhotoContextAnalyzer {

    private static let cachePrefix = "photo_context_"

    // MARK: - Public API

    /// Analyzes a photo and returns its visual context. Returns a
    /// cached result immediately if available; otherwise runs the
    /// full Vision pipeline (~300-500ms) on a background queue.
    static func analyze(
        localIdentifier: String,
        completion: @escaping (PhotoContext?) -> Void
    ) {
        if let cached = cachedContext(for: localIdentifier) {
            completion(cached)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = loadImage(localIdentifier: localIdentifier) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let context = runAnalysis(on: image)

            cacheContext(context, for: localIdentifier)
            DispatchQueue.main.async { completion(context) }
        }
    }

    /// Synchronous variant for batch processing where the caller
    /// is already on a background queue. Returns nil if the photo
    /// can't be loaded (deleted, iCloud-only without local copy).
    static func analyzeSync(localIdentifier: String) -> PhotoContext? {
        if let cached = cachedContext(for: localIdentifier) {
            return cached
        }

        guard let image = loadImage(localIdentifier: localIdentifier) else {
            return nil
        }

        let context = runAnalysis(on: image)
        cacheContext(context, for: localIdentifier)
        return context
    }

    /// Analyzes a CGImage directly. Useful for tests (synthetic
    /// images) and for callers that already have the image in
    /// memory. Synchronous — runs the full Vision pipeline on
    /// the calling thread.
    static func analyzeImage(_ image: CGImage) -> PhotoContext {
        runAnalysis(on: image)
    }

    // MARK: - Cache

    static func cachedContext(for localIdentifier: String) -> PhotoContext? {
        let key = cachePrefix + localIdentifier.hashValue.description
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PhotoContext.self, from: data)
    }

    private static func cacheContext(_ context: PhotoContext, for localIdentifier: String) {
        let key = cachePrefix + localIdentifier.hashValue.description
        if let data = try? JSONEncoder().encode(context) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Image loading

    private static func loadImage(localIdentifier: String) -> CGImage? {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        guard let asset = fetchResult.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        options.resizeMode = .exact

        let targetSize = CGSize(width: 600, height: 600)

        var result: CGImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            result = image?.cgImage
        }
        return result
    }

    // MARK: - Vision pipeline

    private static func runAnalysis(on image: CGImage) -> PhotoContext {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        let classifyReq = VNClassifyImageRequest()
        let textReq = VNRecognizeTextRequest()
        textReq.recognitionLevel = .accurate
        let humanReq = VNDetectHumanRectanglesRequest()
        let animalReq = VNRecognizeAnimalsRequest()
        let horizonReq = VNDetectHorizonRequest()
        let saliencyReq = VNGenerateAttentionBasedSaliencyImageRequest()

        let requests: [VNRequest] = [
            classifyReq, textReq, humanReq,
            animalReq, horizonReq, saliencyReq
        ]

        try? handler.perform(requests)

        let tags = extractTags(from: classifyReq)
        let detectedText = extractText(from: textReq)
        let people = extractPeopleCount(from: humanReq)
        let animals = extractAnimals(from: animalReq)
        let outdoor = extractOutdoor(from: horizonReq)
        let salientRegion = extractSalientRegion(from: saliencyReq)
        let dominantColor = extractDominantColor(from: image)

        return PhotoContext(
            tags: tags,
            detectedText: detectedText,
            people: people,
            animals: animals,
            outdoor: outdoor,
            salientRegion: salientRegion,
            dominantColor: dominantColor
        )
    }

    // MARK: - Result extraction

    private static func extractTags(from request: VNClassifyImageRequest) -> [String] {
        guard let observations = request.results else { return [] }
        return observations
            .filter { $0.confidence > 0.3 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(8)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    private static func extractText(from request: VNRecognizeTextRequest) -> [String] {
        guard let observations = request.results else { return [] }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { $0.count <= 50 }
            .filter { !looksLikePersonalInfo($0) }
            .prefix(5)
            .map { String($0) }
    }

    private static func extractPeopleCount(from request: VNDetectHumanRectanglesRequest) -> Int {
        request.results?.count ?? 0
    }

    private static func extractAnimals(from request: VNRecognizeAnimalsRequest) -> [String] {
        guard let observations = request.results else { return [] }
        return observations
            .flatMap { $0.labels }
            .filter { $0.confidence > 0.3 }
            .map { $0.identifier.lowercased() }
    }

    private static func extractOutdoor(from request: VNDetectHorizonRequest) -> Bool {
        guard let result = request.results?.first else { return false }
        return result.confidence > 0.3
    }

    private static func extractSalientRegion(
        from request: VNGenerateAttentionBasedSaliencyImageRequest
    ) -> String {
        guard let observation = request.results?.first,
              let salientObjects = observation.salientObjects,
              let primary = salientObjects.first else {
            return "center"
        }

        let box = primary.boundingBox
        let cx = box.midX
        let cy = box.midY

        let horizontal: String
        if cx < 0.33 { horizontal = "left" }
        else if cx > 0.67 { horizontal = "right" }
        else { horizontal = "center" }

        let vertical: String
        if cy < 0.33 { vertical = "bottom" }
        else if cy > 0.67 { vertical = "top" }
        else { vertical = "center" }

        if horizontal == "center" && vertical == "center" { return "center" }
        if horizontal == "center" { return vertical }
        if vertical == "center" { return horizontal }
        return "\(vertical)-\(horizontal)"
    }

    private static func extractDominantColor(from image: CGImage) -> String {
        let ciImage = CIImage(cgImage: image)
        let extent = ciImage.extent

        guard let filter = CIFilter(name: "CIAreaAverage") else { return "#808080" }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(
            x: extent.origin.x,
            y: extent.origin.y,
            z: extent.size.width,
            w: extent.size.height
        ), forKey: "inputExtent")

        guard let output = filter.outputImage else { return "#808080" }

        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        var pixel = [UInt8](repeating: 0, count: 4)
        ctx.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return String(format: "#%02X%02X%02X", pixel[0], pixel[1], pixel[2])
    }

    // MARK: - Helpers

    private static func looksLikePersonalInfo(_ text: String) -> Bool {
        let phonePattern = #"\d{3}[-.\s]?\d{3}[-.\s]?\d{4}"#
        let emailPattern = #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+"#
        let urlPattern = #"https?://\S+"#

        return [phonePattern, emailPattern, urlPattern]
            .contains { text.range(of: $0, options: .regularExpression) != nil }
    }
}
