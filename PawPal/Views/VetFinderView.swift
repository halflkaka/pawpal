import SwiftUI
import MapKit

struct VetFinderView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var results: [MKMapItem] = []
    @State private var isEmergency = false
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let searchService = VetSearchService()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isEmergency ? "Emergency care nearby" : "Nearby veterinary clinics")
                        .font(.headline)
                    Text(isEmergency ? "Use this when you need urgent care options quickly." : "Search around your current location to find general veterinary care.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Toggle("Emergency Vet", isOn: $isEmergency)
                    .onChange(of: isEmergency) { _, _ in
                        Task { await searchIfPossible() }
                    }

                Button {
                    errorMessage = nil
                    locationManager.requestLocation()
                } label: {
                    Label(results.isEmpty ? "Use Current Location" : "Refresh Nearby Results", systemImage: "location.fill")
                }

                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching nearby vets…")
                            .foregroundStyle(.secondary)
                    }
                } else if locationManager.location == nil {
                    Label("Share your location to search local vets on-device.", systemImage: "location.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section(results.isEmpty ? "Results" : "\(results.count) Results") {
                if results.isEmpty, locationManager.location != nil, !isSearching, errorMessage == nil {
                    ContentUnavailableView(
                        "No Nearby Matches",
                        systemImage: "cross.case",
                        description: Text("Try refreshing, moving slightly, or switching emergency mode.")
                    )
                    .padding(.vertical, 12)
                }

                ForEach(results, id: \.self) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name ?? "Vet Clinic")
                                    .font(.headline)
                                if let title = addressLine(for: item) {
                                    Text(title)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let distance = distanceText(for: item) {
                                Text(distance)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }

                        HStack(spacing: 12) {
                            if let phoneNumber = item.phoneNumber,
                               let phoneURL = URL(string: "tel://\(phoneNumber.filter { $0.isNumber })") {
                                Link(destination: phoneURL) {
                                    Label("Call", systemImage: "phone.fill")
                                }
                            }

                            if let url = item.url {
                                Link(destination: url) {
                                    Label("Website", systemImage: "safari")
                                }
                            }

                            Link(destination: mapsURL(for: item)) {
                                Label("Directions", systemImage: "map.fill")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Nearby Vets")
        .onChange(of: locationManager.location) { _, _ in
            Task { await searchIfPossible() }
        }
        .onChange(of: locationManager.locationErrorMessage) { _, newValue in
            errorMessage = newValue
        }
    }

    private func searchIfPossible() async {
        guard locationManager.location != nil else { return }
        await search()
    }

    private func search() async {
        guard let location = locationManager.location else { return }

        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )

        do {
            isSearching = true
            errorMessage = nil
            let query = isEmergency ? "24 hour emergency veterinarian" : "veterinarian"
            results = try await searchService.search(query: query, region: region)
            results.sort { lhs, rhs in
                let lhsDistance = lhs.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
                let rhsDistance = rhs.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
                return lhsDistance < rhsDistance
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isSearching = false
    }

    private func addressLine(for item: MKMapItem) -> String? {
        let parts = [item.placemark.thoroughfare, item.placemark.locality, item.placemark.administrativeArea]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? item.placemark.title : parts.joined(separator: ", ")
    }

    private func distanceText(for item: MKMapItem) -> String? {
        guard let userLocation = locationManager.location,
              let itemLocation = item.placemark.location else { return nil }
        let measurement = Measurement(value: userLocation.distance(from: itemLocation) / 1609.34, unit: UnitLength.miles)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func mapsURL(for item: MKMapItem) -> URL {
        let latitude = item.placemark.coordinate.latitude
        let longitude = item.placemark.coordinate.longitude
        return URL(string: "http://maps.apple.com/?daddr=\(latitude),\(longitude)")!
    }
}
