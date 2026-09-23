import Foundation
import SwiftData
import Vision

/// Reads the text out of images with Vision and writes it into
/// `Clip.ocrText`, where search finds it.
///
/// One rule shapes all of it: recognition never blocks a capture. The clip is
/// saved and visible before recognition starts; the text arrives a moment
/// later. If recognition fails, the clip is still there — just not searchable
/// by what is inside it.
@MainActor
final class OCRService {
    /// Serial and `.utility`: one image at a time, at a priority the system is
    /// free to push back — a burst of screenshots must not pin the CPU.
    private static let queue = DispatchQueue(label: "com.sagarmohansingh.cache.ocr", qos: .utility)

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func enqueue(_ clip: Clip) {
        guard let url = FileStorage.url(for: clip.imageFilename) else { return }

        // Only an opaque identifier and a URL cross threads. The model object
        // belongs to the main context and must stay on the main actor.
        let identifier = clip.persistentModelID

        Self.queue.async {
            let recognized = Self.recognizeText(at: url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(recognized ?? "", to: identifier) }
            }
        }
    }

    /// Anything captured before recognition existed, or that failed.
    func backfill() {
        let descriptor = FetchDescriptor<Clip>(predicate: #Predicate { $0.kind == "image" && $0.ocrText == nil })
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }
        NSLog("Cache: reading text in \(pending.count) older image(s)")
        pending.forEach(enqueue)
    }

    /// The clip may have been deleted while recognition ran; that is fine.
    private func apply(_ text: String, to identifier: PersistentIdentifier) {
        guard let clip = context.model(for: identifier) as? Clip, !clip.isDeleted else { return }
        // Empty is written on purpose: it records "looked, found nothing", so
        // the backfill never rescans the same textless picture every launch.
        clip.ocrText = text
        try? context.save()
    }

    private nonisolated static func recognizeText(at url: URL) -> String? {
        let request = VNRecognizeTextRequest()
        // Wrong text in a search index is worse than late text.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        do {
            try VNImageRequestHandler(url: url, options: [:]).perform([request])
        } catch {
            NSLog("Cache: text recognition failed — \(error.localizedDescription)")
            return nil
        }

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
