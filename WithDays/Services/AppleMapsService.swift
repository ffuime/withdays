import Foundation
import MapKit

/// Search and routes through Apple's MapKit: free, with no key.
@MainActor
enum AppleMapsService {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Search

    /// Places and genres (「ラーメン屋」「コンビニ」…) around `near`, nearest first.
    static func search(_ query: String, near: GeoPoint) async throws -> [MapPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: near.coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000)
        request.resultTypes = [.pointOfInterest, .address]
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        } catch {
            throw Failure(message: "検索できませんでした。通信状態を確かめてください")
        }
        return response.mapItems.map(place(from:))
            .sorted { $0.location.distance(to: near) < $1.location.distance(to: near) }
    }

    private static func place(from item: MKMapItem) -> MapPlace {
        let placemark = item.placemark
        let location = GeoPoint(placemark.coordinate)
        let id = item.identifier?.rawValue
            ?? "point-\(location.latitude),\(location.longitude),\(item.name ?? "")"
        // 「新宿区西新宿2丁目8-1」: the city and below.
        let street = [placemark.locality, placemark.subLocality, placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0 }
            .reduce(into: [String]()) { parts, part in if parts.last != part { parts.append(part) } }
            .joined()
        return MapPlace(
            id: id,
            name: item.name ?? "名称不明",
            address: street.isEmpty ? placemark.title : street,
            location: location,
            category: item.pointOfInterestCategory.flatMap(categoryName)
        )
    }

    private static func categoryName(_ category: MKPointOfInterestCategory) -> String? {
        let names: [MKPointOfInterestCategory: String] = [
            .restaurant: "レストラン", .cafe: "カフェ", .bakery: "ベーカリー", .brewery: "ブルワリー",
            .winery: "ワイナリー", .nightlife: "ナイトライフ", .foodMarket: "食料品店", .store: "店舗",
            .pharmacy: "薬局", .hospital: "病院", .bank: "銀行", .atm: "ATM", .gasStation: "ガソリンスタンド",
            .evCharger: "充電スタンド", .parking: "駐車場", .hotel: "ホテル", .park: "公園", .museum: "博物館",
            .library: "図書館", .school: "学校", .university: "大学", .postOffice: "郵便局", .police: "警察",
            .fireStation: "消防署", .publicTransport: "駅・交通機関", .airport: "空港", .movieTheater: "映画館",
            .theater: "劇場", .stadium: "スタジアム", .fitnessCenter: "フィットネス", .laundry: "ランドリー",
            .restroom: "トイレ", .zoo: "動物園", .aquarium: "水族館", .amusementPark: "遊園地", .beach: "ビーチ",
            .campground: "キャンプ場", .carRental: "レンタカー", .marina: "マリーナ", .nationalPark: "国立公園",
        ]
        return names[category]
    }

    // MARK: Routes

    static func route(from origin: GeoPoint, to destination: GeoPoint, mode: TravelMode) async throws -> RouteResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.requestsAlternateRoutes = false
        request.departureDate = Date()

        if mode == .transit {
            // Apple answers 電車・バス with a time only, no line or steps.
            request.transportType = .transit
            do {
                let eta = try await MKDirections(request: request).calculateETA()
                return RouteResult(
                    durationSeconds: Int(eta.expectedTravelTime),
                    distanceMeters: Int(eta.distance),
                    path: [],
                    steps: [],
                    arrival: eta.expectedArrivalDate
                )
            } catch {
                throw Failure(message: "電車・バスの経路が見つかりませんでした")
            }
        }

        switch mode {
        case .walk: request.transportType = .walking
        case .drive: request.transportType = .automobile
        // Cycling directions (iOS 26) by raw value.
        case .bicycle: request.transportType = MKDirectionsTransportType(rawValue: 1 << 3)
        case .transit: break
        }
        let route: MKRoute
        do {
            guard let first = try await MKDirections(request: request).calculate().routes.first else {
                throw Failure(message: "\(mode.label)の経路が見つかりませんでした")
            }
            route = first
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure(message: "\(mode.label)の経路が見つかりませんでした")
        }
        let polyline = route.polyline
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        var steps: [RouteStep] = []
        for step in route.steps where !step.instructions.isEmpty {
            steps.append(RouteStep(id: steps.count, instruction: step.instructions, distanceMeters: Int(step.distance)))
        }
        return RouteResult(
            durationSeconds: Int(route.expectedTravelTime),
            distanceMeters: Int(route.distance),
            path: coordinates.map(GeoPoint.init),
            steps: steps,
            arrival: Date().addingTimeInterval(route.expectedTravelTime)
        )
    }

    /// Opens Apple Maps with the route, for 電車・バス's lines and transfers.
    static func openInMaps(from origin: GeoPoint, originName: String, to destination: GeoPoint, destinationName: String, mode: TravelMode) {
        let start = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        start.name = originName
        let end = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        end.name = destinationName
        let directions: String = switch mode {
        case .walk: MKLaunchOptionsDirectionsModeWalking
        case .drive: MKLaunchOptionsDirectionsModeDriving
        case .transit: MKLaunchOptionsDirectionsModeTransit
        case .bicycle: MKLaunchOptionsDirectionsModeDefault
        }
        MKMapItem.openMaps(with: [start, end], launchOptions: [MKLaunchOptionsDirectionsModeKey: directions])
    }
}
