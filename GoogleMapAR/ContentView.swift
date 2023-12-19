//
//  ContentView.swift
//  GoogleMapAR
//
//  Created by Shokal on 30/11/23.
//

import SwiftUI
import GoogleMaps
import ARKit
import CoreLocation
import ARKit_CoreLocation

struct ContentView: View {
    @ObservedObject var locationManager = LocationManager()
    @State private var placedMarker: CLLocationCoordinate2D?
    @State private var polyline: GMSPolyline?
    @State private var mapCenterCoordinate: CLLocationCoordinate2D?
    @State private var showWelcome = true // State for showing the welcome view
    @State private var poisCached: [POI] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // AR View occupying the full height
                ARViewContainer(currentLocation: $locationManager.currentLocation, placedMarker: $placedMarker, polyline: $polyline, cachedPoi: $poisCached)
                    .edgesIgnoringSafeArea(.all) // Make ARView cover the entire screen
//                    .frame(height: geometry.size.height * 0.7)
                // Horizontal Scroll View for POI Categories
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(POICategory.allCases, id: \.self) { category in
                            Button(category.displayName) {
                                fetchPOIsWithCategory(category)
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }
                .padding(.top, 20)
                 //Map View occupying the bottom 30% of the screen
//                MapViewContainer(currentLocation: $mapCenterCoordinate, placedMarker: $placedMarker, polyline: $polyline)
//                    .frame(height: geometry.size.height * 0.3)
//                    .alignmentGuide(.bottom) { d in d[.bottom] }
//                    .overlay(
//                        Button(action: {
//                            // Action to center map on user's current location
//                            self.mapCenterCoordinate = self.locationManager.currentLocation
//                        }) {
//                            Image(systemName: "location.circle.fill") // System icon for location
//                                .font(.title)
//                                .foregroundColor(.blue)
//                        }
//                        .padding(),
//                        alignment: .topTrailing
//                    )
            }
        }
        .onAppear {
            self.mapCenterCoordinate = self.locationManager.currentLocation
        }
        .onReceive(locationManager.$currentLocation) { newLocation in
            // Safely unwrap the newLocation
            if let newLocation = newLocation {
                // Determine if new POIs should be fetched
                let shouldFetch = shouldFetchNewPOIs(for: newLocation)

                print("Should fetch: \(shouldFetch)")

                if shouldFetch {
                    // Update the last fetched location
                    locationManager.lastFetchedLocation = newLocation

                    poisCached.removeAll()
                    // Fetch new POIs
                    fetchPOIs(near: newLocation, category: "commercial.food_and_drink") { pois in
                        print("Fetch Called")
                        DispatchQueue.main.async {
                            poisCached = pois // Update the cached POIs
                        }
                    }
                }
            }
        }

    }
    private func shouldFetchNewPOIs(for newLocation: CLLocationCoordinate2D) -> Bool {
        guard let lastLocation = locationManager.lastFetchedLocation else {
            // If no last location, fetch POIs
            return true
        }

        let lastLocationCL = CLLocation(latitude: lastLocation.latitude, longitude: lastLocation.longitude)
        let newLocationCL = CLLocation(latitude: newLocation.latitude, longitude: newLocation.longitude)

        // Check if the distance moved is more than 500 meters
        let distanceMoved = lastLocationCL.distance(from: newLocationCL)
        print("Distance moved- \(distanceMoved)")
        return distanceMoved > 500 // Distance threshold in meters
    }

    
    func fetchPOIs(near location: CLLocationCoordinate2D, category: String, completion: @escaping ([POI]) -> Void) {
        let apiKey = "67c6d9f903e848fbb7a897f6fb24107a"
        let radius = 5000
        let limit = 20
        let urlString = "https://api.geoapify.com/v2/places?categories=\(category.lowercased())&filter=circle:\(location.longitude),\(location.latitude),\(radius)&bias=proximity:\(location.longitude),\(location.latitude)&limit=\(limit)&apiKey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            completion([])
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else {
                completion([])
                print("Error: \(String(describing: error))")
                return
            }

            do {
                let pois = parsePOIs(from: data, currentLocation: location)
                completion(pois)
            }
        }.resume()
    }

    func parsePOIs(from data: Data, currentLocation: CLLocationCoordinate2D) -> [POI] {
        do {
            let jsonResult = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            guard let features = jsonResult?["features"] as? [[String: Any]] else { return [] }

            var pois: [POI] = []

            for feature in features {
                if let properties = feature["properties"] as? [String: Any],
                   let name = properties["name"] as? String,
                   let geometry = feature["geometry"] as? [String: Any],
                   let coordinates = geometry["coordinates"] as? [Double] {

                    let poiLocation = CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
                    let currentLocationCL = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
                    let poiCLLocation = CLLocation(latitude: coordinates[1], longitude: coordinates[0])
                    let distance = currentLocationCL.distance(from: poiCLLocation)

                    let poi = POI(name: name, osmID: 0, distance: distance, location: poiLocation)
                    pois.append(poi)
                }
            }

            return pois
        } catch {
            print("Error parsing JSON: \(error)")
            return []
        }
    }
}

