import SwiftUI

/// Search field plus the kind / source-app filter chips.
struct FilterBar: View {
    @Binding var searchText: String
    @Binding var selectedKind: ClipKind?
    @Binding var selectedAppBundleID: String?
    @Binding var selectedCategory: String?

    /// Kinds actually present in the current history — no point offering a
    /// "Colors" chip when nothing is a colour.
    let availableKinds: [ClipKind]
    let availableApps: [SourceApp]
    let availableCategories: [String]

    /// Owned by ContentView so the field can be focused the instant the panel opens.
    @FocusState.Binding var isSearchFocused: Bool

    struct SourceApp: Identifiable, Hashable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    private var hasFilters: Bool {
        !availableKinds.isEmpty || !availableApps.isEmpty || !availableCategories.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            searchField

            if hasFilters {
                chips
            }
        }
        .padding(.horizontal, Theme.windowPadding)
        .padding(.top, Theme.windowPadding)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(availableCategories, id: \.self) { category in
                    chip(
                        label: category,
                        symbol: "folder",
                        isActive: selectedCategory == category
                    ) {
                        withAnimation(Theme.standardSpring) {
                            selectedCategory = (selectedCategory == category) ? nil : category
                        }
                    }
                }

                if !availableCategories.isEmpty && !availableKinds.isEmpty {
                    Divider().frame(height: 12)
                }

                ForEach(availableKinds, id: \.self) { kind in
                    chip(
                        label: kind.displayName,
                        symbol: kind.symbolName,
                        isActive: selectedKind == kind
                    ) {
                        withAnimation(Theme.standardSpring) {
                            selectedKind = (selectedKind == kind) ? nil : kind
                        }
                    }
                }

                if !availableKinds.isEmpty && !availableApps.isEmpty {
                    Divider().frame(height: 12)
                }

                ForEach(availableApps) { app in
                    chip(
                        label: app.name,
                        symbol: nil,
                        isActive: selectedAppBundleID == app.bundleID
                    ) {
                        withAnimation(Theme.standardSpring) {
                            selectedAppBundleID = (selectedAppBundleID == app.bundleID) ? nil : app.bundleID
                        }
                    }
                }
            }
            .padding(.horizontal, 1)   // keeps chip borders from clipping
        }
        .frame(height: 24)
    }

    private func chip(
        label: String,
        symbol: String?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9))
                }
                Text(label).font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .background(
                Capsule().fill(isActive ? Theme.accent : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(isActive ? Color.clear : Theme.cardBorder, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
