import SwiftUI
import UIKit

/// One window's root: the Console (#8), with Host management (#14) behind it.
///
/// The stores behind it are app-wide (`HeelerAppModel`); what a window owns
/// is its navigation. On iPad every window is a scene with its own router,
/// so two windows can show two Agents, and each restores its own Agent after
/// the app is terminated: first from its scene storage, else from the value
/// the window was opened with, else from a dragged row's user activity.
struct ContentView: View {
    let app: HeelerAppModel
    /// The `WindowGroup` value: the Agent this window was opened on, kept in
    /// step with the window's navigation so opening that Agent again finds
    /// this window.
    @Binding var windowRoute: AgentRoute?
    @StateObject private var notificationRouter = AgentNotificationRouter()
    @State private var sceneID = UUID()
    @StateObject private var window = WindowReference()
    /// A dragged row's Agent that reached this scene before it restored.
    @State private var incomingActivityRoute: AgentRoute?
    @State private var hasRestoredRoute = false
    /// Replaced once restoration knows whether this window is new.
    @State private var activation = SceneActivationTracker(isRestored: false)
    /// `AgentRoute.sceneStorageValue`; nil while the window shows the Console.
    @SceneStorage("dev.bybee.heeler.agentRoute") private var storedRoute: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ConsoleView(
            hosts: app.hostStore, console: app.console, terminal: app.terminal,
            inputMode: app.inputMode,
            detailSurface: app.detailSurface,
            appearance: app.appearance,
            pushRegistration: app.pushRegistration,
            notificationPreferences: app.notificationPreferences,
            relaySettings: app.relaySettings,
            notificationRouter: notificationRouter,
            bannerStore: app.bannerStore,
            liveActivities: app.liveActivities,
            activity: app.activity
        )
        // Settings › Overlay Networks and the Host form read the catalog here.
        .environmentObject(app.overlayNetworks)
        .environment(\.overlayNetworkStore, app.overlayNetworks)
        // The Composer's mic and Settings › Voice Input.
        .environmentObject(app.voiceInput)
        .environment(\.voiceInputSession, app.voiceInput)
        // Settings › Overlay Networks adds a Host from a network's peer.
        .environmentObject(app.hostStore)
        .environment(\.hostStoreOptional, app.hostStore)
        // The Hosts list's removal reaches app-wide state.
        .environment(\.hostRemovalDependencies, app.hostRemoval)
        // Host detail's Helper actions reach what follows the Helper.
        .environment(\.hostOnboardingDependencies, app.hostOnboarding)
        .environment(\.sceneWindow, window)
        .environment(
            \.agentSceneRouting,
            AgentSceneRouting(directory: app.sceneDirectory, sceneID: sceneID))
        // The one place the app's light or dark is applied: it lands on the
        // window, so sheets, pushed screens, and the UIKit terminal surfaces
        // all resolve against it.
        .appAppearance(app.appearance, themes: app.terminal.themes)
        .background {
            WindowReader { window.attach($0) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear {
            // Restored first, so a notification tap that launched the app
            // and is waiting for a window lands on top of it when the window
            // registers. A dragged row's Agent needs the registration to
            // route through the single-window rule, so it goes last.
            let draggedRoute = restoreRoute()
            app.console.sceneDidStart(sceneID)
            app.sceneDirectory.register(
                sceneID: sceneID, router: notificationRouter, window: window,
                activate: { activateWindow() })
            window.observeInteraction { [directory = app.sceneDirectory, sceneID] in
                directory.sceneDidReceiveInteraction(sceneID: sceneID)
            }
            if scenePhase == .active {
                sceneDidBecomeActive()
            }
            if let draggedRoute {
                app.sceneDirectory.open(draggedRoute.target, preferredSceneID: sceneID)
            }
            app.start()
        }
        .onDisappear {
            app.sceneDirectory.unregister(sceneID: sceneID)
            app.console.sceneDidEnd(sceneID)
        }
        // A foreground return is not the user choosing this window; see
        // `SceneActivationTracker`. Moving between windows arrives through
        // `observeInteraction` instead.
        .onChangeCompat(of: scenePhase) { _, phase in
            if phase == .active {
                sceneDidBecomeActive()
            }
        }
        // Feeds the Console's Agent list to this window's router, so a
        // notification tap that arrived before the Hosts synced (killed-state
        // launch) routes the moment its pane appears.
        .onChangeCompat(of: app.console.agents, initial: true) { _, _ in
            notificationRouter.agentsDidChange(app.console.agents)
            app.sceneDirectory.sceneRouteDidChange(sceneID: sceneID)
        }
        // Every navigation is written back, so a relaunch restores the Agent
        // this window was last on.
        .onChangeCompat(of: notificationRouter.path) { _, path in
            let route = path.last.map(AgentRoute.init(agentID:))
            storedRoute = route?.sceneStorageValue
            if windowRoute != route {
                windowRoute = route
            }
            app.sceneDirectory.sceneRouteDidChange(sceneID: sceneID)
        }
        // Live Activity row links name an Agent; surrounding chrome,
        // compact, and minimal presentations name only the Host and land on
        // the Console. Another app's link names its Host by address or name,
        // which the saved Hosts resolve.
        .onOpenURL { url in
            guard let link = AgentActivityLink.target(from: url) else { return }
            app.sceneDirectory.open(
                link.agent(in: app.hostStore.hosts), preferredSceneID: sceneID)
        }
        .onContinueUserActivity(AgentRoute.activityType) { activity in
            guard let route = AgentRoute(userActivity: activity) else { return }
            if hasRestoredRoute {
                app.sceneDirectory.open(route.target, preferredSceneID: sceneID)
            } else {
                incomingActivityRoute = route
            }
        }
        // An existing window prefers Heeler's own links, so a Live Activity
        // tap lands in a window that is already open instead of spawning
        // one. A dragged row's activity is not a `heeler://` link, so it
        // still gets the new window it was dropped to create.
        .handlesExternalEvents(
            preferring: [Self.linkEventPrefix], allowing: ["*"])
    }

    private static let linkEventPrefix = "\(AgentActivityLink.scheme)://"

    /// Counts only a newly opened window's first activation as the user
    /// working in it.
    private func sceneDidBecomeActive() {
        guard activation.sceneDidBecomeActive() else { return }
        app.sceneDirectory.sceneDidBecomeActive(sceneID: sceneID)
    }

    /// Applies the restoration precedence once, on the window's first
    /// appearance. A stored or window-value route is placed on the path
    /// directly rather than through `open`: the Agent detail then shows the
    /// Host connecting and the Agent loading, and says so if the pane is
    /// gone, instead of quietly falling back to the Console after a grace
    /// period. A dragged row's route is returned for the caller to open once
    /// this window is registered.
    private func restoreRoute() -> AgentRoute? {
        guard !hasRestoredRoute else { return nil }
        hasRestoredRoute = true
        let incoming = incomingActivityRoute
        incomingActivityRoute = nil
        let restoration = SceneRouteRestoration.resolve(
            sceneStorage: storedRoute, windowValue: windowRoute, userActivity: incoming)
        // A window back from its own scene storage is one the system
        // restored, not one the user just opened.
        activation = SceneActivationTracker(isRestored: restoration?.source == .sceneStorage)
        guard let restoration else { return nil }
        switch restoration.source {
        case .sceneStorage, .windowValue:
            notificationRouter.path = [restoration.route.agentID]
            return nil
        case .userActivity:
            return restoration.route
        }
    }

    /// Brings this window forward when a deep link picks it. A no-op for the
    /// window the user is already in.
    private func activateWindow() {
        guard let scene = window.window?.windowScene,
            scene.activationState != .foregroundActive
        else { return }
        if #available(iOS 17, *) {
            UIApplication.shared.activateSceneSession(
                for: UISceneSessionActivationRequest(session: scene.session),
                errorHandler: nil)
        } else {
            UIApplication.shared.requestSceneSessionActivation(
                scene.session, userActivity: nil, options: nil, errorHandler: nil)
        }
    }
}