extension ContentView {
    func fetchPOIsWithCategory(_ category: POICategory) {
        // Use the category to modify the API call
        let filterValue = category.rawValue // Modify this based on how your API expects it
        fetchPOIs(near: locationManager.currentLocation ?? CLLocationCoordinate2D(), category: filterValue) { pois in
            DispatchQueue.main.async {
                poisCached = pois
            }
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var lastFetchedLocation: CLLocationCoordinate2D?
    @Published var cachedPOIs: [POI] = []

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            currentLocation = location.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error getting location: \(error)")
    }
}

struct ARViewContainer: View {
    @Binding var currentLocation: CLLocationCoordinate2D?
    @Binding var placedMarker: CLLocationCoordinate2D?
    @Binding var polyline: GMSPolyline?
    @Binding var cachedPoi: [POI]

    var body: some View {
        ARView(currentLocation: $currentLocation, placedMarker: $placedMarker, polyline: $polyline, poisCached: $cachedPoi)
    }
}

struct ARView: UIViewRepresentable {
    @Binding var currentLocation: CLLocationCoordinate2D?
    @Binding var placedMarker: CLLocationCoordinate2D?
    @Binding var polyline: GMSPolyline?
    @Binding var poisCached: [POI]
    
    @State private var lastFetchedLocation: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = SceneLocationView() // Use SceneLocationView from ARCL
        sceneView.run() // Start the AR session
        return sceneView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        guard let sceneView = uiView as? SceneLocationView else { return }
        // Use cached POIs to update the scene
        
        sceneView.removeAllNodes()
        addPOIsToScene(pois: poisCached, sceneView: sceneView)
        
//        let messages = [
//            "Welcome to GoogleMapAR!",
//            "Discover the world in AR.",
//            "Explore and enjoy your journey.",
//            // Add more messages as needed
//        ]

//            let avatarNode = createAvatarNode()
//            sceneView.scene.rootNode.addChildNode(avatarNode)
//
//            var totalDelay: TimeInterval = 0
//            for message in messages {
//                let messageNode = createTextNodeForWelcome(message: message, delay: totalDelay)
//                messageNode.position = SCNVector3(x: 0, y: 0.3, z: -1) // Adjust position
//                sceneView.scene.rootNode.addChildNode(messageNode)
//
//                // Increment delay for the next message
//                totalDelay += 5.0 // Adjust this value based on fadeIn, wait and fadeOut durations
//            }
        
