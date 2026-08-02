import AppKit
import SwiftData
import SwiftUI

/// The surface that hangs from the notch.
///
/// Deliberately a different shape from the floating panel: that one is a
/// vertical list you read down, this is a horizontal strip you scan across. It
/// is meant to be glanced at and grabbed from, so recent clips are big, and the
/// first ten carry a ⌃⌘0–9 badge you can hit without aiming.
struct NotchView: View {
    @Query(notchClipsDescriptor) private var clips: [Clip]
    @Environment(\.modelContext) private var modelContext

    let monitor: ClipboardMonitor?
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedKind: ClipKind?
    @State private var hoveredID: UUID?
    @State private var isTargetedForDrop = false

    @Bindable private var settings = AppSettings.shared

    private var store: ClipStore {
        ClipStore(context: modelContext, settings: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Leaves the physical notch itself uncovered — the panel reads as
            // hanging *from* the notch rather than sitting on top of it.
            Color.clear.frame(height: notchInset)

            VStack(alignment: .leading, spacing: 10) {
                topBar
                dayStrip
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                // Square across the top so it meets the screen edge cleanly,
                // rounded below where it hangs into the desktop.
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(.black.opacity(0.86))
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .strokeBorder(isTargetedForDrop ? Theme.accent : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Drop anything onto the notch to file it, which is the other half of
        // why the surface is worth reaching for.
        .onDrop(of: [.fileURL, .image, .text], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers)
        }
        .preferredColorScheme(.dark)
    }

    /// Height of the physical notch on this screen, or a small lip when there
    /// isn't one.
    private var notchInset: CGFloat {
        guard let screen = NotchGeometry.screenUnderCursor() else { return 0 }
        return NotchGeometry.notchRect(on: screen)?.height ?? 0
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.08)))
            .frame(width: 200)

            kindChip(label: "All", kind: nil)
            ForEach(availableKinds, id: \.self) { kind in
                kindChip(label: kind.displayName, kind: kind)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func kindChip(label: String, kind: ClipKind?) -> some View {
        let isActive = selectedKind == kind

        return Button {
            withAnimation(Theme.standardSpring) { selectedKind = kind }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .medium : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isActive ? .black : .white.opacity(0.65))
                .background(Capsule().fill(isActive ? .white : .white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Strip

    @ViewBuilder
    private var dayStrip: some View {
        if filteredClips.isEmpty {
            emptyState
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(groupedByDay, id: \.label) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))

                            HStack(spacing: 8) {
                                ForEach(group.clips, id: \.id) { clip in
                                    NotchCard(
                                        clip: clip,
                                        shortcutIndex: shortcutIndex(for: clip),
                                        isHovered: hoveredID == clip.id,
                                        onSelect: { paste(clip) },
                                        onTogglePin: { store.togglePin(clip) }
                                    )
                                    .onHover { hovering in
                                        hoveredID = hovering ? clip.id : nil
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.35))

            Text(searchText.isEmpty
                 ? "Nothing here yet — copy something, or drop a file on the notch."
                 : "No clips match “\(searchText)”.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    // MARK: - Data

    private var filteredClips: [Clip] {
        clips.filter { clip in
            if let selectedKind, clip.kind != selectedKind.rawValue { return false }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }

            return [clip.title, clip.text, clip.ocrText]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(query) }
        }
    }

    private var availableKinds: [ClipKind] {
        let present = Set(clips.map(\.kind))
        return ClipKind.allCases.filter { present.contains($0.rawValue) }
    }

    private struct DayGroup {
        let label: String
        let clips: [Clip]
    }

    /// "Today", "Yesterday", then dates — the same grouping the eye already
    /// uses when scanning back through a day's work.
    private var groupedByDay: [DayGroup] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [Clip]] = [:]

        for clip in filteredClips {
            let day = calendar.startOfDay(for: clip.createdAt)
            if buckets[day] == nil {
                buckets[day] = []
                order.append(day)
            }
            buckets[day]?.append(clip)
        }

        return order.map { day in
            DayGroup(label: Self.dayLabel(for: day, calendar: calendar), clips: buckets[day] ?? [])
        }
    }

    private static func dayLabel(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: day)
    }

    /// The first ten visible clips get a ⌃⌘0–9 badge.
    private func shortcutIndex(for clip: Clip) -> Int? {
        guard let index = filteredClips.firstIndex(where: { $0.id == clip.id }), index < 10 else {
            return nil
        }
        return index
    }

    // MARK: - Actions

    private func paste(_ clip: Clip) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch ClipKind(rawValue: clip.kind) ?? .text {
        case .image:
            guard let image = FileStorage.loadImage(named: clip.imageFilename) else { return }
            pasteboard.writeObjects([image])
        case .file:
            let urls = (clip.text ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) as NSURL }
            guard !urls.isEmpty else { return }
            pasteboard.writeObjects(urls)
        default:
            guard let text = clip.text else { return }
            pasteboard.setString(text, forType: .string)
        }

        monitor?.acknowledgeSelfCopy()
        store.recordUse(of: clip)
        onDismiss()
    }

    /// Files, images and text dropped on the notch become clips, filed as
    /// coming from "Drop" rather than from whatever app happened to be in front.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        if let image = NSImage(contentsOf: url) {
                            store.insertImage(image, sourceAppName: "Drop", sourceAppBundleID: nil)
                        } else {
                            store.insertText(
                                url.path,
                                kind: .file,
                                sourceAppName: "Drop",
                                sourceAppBundleID: nil
                            )
                        }
                    }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let text = value as? String else { return }
                    Task { @MainActor in
                        store.insertText(
                            text,
                            kind: ClipKind.detect(text: text),
                            sourceAppName: "Drop",
                            sourceAppBundleID: nil
                        )
                    }
                }
            }
        }
        return true
    }
}

/// Newest clips only — the notch is a glance surface, not the full archive.
private let notchClipsDescriptor: FetchDescriptor<Clip> = {
    var descriptor = FetchDescriptor<Clip>(
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = 60
    return descriptor
}()
