import SwiftUI

/// The whole notch window: one black shape that is the notch when closed,
/// widens to confirm a copy, and grows into the panel when opened.
///
/// The content is laid out at full size all the time and only *revealed* by
/// the shape as it grows, so opening animates a mask — cheap — instead of
/// re-laying-out the strip on every frame.
struct NotchRootView: View {
    @Bindable var model: NotchModel
    let actions: ClipActions
    let watcher: ScreenshotWatcher
    let settings: AppSettings

    var body: some View {
        let metrics = model.metrics
        let silhouette = model.silhouette
        let isOpen = model.phase == .open

        ZStack(alignment: .top) {
            NotchShape(shoulderRadius: silhouette.shoulder, bottomRadius: silhouette.bottom)
                .fill(Theme.ink)
                .frame(width: silhouette.width, height: silhouette.height)

            if model.phase == .peek, let peek = model.peek {
                PeekView(peek: peek, metrics: metrics)
                    .transition(.opacity)
            }

            NotchContentView(model: model, actions: actions, watcher: watcher, settings: settings)
                .frame(width: metrics.panelSize.width, height: metrics.panelSize.height)
                .opacity(isOpen ? 1 : 0)
                .scaleEffect(isOpen || Theme.reduceMotion ? 1 : 0.96, anchor: .top)
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
        }
        .frame(width: metrics.panelSize.width, height: metrics.panelSize.height, alignment: .top)
        .mask(alignment: .top) {
            NotchShape(shoulderRadius: silhouette.shoulder, bottomRadius: silhouette.bottom)
                .frame(width: silhouette.width, height: silhouette.height)
        }
        .environment(\.colorScheme, .dark)
    }
}