        if let path = self.polyline?.path {
            var distancesToDestination = [Double](repeating: 0, count: Int(path.count()))
            
            // Calculate distances from each point to the destination
            for index in stride(from: path.count() - 1, through: 0, by: -1) {
                let coordinate = path.coordinate(at: index)
                let location = CLLocation(coordinate: coordinate, altitude: 5)
                
                if index < path.count() - 1 {
                    let nextCoordinate = path.coordinate(at: index + 1)
                    let nextLocation = CLLocation(latitude: nextCoordinate.latitude, longitude: nextCoordinate.longitude)
                    distancesToDestination[Int(index)] = location.distance(from: nextLocation) + distancesToDestination[Int(index) + 1]
                }
                
                // To use an USDZ file as node
                //                if let usdzNode = createNodeFromUSDZ(named: "arrow") {
                //                    // Position and add the node to your AR scene
                //                    usdzNode.position = SCNVector3(x: 0, y: 0, z: -1) // Adjust position as needed
                //                    // Add to ARSCNView or SceneLocationView
                //
                //                    let locationNode = LocationNode(location: location)
                //                    locationNode.addChildNode(usdzNode)
                //                    sceneView.addLocationNodeWithConfirmedLocation(locationNode: locationNode)
                //                }
                
                let node = createCircleNode()
                let locationNode = LocationNode(location: location)
                locationNode.addChildNode(node)
                
                // Show distance only for the next node to be reached
                if index == path.count() - 1 || (currentLocation != nil && location.distance(from: CLLocation(latitude: currentLocation!.latitude, longitude: currentLocation!.longitude)) < distancesToDestination[Int(index)]) {
                    let formattedDistance = String(format: "%.2f meters", distancesToDestination[Int(index)])
                    let distanceNode = createTextNode(text: formattedDistance)
                    distanceNode.position = SCNVector3(x: 0, y: 0.2, z: 0) // Adjust position as needed
                    locationNode.addChildNode(distanceNode)
                }
                
                sceneView.addLocationNodeWithConfirmedLocation(locationNode: locationNode)
            }
        }
    }
    
    private func shouldFetchNewPOIs(for newLocation: CLLocationCoordinate2D) -> Bool {
        guard let lastLocation = lastFetchedLocation else {
            return true // No last location, fetch POIs
        }

        return distanceBetween(lastLocation, and: newLocation) > 300 // Threshold in meters
    }

    private func addPOIsToScene(pois: [POI], sceneView: SceneLocationView) {
        print("Total Pois- \(pois.count)")
        for poi in pois {
            let maxRadius: CGFloat = 10.0
            let minRadius: CGFloat = 5.0
            let distanceThreshold: Double = 1000 // Meters

            let scaleFactor = max(minRadius / maxRadius, min(1, Double(poi.distance) / distanceThreshold))
            let radius = maxRadius * scaleFactor

            let poiNode = createPOINode(poi, radius: radius)
            print(poi.name)
            // Create a title node with text scaling based on distance
            let titleNode = createTextNodeForPoi(text: poi.name, distance: poi.distance)
            titleNode.position = SCNVector3(x: 0, y: poiNode.position.y + Float(radius), z: 0 + Float(radius))
            poiNode.addChildNode(titleNode)

            let locationNode = LocationNode(location: CLLocation(coordinate: poi.location, altitude: 1))
            locationNode.addChildNode(poiNode)
            sceneView.addLocationNodeWithConfirmedLocation(locationNode: locationNode)
        }
        
    }
    
