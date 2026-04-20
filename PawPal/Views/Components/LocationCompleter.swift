import Foundation
import MapKit

/// MKLocalSearchCompleter wrapper — publishes results as the query changes.
///
/// Previously lived as a `private final class` inside `ProfileView.swift`
/// next to `LocationPickerSheet`. Lifted to file scope so the playdate
/// composer sheet can reuse the same search-as-you-type completer
/// without duplicating the delegate plumbing. The public surface is
/// unchanged: consumers observe `results` and call `search(_:)`.
@MainActor
final class LocationCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func search(_ query: String) {
        completer.queryFragment = query
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = completer.results
        Task { @MainActor in self.results = r }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