#Preview {
    ContentView(
        app: HeelerAppModel(
            pushRegistration: PushRegistrationStore(), sceneDirectory: AgentSceneDirectory()),
        windowRoute: .constant(nil))
}


// iOS 16: fallbacks for SwiftUI APIs newer than iOS 16.0.
extension View {
    @ViewBuilder func fontDesignCompat(_ design: Font.Design?) -> some View {
        if #available(iOS 16.1, *) { self.fontDesign(design) } else { self }
    }
    @ViewBuilder func scrollBounceBasedOnSizeCompat() -> some View {
        if #available(iOS 16.4, *) { self.scrollBounceBehavior(.basedOnSize) } else { self }
    }
    @ViewBuilder func listSectionSpacingCompactCompat() -> some View {
        if #available(iOS 17, *) { self.listSectionSpacing(.compact) } else { self }
    }
    @ViewBuilder func contentMarginsTopCompat(_ length: CGFloat) -> some View {
        if #available(iOS 17, *) { self.contentMarginsCompat(.top, length) } else { self }
    }
    @ViewBuilder func scrollIndicatorsFlashCompat(onAppear: Bool) -> some View {
        if #available(iOS 17, *) { self.scrollIndicatorsFlash(onAppear: onAppear) } else { self }
    }
    @ViewBuilder func defaultScrollAnchorBottomCompat() -> some View {
        if #available(iOS 17, *) { self.defaultScrollAnchor(.bottom) } else { self }
    }
    @ViewBuilder func selectionDisabledCompat() -> some View {
        if #available(iOS 17, *) { self.selectionDisabled() } else { self }
    }
    @ViewBuilder func presentationSizingFormCompat() -> some View {
        if #available(iOS 18, *) { self.presentationSizing(.form) } else { self }
    }
    /// iOS 17's two-value `onChange(of:)`. The first call after appear is not delivered.
    func onChangeCompat<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View {
        modifier(OnChangeCompat(value: value, initial: initial, action: action))
    }
}