    func createPOINode(_ poi: POI, radius: CGFloat) -> SCNNode {
        // Create the geometry with the calculated radius
        let geometry = SCNSphere(radius: radius)
        geometry.firstMaterial?.diffuse.contents = UIColor.green

        // Create and return the node
        let node = SCNNode(geometry: geometry)
        node.name = String(poi.distance) // Optional, for identification
        
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = .all
        node.constraints = [billboardConstraint]
        
        return node
    }

    
    func createTextNodeForWelcome(message: String, delay: TimeInterval) -> SCNNode {
        let textGeometry = SCNText(string: message, extrusionDepth: 0.1)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(0.01, 0.01, 0.01) // Adjust the text size
        textNode.opacity = 0 // Start with an invisible node

        // Fade-in and fade-out animations
        let fadeInAction = SCNAction.fadeIn(duration: 1.0)
        let waitAction = SCNAction.wait(duration: delay)
        let fadeOutAction = SCNAction.fadeOut(duration: 1.0)
        let sequenceAction = SCNAction.sequence([waitAction, fadeInAction, SCNAction.wait(duration: 3.0), fadeOutAction])
        textNode.runAction(sequenceAction)

        return textNode
    }
 
    
    private func distanceBetween(_ location1: CLLocationCoordinate2D, and location2: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: location1.latitude, longitude: location1.longitude)
        let loc2 = CLLocation(latitude: location2.latitude, longitude: location2.longitude)
        return loc1.distance(from: loc2)
    }

    func createTextNode(text: String) -> SCNNode {
        let textGeometry = SCNText(string: text, extrusionDepth: 0.4)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(0.1, 0.1, 0.1)
        return textNode
    }
    
    func createTextNodeForPoi(text: String, distance: Double) -> SCNNode {
        let textGeometry = SCNText(string: text, extrusionDepth: 1.0)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        let textNode = SCNNode(geometry: textGeometry)

        // Adjust the scale based on distance
        let minScale: Float = 1.0 // Minimum scale for close POIs
        let maxScale: Float = 3.0 // Maximum scale for distant POIs
        let distanceThreshold: Double = 1000 // Distance threshold for scaling

        // Calculate the scale factor (linear scaling)
        let scaleFactor = Float(max(minScale, min(maxScale, Float(distance) / Float(distanceThreshold))))
        textNode.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)

        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = .all
        textNode.constraints = [billboardConstraint]
        
        return textNode
    }

    
    func createAvatarNode() -> SCNNode {
        let sphere = SCNSphere(radius: 0.2)
        sphere.firstMaterial?.diffuse.contents = UIImage(named: "avatarTexture")
        let avatarNode = SCNNode(geometry: sphere)
        avatarNode.position = SCNVector3(x: 0, y: 0, z: -1)

        // Add animation here if needed
        let rotateAction = SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 10)
        avatarNode.runAction(SCNAction.repeatForever(rotateAction))

        return avatarNode
    }

    
    func createCircleNode() -> SCNNode {
            let geometry = SCNSphere(radius: 0.5)
            geometry.firstMaterial?.diffuse.contents = UIColor.red

            let node = SCNNode(geometry: geometry)
            return node
        }

    func createNodeFromUSDZ(named usdzFileName: String) -> SCNNode? {
        guard let sceneURL = Bundle.main.url(forResource: usdzFileName, withExtension: "usdz") else {
            print("Could not find \(usdzFileName).usdz file in the project")
            return nil
        }

        do {
            let scene = try SCNScene(url: sceneURL, options: nil)
            let node = scene.rootNode.childNodes.first
            return node
        } catch {
            print("Error loading USDZ file: \(error)")
            return nil
        }
    }

}

struct MapViewContainer: View {
    @Binding var currentLocation: CLLocationCoordinate2D?
    @Binding var placedMarker: CLLocationCoordinate2D?
    @Binding var polyline: GMSPolyline?

    var body: some View {
        MapView(currentLocation: $currentLocation, placedMarker: $placedMarker, polyline: $polyline)
    }
}

struct MapView: UIViewRepresentable {
    @Binding var currentLocation: CLLocationCoordinate2D?
    @Binding var placedMarker: CLLocationCoordinate2D?
    @Binding var polyline: GMSPolyline?

    func makeUIView(context: Context) -> GMSMapView {
        let mapView = GMSMapView()
        mapView.delegate = context.coordinator
        
        if let currentLocation = currentLocation {
            let camera = GMSCameraPosition.camera(withLatitude: currentLocation.latitude, longitude: currentLocation.longitude, zoom: 16.0)
            mapView.camera = camera
        }
       if let placedMarker = placedMarker {
           let marker = GMSMarker(position: placedMarker)
           marker.map = mapView
       }

        mapView.isMyLocationEnabled = true
        
        // Draw the polyline
        if let polyline = polyline {
            polyline.map = mapView
        }

        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        // Update the map view's camera to the current location
        if let currentLocation = currentLocation {
            let camera = GMSCameraPosition.camera(withLatitude: currentLocation.latitude, longitude: currentLocation.longitude, zoom: 16.0)
            mapView.animate(to: camera)
        }

        // Clear existing polylines
        mapView.clear()
        
        // Handle marker placement
        if let placedMarker = placedMarker {
            let marker = GMSMarker(position: placedMarker)
            marker.map = mapView
        }
        
        // Add the new polyline if it exists
        if let polyline = polyline {
            polyline.strokeColor = .blue
            polyline.strokeWidth = 5.0
            polyline.map = mapView
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: MapView

        init(_ parent: MapView) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.placedMarker = coordinate
            parent.fetchDirectionsWithOpenStreetMap(from: parent.currentLocation!, to: coordinate, mapView: mapView)
        }
    }
    
