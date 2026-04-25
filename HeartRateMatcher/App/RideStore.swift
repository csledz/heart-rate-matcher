import Foundation
import SwiftUI

@MainActor
final class RideStore: ObservableObject {
    @Published var rides: [Ride] = []
    @Published var lastError: String?

    private let importer = RideImporter()

    func importRide(from url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let ride = try importer.importRide(from: url)
            rides.append(ride)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func remove(at offsets: IndexSet) {
        rides.remove(atOffsets: offsets)
    }

    func ride(with id: Ride.ID) -> Ride? {
        rides.first(where: { $0.id == id })
    }
}
