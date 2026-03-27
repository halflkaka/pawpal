import Foundation
import MapKit

final class VetSearchService {
    func search(query: String, region: MKCoordinateRegion) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems
    }
}