extension Text {
    func fontDesignCompat(_ design: Font.Design?) -> Text {
        if #available(iOS 16.1, *) { return self.fontDesign(design) } else { return self }
    }
}

private struct OnChangeCompat<V: Equatable>: ViewModifier {
    let value: V
    let initial: Bool
    let action: (V, V) -> Void
    @State private var previous: V?
    @State private var latest = LatestAction()
    func body(content: Content) -> some View {
        latest.action = action
        return content
            .onAppear { previous = value; if initial { action(value, value) } }
            .onChange(of: value) { new in
                let old = previous ?? new
                previous = new
                // iOS 16 runs the closure from the previous render, whose captured
                // `action` reads stale view values; the box holds this render's.
                (latest.action ?? action)(old, new)
            }
    }

    private final class LatestAction {
        var action: ((V, V) -> Void)?
    }
}

/// Stand-in for `ContentUnavailableView` (iOS 17).
struct CompatUnavailableView<Label: View, Description: View, Actions: View>: View {
    let label: Label
    let description: Description
    let actions: Actions
    init(@ViewBuilder label: () -> Label,
         @ViewBuilder description: () -> Description = { EmptyView() },
         @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.label = label(); self.description = description(); self.actions = actions()
    }
    var body: some View {
        VStack(spacing: 8) {
            label.font(.title2.weight(.semibold)).labelStyle(CompatUnavailableLabelStyle())
            description.font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
            actions
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension CompatUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text, Actions == EmptyView {
    init(verbatim title: String, systemImage: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, systemImage: systemImage) },
                  description: { description ?? Text("") })
    }
    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, systemImage: systemImage) },
                  description: { description ?? Text("") })
    }
}

private struct CompatUnavailableLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 8) {
            configuration.icon.font(.system(size: 44)).foregroundColor(.secondary)
            configuration.title
        }
    }
}

extension View {
    @ViewBuilder func backgroundProminenceStandardCompat() -> some View {
        if #available(iOS 17, *) { self.environment(\.backgroundProminence, .standard) } else { self }
    }
    @ViewBuilder func presentationBackgroundCompat<S: ShapeStyle>(_ style: S) -> some View {
        if #available(iOS 16.4, *) { self.presentationBackground(style) } else { self }
    }
    @ViewBuilder func contentTransitionSymbolReplaceCompat() -> some View {
        if #available(iOS 17, *) { self.contentTransitionSymbolReplaceCompat() } else { self }
    }
}

