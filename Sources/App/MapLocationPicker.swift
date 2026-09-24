import CoreLocation
import MapKit
import SwiftUI

/// Pins the weather location on a map instead of typing a city name. The map
/// pans under a fixed centre pin; confirming stores the centre coordinate and a
/// reverse-geocoded name into `TraySettings` for `WeatherProvider` to read.
struct MapLocationPicker: View {
    @Environment(\.dismiss) private var dismiss
    /// The resolved display name, handed back so the caller can refresh its label.
    var onSave: (String) -> Void

    @State private var camera: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @State private var resolving = false

    init(initial: CLLocationCoordinate2D?, onSave: @escaping (String) -> Void) {
        // Seoul when nothing is pinned yet -- a valid start the user pans from.
        let start = initial ?? CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
        _center = State(initialValue: start)
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: start, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08))))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $camera)
                    .onMapCameraChange(frequency: .continuous) { ctx in
                        center = ctx.camera.centerCoordinate
                    }
                    .ignoresSafeArea(edges: .bottom)
                // Fixed pin marking the map centre; its tip sits on the centre.
                Image(systemName: "mappin")
                    .font(.title)
                    .foregroundStyle(.red)
                    .offset(y: -11)
                    .allowsHitTesting(false)
            }
            .navigationTitle(L.s("drawer.settings.pinTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.s("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.s("common.done")) { save() }.disabled(resolving)
                }
            }
        }
    }

    private func save() {
        let c = center
        let settings = TraySettings()
        settings.weatherManualLat = c.latitude
        settings.weatherManualLon = c.longitude
        resolving = true
        CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: c.latitude, longitude: c.longitude)
        ) { places, _ in
            let p = places?.first
            let name = [p?.locality, p?.administrativeArea, p?.name, p?.country]
                .compactMap { $0 }.first(where: { !$0.isEmpty })
                ?? String(format: "%.3f, %.3f", c.latitude, c.longitude)
            settings.weatherManualName = name
            onSave(name)
            resolving = false
            dismiss()
        }
    }
}
