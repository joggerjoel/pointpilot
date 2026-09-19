import Foundation
import CoreLocation

/// Coordinate value object representing latitude & longitude.
struct LocationCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    /// Default demo coordinate: Downtown Manhattan (near Nobu, Shake Shack, Chipotle).
    static let defaultDemo = LocationCoordinate(latitude: 40.7168, longitude: -74.0089)
}

/// Authorization and tracking state for location services.
enum LocationState: Equatable, Sendable {
    case notDetermined
    case requesting
    case authorized(LocationCoordinate)
    case denied
    case restricted
    case error(String)

    var coordinate: LocationCoordinate? {
        if case .authorized(let coord) = self {
            return coord
        }
        return nil
    }

    var isSearching: Bool {
        if case .requesting = self { return true }
        return false
    }
}

/// Boundary protocol for location services so tests can mock GPS without triggering real OS alerts.
@MainActor
protocol LocationServiceProtocol: AnyObject {
    var state: LocationState { get }
    var onStateChange: ((LocationState) -> Void)? { get set }

    func requestLocation() async -> LocationCoordinate?
}

/// Production CoreLocation wrapper.
@MainActor
final class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationCoordinate?, Never>?

    private(set) var state: LocationState = .notDetermined {
        didSet {
            onStateChange?(state)
        }
    }

    var onStateChange: ((LocationState) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        updateInitialState()
    }

    private func updateInitialState() {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if let loc = locationManager.location {
                state = .authorized(LocationCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))
            } else {
                state = .notDetermined
            }
        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        case .notDetermined:
            state = .notDetermined
        @unknown default:
            state = .notDetermined
        }
    }

    func requestLocation() async -> LocationCoordinate? {
        let authStatus = locationManager.authorizationStatus

        if authStatus == .denied || authStatus == .restricted {
            state = (authStatus == .denied) ? .denied : .restricted
            return nil
        }

        state = .requesting

        if authStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.locationManager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            resumeContinuation(with: nil)
            return
        }

        let coord = LocationCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        state = .authorized(coord)
        resumeContinuation(with: coord)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        state = .error(error.localizedDescription)
        resumeContinuation(with: nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied:
            state = .denied
            resumeContinuation(with: nil)
        case .restricted:
            state = .restricted
            resumeContinuation(with: nil)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    private func resumeContinuation(with coord: LocationCoordinate?) {
        continuation?.resume(returning: coord)
        continuation = nil
    }
}
