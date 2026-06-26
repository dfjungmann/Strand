import SwiftUI
import MapKit

// MARK: - Shared tile URLSession with disk cache

/// 300 MB disk / 30 MB RAM – tiles reused across sessions.
/// Cleared only when user explicitly taps refresh.
private let weatherTileCache = URLCache(
    memoryCapacity:  30 * 1024 * 1024,
    diskCapacity:   300 * 1024 * 1024,
    diskPath: nil
)

private let weatherTileSession: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.urlCache = weatherTileCache
    cfg.requestCachePolicy = .returnCacheDataElseLoad
    cfg.timeoutIntervalForRequest = 15
    cfg.httpMaximumConnectionsPerHost = 3   // avoid 429 rate limiting
    return URLSession(configuration: cfg)
}()

// MARK: - Island definitions

struct CanaryIsland: Identifiable, Hashable {
    let id: String
    let name: String
    let shortName: String
    let latitude: Double
    let longitude: Double
    let zoom: Int
    let latDelta: Double
    let lonDelta: Double

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}

let canaryIslands: [CanaryIsland] = [
    // Kanaren: GC (27.96/-15.59) + TF (28.27/-16.63) gemeinsam sichtbar
    CanaryIsland(id: "kan", name: "Kanaren",              shortName: "Kan", latitude: 28.12, longitude: -16.10, zoom: 8, latDelta: 1.30, lonDelta: 2.50),
    CanaryIsland(id: "gla", name: "Gladbeck",             shortName: "Gla", latitude: 51.57, longitude:   7.00, zoom: 9, latDelta: 0.70, lonDelta: 0.90),
    CanaryIsland(id: "ton", name: "Baiersbronn-Tonbach",  shortName: "Ton", latitude: 48.57, longitude:   8.35, zoom: 9, latDelta: 0.70, lonDelta: 0.90),
]

// MARK: - Unified display layer

enum DisplayLayer: String, CaseIterable, Identifiable {
    case precipitation = "precipitation_new"
    case clouds        = "clouds_new"
    case wind          = "wind_new"
    case temperature   = "temp_new"
    case radarAnim     = "radar_anim"   // RainViewer animated

    var id: String { rawValue }
    var label: String {
        switch self {
        case .precipitation: return "Regen"
        case .clouds:        return "Wolken"
        case .wind:          return "Wind"
        case .temperature:   return "Temp"
        case .radarAnim:     return "Radar"
        }
    }
    var isOWM: Bool { self != .radarAnim }
}

// MARK: - RainViewer API

private struct RVResponse: Decodable {
    let radar: RVRadarData?
}
private struct RVRadarData: Decodable {
    let past: [RVFrame]
}
struct RVFrame: Decodable {
    let time: Int
    let path: String
}

private func fetchRainViewerFrames() async throws -> [RVFrame] {
    let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        throw URLError(.badServerResponse)
    }
    let rv = try JSONDecoder().decode(RVResponse.self, from: data)
    let frames = rv.radar?.past ?? []
    guard !frames.isEmpty else {
        throw NSError(domain: "RainViewer", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Keine Radardaten verfügbar"])
    }
    return frames
}

// MARK: - Tile overlay with intensity compositing + caching

private class WeatherTileOverlay: MKTileOverlay {
    private let tag: String
    let intensity: Int
    let forceRefresh: Bool

    init(urlTemplate: String, tag: String, maxZoom: Int, tileSize: Int = 256, intensity: Int, forceRefresh: Bool = false) {
        self.tag = tag
        self.intensity = max(1, min(intensity, 6))
        self.forceRefresh = forceRefresh
        super.init(urlTemplate: urlTemplate)
        canReplaceMapContent = false
        minimumZ = 0
        maximumZ = maxZoom
        self.tileSize = CGSize(width: tileSize, height: tileSize)
    }

    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, Error?) -> Void) {
        let tileURL = url(forTilePath: path)
        let policy: URLRequest.CachePolicy = forceRefresh
            ? .reloadIgnoringLocalCacheData
            : .returnCacheDataElseLoad
        let request = URLRequest(url: tileURL, cachePolicy: policy, timeoutInterval: 15)

        loadTileWithRetry(request: request, path: path, tag: tag, attemptsLeft: 3, result: result)
    }

    private func loadTileWithRetry(request: URLRequest, path: MKTileOverlayPath,
                                   tag: String, attemptsLeft: Int,
                                   result: @escaping (Data?, Error?) -> Void) {
        weatherTileSession.dataTask(with: request) { [self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Rate-limited: evict cached error, wait, retry with forced fresh request
            if status == 429, attemptsLeft > 0 {
                if let url = request.url {
                    weatherTileCache.removeCachedResponse(for: request)
                    _ = url  // suppress warning
                }
                let delay = Double(4 - attemptsLeft) * 3.0   // 3s, 6s, 9s back-off
                let freshRequest = URLRequest(url: request.url!, cachePolicy: .reloadIgnoringLocalCacheData,
                                             timeoutInterval: 15)
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.loadTileWithRetry(request: freshRequest, path: path, tag: tag,
                                          attemptsLeft: attemptsLeft - 1, result: result)
                }
                return
            }
            if status != 200 || error != nil {
                if let error { print("[\(tag)] \(path.z)/\(path.x)/\(path.y) error: \(error)") }
                else { print("[\(tag)] \(path.z)/\(path.x)/\(path.y) → HTTP \(status)") }
                result(data, error); return
            }

            guard intensity > 1, let data, let image = UIImage(data: data) else {
                result(data, nil); return
            }
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let boosted = UIGraphicsImageRenderer(size: image.size, format: fmt).image { _ in
                let r = CGRect(origin: .zero, size: image.size)
                for _ in 0 ..< intensity { image.draw(in: r) }
            }
            result(boosted.pngData(), nil)
        }.resume()
    }
}


