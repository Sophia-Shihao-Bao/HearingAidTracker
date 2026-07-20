import SwiftUI
import MapKit

struct MapView: UIViewRepresentable {
    /// Coordinate to pin and center on (nil = show nothing/custom message)
    var pinCoordinate: CLLocationCoordinate2D?

    // Back-compat so existing calls can keep using `userCoordinate:` label
    init(userCoordinate: CLLocationCoordinate2D?) {
        self.pinCoordinate = userCoordinate
    }

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.showsUserLocation = true
        mv.userTrackingMode = .none
        mv.isRotateEnabled = false
        return mv
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Remove old annotations (keep the blue user dot)
        let toRemove = uiView.annotations.filter { !($0 is MKUserLocation) }
        if !toRemove.isEmpty { uiView.removeAnnotations(toRemove) }

        guard let c = pinCoordinate else { return }

        // Center map and add pin
        let region = MKCoordinateRegion(center: c,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        uiView.setRegion(region, animated: true)

        let pin = MKPointAnnotation()
        pin.coordinate = c
        pin.title = "Phone Location"
        uiView.addAnnotation(pin)
    }
}
