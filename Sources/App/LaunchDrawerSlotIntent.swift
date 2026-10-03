import AppIntents
import Foundation

/// Opens one drawer slot's target from a widget tile that cannot be a
/// `Link`: the small Home Screen widget and the Lock Screen rectangle.
///
/// `openAppWhenRun`: the system brings the app forward and runs this inside
/// it. The intent only hands the URL over -- `UIApplication` does not
/// compile in the widget extension, which has to know this type to build
/// the button -- and the app opens it the way it opens an island link: an
/// installed app through the private launch API, anything else through the
/// system.
struct LaunchDrawerSlotIntent: AppIntent {
    static let title: LocalizedStringResource = "ドロワーの項目を開く"
    static let openAppWhenRun: Bool = true

    @Parameter(title: "URL")
    var launch: String

    init() {}

    init(launch: String) {
        self.launch = launch
    }

    /// A launch the app has not acted on yet. On a cold start the
    /// notification below can fire before the window is listening, so the
    /// scene also takes this when it becomes active.
    @MainActor private(set) static var pending: URL?

    /// The waiting launch, once: whichever of the two listeners gets here
    /// first handles it, the other finds nothing.
    @MainActor static func takePending() -> URL? {
        defer { pending = nil }
        return pending
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let url = URL(string: launch) else { return .result() }
        Self.pending = url
        NotificationCenter.default.post(name: .launchDrawerSlot, object: url)
        return .result()
    }
}

extension Notification.Name {
    /// Posted by `LaunchDrawerSlotIntent` inside the app; `object` is the URL.
    static let launchDrawerSlot = Notification.Name("launchDrawerSlot")
}
