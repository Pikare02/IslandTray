import UniformTypeIdentifiers
import XCTest
@testable import IslandTray

/// Only `preferredTypeIdentifier` is covered here. The rest of `ingest`
/// drives `loadFileRepresentation` and `TrayStore.shared`, which need a real
/// drag session and the app's real container respectively -- neither is
/// available in a test bundle. The type-identifier selection, though, is
/// ordinary Swift over `NSItemProvider.registeredTypeIdentifiers` and is
/// worth pinning on its own.
final class DropReceiverTests: XCTestCase {
    /// `registeredTypeIdentifiers` reports identifiers in registration order:
    /// registering `first` then `second` gives `candidates == [first, second]`.
    private func provider(registering identifiers: [String]) -> NSItemProvider {
        let provider = NSItemProvider()
        for identifier in identifiers {
            provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .all) { completion in
                completion(Data(), nil)
                return nil
            }
        }
        return provider
    }

    func testPrefersTheConcreteTypeOverAContainerType() {
        // "public.data" is registered first (so it would win a plain
        // `.first`), but it's on the ignore list, so the concrete type behind
        // it must be the one picked.
        let item = provider(registering: ["public.data", "public.jpeg"])
        XCTAssertEqual(
            DropReceiver.preferredTypeIdentifier(for: item), "public.jpeg",
            "a container-ish identifier standing first must not win over a concrete type behind it"
        )
    }

    func testFallsBackToTheFirstCandidateWhenEveryOneIsIgnored() {
        // Both "public.item" and "public.content" are on the ignore list;
        // with nothing concrete offered, the first one registered still wins
        // over manufacturing a generic UTType.data identifier.
        let item = provider(registering: ["public.item", "public.content"])
        XCTAssertEqual(DropReceiver.preferredTypeIdentifier(for: item), "public.item")
    }

    func testFallsBackToUTTypeDataWhenNothingIsRegistered() {
        let empty = NSItemProvider()
        XCTAssertEqual(DropReceiver.preferredTypeIdentifier(for: empty), UTType.data.identifier)
    }
}