// MARK: - Map UIViewRepresentable

private struct RadarMapView: UIViewRepresentable {
    let island: CanaryIsland
    let tileURLTemplate: String?
    let tileTag: String
    let maxZoom: Int
    let tileSize: Int
    let intensity: Int
    let forceRefresh: Bool

    private var overlayKey: String {
        "\(island.id)|\(tileURLTemplate ?? "nil")|\(maxZoom)|\(intensity)|\(forceRefresh)"
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .standard
        map.isRotateEnabled = false
        map.showsUserLocation = false
        map.delegate = context.coordinator
        map.setRegion(island.region, animated: false)
        context.coordinator.lastIslandID = island.id
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if context.coordinator.lastIslandID != island.id {
            context.coordinator.lastIslandID = island.id
            mapView.setRegion(island.region, animated: true)
        }
        if context.coordinator.lastOverlayKey != overlayKey {
            context.coordinator.lastOverlayKey = overlayKey
            mapView.overlays.forEach { mapView.removeOverlay($0) }
            if let template = tileURLTemplate {
                let overlay = WeatherTileOverlay(urlTemplate: template, tag: tileTag,
                                                 maxZoom: maxZoom, tileSize: tileSize,
                                                 intensity: intensity, forceRefresh: forceRefresh)
                mapView.addOverlay(overlay, level: .aboveLabels)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MKMapViewDelegate {
        var lastIslandID = ""
        var lastOverlayKey = ""

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: tile)
                r.alpha = 1.0
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Main View

struct WeatherMapView: View {
    @Binding var selectedTab: Int

    @AppStorage("owm_api_key")              private var owmKey = ""
    @AppStorage("radar_intensity")          private var intensity: Int = 3
    @AppStorage("radar_default_location")   private var defaultLocationID: String = "kan"

    @State private var selectedIsland: CanaryIsland = canaryIslands[0]
    @State private var selectedLayer: DisplayLayer = .radarAnim

    // RainViewer animation
    @State private var rvFrames: [RVFrame] = []
    @State private var currentFrameIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var animationTask: Task<Void, Never>? = nil
    @State private var isLoadingFrames = false

    @State private var lastUpdated: Date? = nil
    @State private var loadError: String? = nil
    @State private var pendingForceRefresh = false

    private var trimmedKey: String { owmKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var useOWM: Bool { !trimmedKey.isEmpty }

    private var currentTileTemplate: String? {
        switch selectedLayer {
        case .radarAnim:
            guard !rvFrames.isEmpty else { return nil }
            // 512px tiles → 4× fewer requests vs 256px, same zoom range
            return "https://tilecache.rainviewer.com\(rvFrames[currentFrameIndex].path)/512/{z}/{x}/{y}/4/1_0.png"
        default:
            guard useOWM else { return nil }
            return "https://tile.openweathermap.org/map/\(selectedLayer.rawValue)/{z}/{x}/{y}.png?appid=\(trimmedKey)"
        }
    }

    private var currentFrameDate: Date? {
        guard selectedLayer == .radarAnim, !rvFrames.isEmpty else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(rvFrames[currentFrameIndex].time))
    }

    // Which layers to show in picker
    private var availableLayers: [DisplayLayer] {
        useOWM ? DisplayLayer.allCases : [.radarAnim]
    }

    var body: some View {
        ZStack(alignment: .top) {
            RadarMapView(
                island: selectedIsland,
                tileURLTemplate: currentTileTemplate,
                tileTag: selectedLayer == .radarAnim ? "RV" : "OWM",
                maxZoom: selectedLayer == .radarAnim ? 8 : 18,  // RainViewer max zoom = 8
                tileSize: selectedLayer == .radarAnim ? 512 : 256,
                intensity: intensity,
                forceRefresh: pendingForceRefresh
            )
            .ignoresSafeArea(edges: .bottom)

            topBar
        }
        .task { await initializeView() }
        .onChange(of: selectedLayer) { _, newLayer in
            stopAnimation()
            if newLayer == .radarAnim {
                Task { await loadRadarFrames(forceRefresh: false) }
            } else {
                lastUpdated = Date()
            }
        }
        .onChange(of: useOWM) { _, nowOWM in
            if !nowOWM { selectedLayer = .radarAnim }
        }
        .onDisappear { stopAnimation() }
        .gesture(
            DragGesture(minimumDistance: 60)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                    if v.translation.width > 60 { withAnimation { selectedTab = 3 } }
                }
        )
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 6) {
            // Title + refresh
            HStack {
                Text("Radar · \(selectedIsland.name)")
                    .font(.headline)
                Spacer()
                if isLoadingFrames {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button { Task { await forceRefreshAll() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                if let date = lastUpdated {
                    Text(date, style: .time)
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Island picker with long-press-to-default
            islandSegmentedPicker

            // Layer picker
            Picker("Ebene", selection: $selectedLayer) {
                ForEach(availableLayers) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)

            // Animation controls (only for Radar layer)
            if selectedLayer == .radarAnim {
                radarAnimationBar
            } else {
                // Intensity stepper for static OWM layers
                intensityStepper
                    .padding(.horizontal, 12)
            }

            if let error = loadError {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 12)
            }

            Color.clear.frame(height: 4)
        }
        .background(.bar)
    }

    // Custom island picker – tap = select, long press = set as default (★)
    private var islandSegmentedPicker: some View {
        HStack(spacing: 0) {
            ForEach(canaryIslands) { island in
                let isSelected = selectedIsland == island
                let isDefault  = defaultLocationID == island.id
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedIsland = island }
                } label: {
                    HStack(spacing: 2) {
                        Text(island.shortName)
                            .font(.system(size: 13, weight: .medium))
                        if isDefault {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        isSelected
                            ? Color(.systemBackground)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                }
                .padding(2)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                        withAnimation { defaultLocationID = island.id }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                )
            }
        }
        .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    private var radarAnimationBar: some View {
        HStack(spacing: 12) {
            // Play / Pause
            Button {
                isPlaying ? stopAnimation() : startAnimation()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isPlaying ? .orange : .blue)
            }
            .disabled(rvFrames.isEmpty)

            // Frame scrubber
            if !rvFrames.isEmpty {
                Slider(
                    value: Binding(
                        get: { Double(currentFrameIndex) },
                        set: { newVal in
                            stopAnimation()
                            currentFrameIndex = Int(newVal.rounded())
                        }
                    ),
                    in: 0 ... Double(max(rvFrames.count - 1, 0)),
                    step: 1
                )

                // Timestamp of current frame
                if let frameDate = currentFrameDate {
                    Text(frameDate, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 40)
                }

                // Frame counter
                Text("\(currentFrameIndex + 1)/\(rvFrames.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if isLoadingFrames {
                Text("Lädt…").font(.caption).foregroundStyle(.secondary)
            }

            intensityStepper
        }
        .padding(.horizontal, 12)
    }

    private var intensityStepper: some View {
        HStack(spacing: 2) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.caption).foregroundStyle(.secondary)
            Stepper("", value: $intensity, in: 1...6)
                .labelsHidden()
                .fixedSize()
            Text("\(intensity)×")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .leading)
        }
    }

    // MARK: - Animation logic

    private func startAnimation() {
        guard !rvFrames.isEmpty else { return }
        isPlaying = true
        animationTask?.cancel()
        animationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 s per frame
                guard !Task.isCancelled else { break }
                currentFrameIndex = (currentFrameIndex + 1) % rvFrames.count
            }
        }
    }

    private func stopAnimation() {
        isPlaying = false
        animationTask?.cancel()
        animationTask = nil
    }

    // MARK: - Data loading

    private func initializeView() async {
        // Restore saved default location
        if let saved = canaryIslands.first(where: { $0.id == defaultLocationID }) {
            selectedIsland = saved
        }
        // Always open with radar animation
        selectedLayer = .radarAnim
        await loadRadarFrames(forceRefresh: false)
    }

    private func loadRadarFrames(forceRefresh: Bool) async {
        isLoadingFrames = true
        loadError = nil
        // Always clear tile cache when loading new frames – removes any stale 429 responses
        weatherTileCache.removeAllCachedResponses()
        do {
            rvFrames = try await fetchRainViewerFrames()
            currentFrameIndex = max(0, rvFrames.count - 1)   // start at latest frame
            lastUpdated = Date()
            if !isPlaying { startAnimation() }
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingFrames = false
    }

    private func forceRefreshAll() async {
        weatherTileCache.removeAllCachedResponses()
        pendingForceRefresh = true
        stopAnimation()
        if selectedLayer == .radarAnim {
            await loadRadarFrames(forceRefresh: true)
        } else {
            lastUpdated = Date()
        }
        try? await Task.sleep(for: .seconds(2))
        pendingForceRefresh = false
    }
}
