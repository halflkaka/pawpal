import SwiftUI
import MapKit

struct VetFinderView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var results: [MKMapItem] = []
    @State private var isEmergency = false
    @State private var errorMessage: String?

    private let searchService = VetSearchService()

    var body: some View {
        List {
            Section {
                Toggle("Emergency Vet", isOn: $isEmergency)
                    .onChange(of: isEmergency) { _, _ in
                        Task { await search() }
                    }

                Button("Use Current Location") {
                    locationManager.requestLocation()
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Results") {
                ForEach(results, id: \.self) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name ?? "Vet Clinic")
                            .font(.headline)
                        if let title = item.placemark.title {
                            Text(title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Nearby Vets")
        .onChange(of: locationManager.location) { _, _ in
            Task { await search() }
        }
    }

    private func search() async {
        guard let location = locationManager.location else { return }

        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )

        do {
            errorMessage = nil
            let query = isEmergency ? "emergency veterinarian" : "veterinarian"
            results = try await searchService.search(query: query, region: region)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
