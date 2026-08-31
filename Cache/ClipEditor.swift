import AppKit
import SwiftUI

/// Edit a single clip: rename it, change its text, act on an image, set a reminder.
struct ClipEditor: View {
    let clip: Clip
    let store: ClipStore
    let onClose: () -> Void

    @State private var title: String = ""
    @State private var text: String = ""

    @State private var hasReminder = false
    @State private var reminderDate = Date().addingTimeInterval(3600)

    @State private var resizeMaxEdge: Double = 1000
    @State private var exportFormat: ImageFormat = .png
    @State private var statusMessage: String?

    private var kind: ClipKind { ClipKind(rawValue: clip.kind) ?? .text }
    private var isImage: Bool { kind == .image }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isImage ? "Edit Image Clip" : "Edit Clip")
                .font(.system(size: 13, weight: .medium))

            titleField

            if isImage {
                imageSection
            } else {
                textSection
            }

            reminderSection

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(width: 420, height: 480)
        .onAppear(perform: load)
    }

    // MARK: - Sections

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Title")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Optional — shown instead of the contents", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Content")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Editing the text re-runs kind detection on save, so turning a
            // sentence into "#FF0000" reclassifies it as a colour.
            TextEditor(text: $text)
                .font(.system(size: 12, design: kind == .code ? .monospaced : .default))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                )
                .frame(height: 160)
        }
    }

    @ViewBuilder
    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let thumbnail = ThumbnailCache.thumbnail(named: clip.thumbnailFilename) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
            }

            if let size = fullImage.flatMap(FileStorage.pixelSize) {
                Text("\(Int(size.width)) × \(Int(size.height)) px")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Recognised text is already indexed for search; this makes it
            // usable — the whole point of OCR'ing a screenshot of a receipt.
            if let ocrText = clip.ocrText, !ocrText.isEmpty {
                Button("Copy recognized text") { copyRecognizedText(ocrText) }
                    .font(.system(size: 12))
            } else {
                Text("No text recognized in this image.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 8) {
                Text("Resize")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Slider(value: $resizeMaxEdge, in: 100...4000, step: 100)

                Text("\(Int(resizeMaxEdge))px")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Picker("Format", selection: $exportFormat) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 90)

                Button("Copy resized") { exportResized(toPasteboard: true) }
                    .font(.system(size: 12))

                Button("Save to Downloads…") { exportResized(toPasteboard: false) }
                    .font(.system(size: 12))
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $hasReminder) {
                Text("Remind me about this clip")
                    .font(.system(size: 13))
            }
            .toggleStyle(.switch)
            .tint(Theme.accent)

            if hasReminder {
                DatePicker("", selection: $reminderDate, in: Date()...)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onClose)
            Button("Save", action: save)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private func load() {
        title = clip.title ?? ""
        text = clip.text ?? ""

        if let existing = clip.reminderAt {
            hasReminder = true
            reminderDate = existing
        }

        if let size = fullImage.flatMap(FileStorage.pixelSize) {
            resizeMaxEdge = Double(max(size.width, size.height))
        }
    }

    private var fullImage: NSImage? {
        FileStorage.loadImage(named: clip.imageFilename)
    }

    private func save() {
        store.updateTitle(title, on: clip)

        if !isImage, text != (clip.text ?? "") {
            store.updateText(text, on: clip)
        }

        let newReminder = hasReminder ? reminderDate : nil
        if newReminder != clip.reminderAt {
            store.setReminder(newReminder, on: clip)
            if newReminder == nil {
                ReminderService.cancel(for: clip)
            } else {
                Task { await ReminderService.schedule(for: clip) }
            }
        }

        onClose()
    }

    private func copyRecognizedText(_ ocrText: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ocrText, forType: .string)
        statusMessage = "Recognized text copied."
    }

    private func exportResized(toPasteboard: Bool) {
        guard let image = fullImage else { return }

        let resized = FileStorage.makeThumbnail(from: image, maxEdge: CGFloat(resizeMaxEdge))
        guard let data = FileStorage.encode(resized, as: exportFormat) else {
            statusMessage = "Could not encode the image."
            return
        }

        if toPasteboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let converted = NSImage(data: data) {
                pasteboard.writeObjects([converted])
                statusMessage = "Resized image copied."
            }
            return
        }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = (clip.title?.isEmpty == false ? clip.title! : "cache-image")
        let url = downloads.appendingPathComponent("\(name).\(exportFormat.fileExtension)")

        do {
            try data.write(to: url)
            statusMessage = "Saved to Downloads/\(url.lastPathComponent)"
        } catch {
            statusMessage = "Could not save: \(error.localizedDescription)"
        }
    }
}
