import Foundation
import SwiftData
import Vision

/// Reads text out of image clips with the Vision framework and writes it back
/// into `Clip.ocrText`, where search picks it up.
///
/// Everything about this is shaped by one rule: OCR must never block a capture.
/// Recognition happens on a background queue, the insert has already been saved
/// by the time we start, and the result is written back later. If OCR is slow or
/// fails outright, the clip is still in the list — it just isn't searchable by
/// its contents.
@MainActor
final class OCRService {
    /// Serial and `.utility`: one image at a time, at a priority the system is
    /// free to deprioritise. A concurrent queue here would let a burst of
    /// screenshots saturate the CPU of an app that's meant to be invisible.
    private static let queue = DispatchQueue(
        label: "com.sagarmohansingh.supaclip.ocr",
        qos: .utility
    )

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Queue a clip for recognition. Returns immediately.
    func enqueue(_ clip: Clip) {
        guard let filename = clip.imageFilename else { return }

        // Capture only what's safe to send across threads: an opaque row
        // identifier and a file URL. The `Clip` object itself belongs to the
        // main actor's context and must not leave it.
        let identifier = clip.persistentModelID
        let url = FileStorage.clipsDirectory.appendingPathComponent(filename)

        Self.queue.async {
            let recognized = Self.recognizeText(at: url) ?? ""

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // An empty string is written deliberately: it records
                    // "recognition ran and found nothing", which is different
                    // from nil meaning "never attempted". Backfill relies on
                    // that distinction to avoid re-scanning textless images on
                    // every launch.
                    self.apply(recognized, to: identifier)
                }
            }
        }
    }

    /// Recognise anything that was captured before OCR existed, or that failed.
    ///
    /// Runs once at launch on the same serial queue as live captures, so an old
    /// history catches up in the background without competing with new copies.
    func backfill() {
        let descriptor = FetchDescriptor<Clip>(
            predicate: #Predicate { $0.kind == "image" && $0.ocrText == nil }
        )

        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        NSLog("SupaClip: recognising text in \(pending.count) older image(s)")
        for clip in pending {
            enqueue(clip)
        }
    }

    /// Look the row back up by identifier — the clip may well have been pruned
    /// or deleted while recognition was running, and that's fine.
    private func apply(_ text: String, to identifier: PersistentIdentifier) {
        guard let clip = context.model(for: identifier) as? Clip else { return }

        clip.ocrText = text
        try? context.save()
    }

    // MARK: - Vision

    /// `nonisolated` and static so it can run off the main actor without
    /// dragging any of this class's state with it.
    private nonisolated static func recognizeText(at url: URL) -> String? {
        let request = VNRecognizeTextRequest()
        // `.accurate` is slower than `.fast` but this is background work, and
        // wrong text in a search index is worse than late text.
        //
        // Measured: the first recognition loads Vision's models into this
        // process and they stay resident — 78MB idle becomes 163MB with
        // `.accurate`, 132MB with `.fast`. Since neither fits the 80MB budget,
        // `.fast` would trade accuracy for nothing. The only real fix is moving
        // recognition into a separate short-lived process.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(url: url, options: [:])

        do {
            try handler.perform([request])
        } catch {
            NSLog("SupaClip: OCR failed — \(error.localizedDescription)")
            return nil
        }

        guard let observations = request.results else { return nil }

        // Each observation is one detected line; `topCandidates(1)` is Vision's
        // best guess for that line.
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