    func fetchDirectionsWithOpenStreetMap(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mapView: GMSMapView) {
        print("Entered Into getting Direction..")
        let apiKey = "5b3ce3597851110001cf6248a682756e54b84aaa99ae4d7216d79b90"
        let urlString = "https://api.openrouteservice.org/v2/directions/driving-car?api_key=\(apiKey)&start=\(from.longitude),\(from.latitude)&end=\(to.longitude),\(to.latitude)"
        print("Url Called: \(urlString)")
        guard let url = URL(string: urlString) else { return }
        
        print("Url: \(url)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else { return }

            do {
                if let jsonResult = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let features = jsonResult["features"] as? [[String: Any]],
                   let firstFeature = features.first,
                   let geometry = firstFeature["geometry"] as? [String: Any],
                   let coordinates = geometry["coordinates"] as? [[Double]] {

                    let path = GMSMutablePath()
                    coordinates.forEach { coordinate in
                        if coordinate.count == 2 {
                            path.addLatitude(coordinate[1], longitude: coordinate[0])
                        }
                    }
                    
                    DispatchQueue.main.async {
                        let polyline = GMSPolyline(path: path)
                        polyline.strokeColor = .blue
                        polyline.strokeWidth = 5.0
                        self.polyline = polyline
                    }
                }
            } catch {
                print("Error parsing JSON: \(error)")
            }
        }.resume()
    }

    func fetchAndSetPolylineWithGoogleMapDirectionsAPI(from: CLLocationCoordinate2D?, to: CLLocationCoordinate2D) {
        guard let startCoordinate = from else { return }

        let apiKey = "AIzaSyBrd2vc69Mfq1-OPQmsUNjRhYFfM9-tDJc"
        let urlString = "https://maps.googleapis.com/maps/api/directions/json?origin=\(startCoordinate.latitude),\(startCoordinate.longitude)&destination=\(to.latitude),\(to.longitude)&key=\(apiKey)"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else { return }

            do {
                if let jsonResult = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let routes = jsonResult["routes"] as? [Any], !routes.isEmpty,
                   let route = routes[0] as? [String: Any],
                   let overviewPolyline = route["overview_polyline"] as? [String: Any],
                   let polylineString = overviewPolyline["points"] as? String {
                    print("Polyline: \(polylineString)")
                    
                    if let path = GMSPath(fromEncodedPath: polylineString) {
                        let polyline = GMSPolyline(path: path)
                        DispatchQueue.main.async {
                            self.polyline = polyline
                            print("Polyline Path Count: \(path.count())")
                        }
                    }
                }
            } catch {
                print("Error parsing JSON: \(error)")
            }
        }.resume()
    }
}

struct POI {
    let name: String
    let osmID: Int
    let distance: Double
    let location: CLLocationCoordinate2D
}

enum POICategory: String, CaseIterable {
    case shopping = "commercial.shopping_mall"
    case foodAndDrinks = "commercial.food_and_drink"
    case accommodation = "accommodation"
    case education = "education"
    case healthcare = "healthcare"
    case parking = "parking"
    case rentals = "rental"
    case tourism = "tourism"
    case amenities = "amenity"
    case beaches = "beach"
    case heritage = "heritage"
    case publicTransport = "public_transport"
    case activities = "activity"
    case office = "office"
    case populatedPlaces = "populated_place"
    case religion = "religion"

    var displayName: String {
        switch self {
        case .shopping: return "Shopping"
        case .foodAndDrinks: return "Food and Drinks"
        case .accommodation: return "Accommodation"
        case .education: return "Education"
        case .healthcare: return "Healthcare"
        case .parking: return "Parking"
        case .rentals: return "Rentals"
        case .tourism: return "Tourism"
        case .amenities: return "Amenities"
        case .beaches: return "Beaches"
        case .heritage: return "Heritage"
        case .publicTransport: return "Public Transport"
        case .activities: return "Activities"
        case .office: return "Office"
        case .populatedPlaces: return "Populated Places"
        case .religion: return "Religion"
        }
    }

    var apiCategory: String {
        return self.rawValue
    }
}

// Add the necessary preview provider
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

#Preview {
    ContentView()
}