private struct VoiceInputSessionKey: EnvironmentKey { static var defaultValue: VoiceInputSession? { nil } }
private struct ConsoleSheetFitKey: EnvironmentKey { static var defaultValue: ConsoleSheetFit? { nil } }
extension EnvironmentValues {
    var voiceInputSession: VoiceInputSession? {
        get { self[VoiceInputSessionKey.self] }
        set { self[VoiceInputSessionKey.self] = newValue }
    }
    var consoleSheetFit: ConsoleSheetFit? {
        get { self[ConsoleSheetFitKey.self] }
        set { self[ConsoleSheetFitKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder func scrollTargetLayoutCompat() -> some View {
        if #available(iOS 17, *) { self.scrollTargetLayout() } else { self }
    }
}

extension View {
    @ViewBuilder func listSectionSpacingCompat(_ spacing: CGFloat) -> some View {
        if #available(iOS 17, *) { self.listSectionSpacingCompat(spacing) } else { self }
    }
    @ViewBuilder func contentMarginsHorizontalCompat(_ length: CGFloat) -> some View {
        if #available(iOS 17, *) { self.contentMarginsCompat(.horizontal, length) } else { self }
    }
    @ViewBuilder func navigationDestinationCompat<Item: Hashable, Destination: View>(
        item: Binding<Item?>, @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if #available(iOS 17, *) {
            self.navigationDestination(item: item, destination: destination)
        } else {
            self.navigationDestination(isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } })) {
                if let value = item.wrappedValue { destination(value) }
            }
        }
    }
}

extension Color {
    func mixedCompat(with other: Color, by fraction: Double) -> Color {
        if #available(iOS 18, *) { return mix(with: other, by: fraction) }
        var a: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var b = a
        UIColor(self).getRed(&a.0, green: &a.1, blue: &a.2, alpha: &a.3)
        UIColor(other).getRed(&b.0, green: &b.1, blue: &b.2, alpha: &b.3)
        let f = CGFloat(fraction)
        return Color(.sRGB, red: Double(a.0 + (b.0 - a.0) * f), green: Double(a.1 + (b.1 - a.1) * f),
                     blue: Double(a.2 + (b.2 - a.2) * f), opacity: Double(a.3 + (b.3 - a.3) * f))
    }
}

private struct OverlayNetworkStoreKey: EnvironmentKey { static var defaultValue: OverlayNetworkStore? { nil } }
extension EnvironmentValues {
    var overlayNetworkStore: OverlayNetworkStore? {
        get { self[OverlayNetworkStoreKey.self] }
        set { self[OverlayNetworkStoreKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder func buttonBorderShapeCircleCompat() -> some View {
        if #available(iOS 17, *) { self.buttonBorderShape(.circle) } else { self.buttonBorderShape(.roundedRectangle) }
    }
}

extension View {
    @ViewBuilder func contentMarginsCompat(_ edges: Edge.Set, _ length: CGFloat) -> some View {
        if #available(iOS 17, *) { self.contentMargins(edges, length, for: .scrollContent) } else { self }
    }
}

private struct HostStoreOptionalKey: EnvironmentKey { static var defaultValue: HostStore? { nil } }
extension EnvironmentValues {
    var hostStoreOptional: HostStore? {
        get { self[HostStoreOptionalKey.self] }
        set { self[HostStoreOptionalKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder func presentationBackgroundInteractionCompat(_ disabled: Bool, upThrough detent: PresentationDetent) -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackgroundInteraction(disabled ? .disabled : .enabled(upThrough: detent))
        } else { self }
    }
    @ViewBuilder func presentationCompactAdaptationSheetCompat() -> some View {
        if #available(iOS 16.4, *) { self.presentationCompactAdaptation(.sheet) } else { self }
    }
}

extension View {
    @ViewBuilder func presentationCompactAdaptationPopoverCompat() -> some View {
        if #available(iOS 16.4, *) { self.presentationCompactAdaptation(.popover) } else { self }
    }
    @ViewBuilder func accessibilityIsToggleCompat() -> some View {
        if #available(iOS 17, *) { self.accessibilityAddTraits(.isToggle) } else { self }
    }
}

extension View {
    @ViewBuilder func toolbarRemovingTitleCompat(_ remove: Bool) -> some View {
        if #available(iOS 18, *) { self.toolbar(removing: remove ? .title : nil) } else { self }
    }
    @ViewBuilder func toolbarRemovingSidebarToggleCompat(_ remove: Bool) -> some View {
        if #available(iOS 17, *) { self.toolbar(removing: remove ? .sidebarToggle : nil) } else { self }
    }
    @ViewBuilder func toolbarTitleInlineLargeCompat() -> some View {
        if #available(iOS 17, *) { self.toolbarTitleDisplayMode(.inlineLarge) } else { self.navigationBarTitleDisplayMode(.large) }
    }
    @ViewBuilder func navigationLinkIndicatorHiddenCompat() -> some View {
        if #available(iOS 17, *) { self.navigationLinkIndicatorVisibility(.hidden) } else { self }
    }
}
