import SwiftUI
import WebKit

// MARK: - Leaflet Map WebView
struct LeafletMapView: UIViewRepresentable {
    private static var jsL: Strings { AppSettings.shared.l }
    let monuments: [Monument]
    let userLat: Double
    let userLon: Double
    let userHeading: Double
    let mapAction: MapAction
    var onUploadTap: ((UploadMonumentInfo) -> Void)?
    var onViewportChanged: ((Double, Double, Double, Double, Int) -> Void)?
    var onMapReady: (() -> Void)?
    var onFollowModeChanged: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        var mapReady = false
        var lastMonumentIds: Set<String> = []
        var lastFilterHash: Int = -1
        var lastLanguage: String = ""
        var onUploadTap: ((UploadMonumentInfo) -> Void)?
        var onViewportChanged: ((Double, Double, Double, Double, Int) -> Void)?
        var onMapReady: (() -> Void)?
        var onFollowModeChanged: ((Bool) -> Void)?
        var osmCacheInjected = false
        weak var webView: WKWebView?
        private var notificationObserver: Any?

        override init() {
            super.init()
            notificationObserver = NotificationCenter.default.addObserver(
                forName: .monumentPhotoUpdated,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let info = notification.userInfo,
                      let qid = info["qid"] as? String,
                      let filename = info["filename"] as? String else { return }
                self?.updateMarkerPhoto(qid: qid, imageFilename: filename)
            }
        }


        deinit {
            if let observer = notificationObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func updateMarkerPhoto(qid: String, imageFilename: String) {
            let imgUrl = "https://commons.wikimedia.org/wiki/Special:FilePath/\(imageFilename)?width=120"
                .replacingOccurrences(of: "'", with: "\\'")
            let escapedQid = qid.replacingOccurrences(of: "'", with: "\\'")
            let js = "updateSingleMarker('\(escapedQid)', '#22c55e', '\(imgUrl)');"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        context.coordinator.onUploadTap = onUploadTap
        context.coordinator.onViewportChanged = onViewportChanged
        context.coordinator.onMapReady = onMapReady
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.isMultipleTouchEnabled = true
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        context.coordinator.webView = webView
        loadHTML(webView, context: context)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        coord.onUploadTap = onUploadTap
        coord.onViewportChanged = onViewportChanged
        coord.onMapReady = onMapReady
        coord.onFollowModeChanged = onFollowModeChanged
        guard coord.mapReady else { return }

        // Update JS localization strings when language changes
        let currentLang = AppSettings.shared.language
        if coord.lastLanguage != currentLang {
            coord.lastLanguage = currentLang
            let l = AppSettings.shared.l
            let noPhoto = l.noPhoto.replacingOccurrences(of: "'", with: "\\'")
            let uploadPhoto = l.uploadPhoto.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("_L.noPhoto='\(noPhoto)';_L.uploadPhoto='\(uploadPhoto)';", completionHandler: nil)
            if !monuments.isEmpty {
                coord.lastFilterHash = -1 // force full rebuild
            }
        }

        // Inject cached OSM boundaries once
        if !coord.osmCacheInjected {
            coord.osmCacheInjected = true
            if let cachedJSON = OSMBoundaryCache.loadJSONString() {
                let js = "osmGeoCache = \(cachedJSON);"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        // Update user location & heading
        let shouldCenter = mapAction == .centerOnUser
        let js = "updateUserLocation(\(userLat), \(userLon), \(userHeading), \(shouldCenter));"
        webView.evaluateJavaScript(js, completionHandler: nil)

        // Handle zoom actions
        switch mapAction {
        case .zoomIn:
            webView.evaluateJavaScript("map.zoomIn();", completionHandler: nil)
        case .zoomOut:
            webView.evaluateJavaScript("map.zoomOut();", completionHandler: nil)
        case .focusOn(let lat, let lon):
            webView.evaluateJavaScript("focusAndOpenPopup(\(lat), \(lon));", completionHandler: nil)
        default:
            break
        }

        // Compute current filter hash
        let currentFilterHash = monuments.count > 0 ? monuments.map(\.hasPhoto).hashValue : 0
        let currentIds = Set(monuments.map(\.id))

        if currentFilterHash != coord.lastFilterHash {
            coord.lastFilterHash = currentFilterHash
            coord.lastMonumentIds = currentIds
            let markersJS = buildMarkersJS()
            webView.evaluateJavaScript("replaceAllMarkers(\(markersJS));", completionHandler: nil)
        } else if currentIds != coord.lastMonumentIds {
            let newMonuments = monuments.filter { !coord.lastMonumentIds.contains($0.id) }
            coord.lastMonumentIds = currentIds
            if !newMonuments.isEmpty {
                let newJS = buildMarkersJS(for: newMonuments)
                webView.evaluateJavaScript("addMarkers(\(newJS));", completionHandler: nil)
            }
        }
    }

    private func escapeJS(_ s: String?) -> String {
        guard let s = s, !s.isEmpty else { return "null" }
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func buildMarkersJS(for list: [Monument]? = nil) -> String {
        let arr = (list ?? monuments).map { m in
            let escaped = m.name.replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let color = m.hasPhoto ? "#22c55e" : "#ef4444"
            let imgStr: String
            if let url = m.imageUrl {
                let thumbEscaped = url.replacingOccurrences(of: "\"", with: "\\\"")
                imgStr = "\"\(thumbEscaped)\""
            } else {
                imgStr = "null"
            }
            let osmRelStr = m.osmRelationId.map { "\"\($0)\"" } ?? "null"
            let osmWayStr = m.osmWayId.map { "\"\($0)\"" } ?? "null"
            return "{\"lat\":\(m.latitude),\"lon\":\(m.longitude),\"color\":\"\(color)\",\"name\":\"\(escaped)\",\"qid\":\"\(m.wikidataId)\",\"img\":\(imgStr),\"osmRel\":\(osmRelStr),\"osmWay\":\(osmWayStr),\"type\":\(escapeJS(m.instanceOf)),\"admin\":\(escapeJS(m.adminEntity)),\"heritage\":\(escapeJS(m.heritageDesig)),\"architect\":\(escapeJS(m.architect)),\"style\":\(escapeJS(m.archStyle))}"
        }
        return "[\(arr.joined(separator: ","))]"
    }

    private func loadHTML(_ webView: WKWebView, context: Context) {
        let saved = SavedMapPosition.load()
        let initLat = saved?.lat ?? userLat
        let initLon = saved?.lon ?? userLon
        let initZoom = saved?.zoom ?? 15

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <link rel="stylesheet" href="leaflet.css"/>
        <script src="leaflet.js"></script>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          #map { width: 100vw; height: 100vh; }
          .custom-popup .leaflet-popup-content-wrapper {
            border-radius: 12px;
            padding: 0;
            overflow: hidden;
            box-shadow: 0 4px 16px rgba(0,0,0,0.18);
          }
          .custom-popup .leaflet-popup-content {
            margin: 0;
            min-width: 200px;
          }
          .custom-popup .leaflet-popup-tip {
            background: #fff;
          }
          .popup-inner {
            display: flex;
            align-items: stretch;
            min-height: 64px;
          }
          .popup-thumb {
            width: 72px;
            min-height: 64px;
            object-fit: cover;
            flex-shrink: 0;
            display: block;
          }
          .popup-info {
            padding: 10px 12px;
            display: flex;
            flex-direction: column;
            justify-content: center;
            flex: 1;
            min-width: 0;
          }
          .popup-name {
            font-weight: 700;
            font-size: 13px;
            color: #1a1a1a;
            line-height: 1.3;
            word-wrap: break-word;
          }
          .popup-thumb-placeholder {
            width: 72px;
            min-height: 64px;
            background: #f0f0f0;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
          }
          .popup-nophoto {
            font-size: 11px;
            color: #999;
            margin-top: 3px;
          }
          .popup-upload-btn {
            display: block;
            width: 100%;
            padding: 8px 0;
            background: #36c;
            color: #fff;
            font-size: 12px;
            font-weight: 600;
            text-align: center;
            border: none;
            border-top: 1px solid #eee;
            cursor: pointer;
            letter-spacing: 0.3px;
          }
          .popup-upload-btn:active {
            background: #2a52a0;
          }
        </style>
        </head>
        <body>
        <div id="map"></div>
        <script>
          var _L = {
            noPhoto: '\(Self.jsL.noPhoto.replacingOccurrences(of: "'", with: "\\'"))',
            uploadPhoto: '\(Self.jsL.uploadPhoto.replacingOccurrences(of: "'", with: "\\'"))'
          };
          var map = L.map('map', {
            zoomControl: false,
            doubleClickZoom: true,
            touchZoom: true,
            bounceAtZoomLimits: false
          }).setView([\(initLat), \(initLon)], \(initZoom));
          L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
            maxZoom: 19,
            attribution: '© OpenStreetMap'
          }).addTo(map);

          map.on('moveend', function() {
            var c = map.getCenter();
            var z = map.getZoom();
            window.webkit.messageHandlers.savePosition.postMessage(
              JSON.stringify({lat: c.lat, lon: c.lng, zoom: z})
            );
          });

          // Custom double-tap zoom (WKWebView scrollView steals dblclick)
          (function() {
            var lastTap = 0;
            var tapTimeout = null;
            document.getElementById('map').addEventListener('touchend', function(e) {
              if (e.touches.length > 0) return; // multi-finger, ignore
              var now = Date.now();
              var delta = now - lastTap;
              if (delta < 350 && delta > 50) {
                // Double tap detected
                e.preventDefault();
                if (tapTimeout) { clearTimeout(tapTimeout); tapTimeout = null; }
                var touch = e.changedTouches[0];
                var pt = map.containerPointToLatLng(L.point(touch.clientX, touch.clientY));
                map.setView(pt, map.getZoom() + 1, {animate: true});
                lastTap = 0;
              } else {
                lastTap = now;
              }
            }, {passive: false});
          })();

          var userHeadingCone = null;
          var userDotOuter = null;
          var userDotInner = null;
          var markerById = {};
          var currentMarkerData = {};

          function createHeadingCone(lat, lon, heading) {
            var spread = 35;
            var radius = 0.0012;
            var left = (heading - spread) * Math.PI / 180;
            var right = (heading + spread) * Math.PI / 180;
            var steps = 20;
            var pts = [[lat, lon]];
            for (var i = 0; i <= steps; i++) {
              var a = left + (right - left) * i / steps;
              pts.push([lat + radius * Math.cos(a), lon + radius * Math.sin(a) / Math.cos(lat * Math.PI / 180)]);
            }
            pts.push([lat, lon]);
            return pts;
          }

          var followMode = false;

          map.on('dragstart', function() {
            if (followMode) {
              followMode = false;
              window.webkit.messageHandlers.followModeChanged.postMessage('false');
            }
          });

          function updateUserLocation(lat, lon, heading, shouldCenter) {
            var conePts = createHeadingCone(lat, lon, heading);
            if (userHeadingCone) {
              userHeadingCone.setLatLngs(conePts);
            } else {
              userHeadingCone = L.polygon(conePts, {
                color: 'transparent',
                fillColor: '#007AFF',
                fillOpacity: 0.15,
                weight: 0
              }).addTo(map);
            }

            if (userDotOuter) {
              userDotOuter.setLatLng([lat, lon]);
            } else {
              userDotOuter = L.circleMarker([lat, lon], {
                radius: 18,
                fillColor: '#007AFF',
                fillOpacity: 0.15,
                color: '#007AFF',
                opacity: 0.2,
                weight: 1
              }).addTo(map);
            }

            if (userDotInner) {
              userDotInner.setLatLng([lat, lon]);
            } else {
              userDotInner = L.circleMarker([lat, lon], {
                radius: 7,
                fillColor: '#007AFF',
                fillOpacity: 1,
                color: '#FFFFFF',
                weight: 2.5,
                opacity: 1
              }).addTo(map);
            }

            if (shouldCenter) {
              followMode = true;
              map.setView([lat, lon], map.getZoom() < 14 ? 15 : map.getZoom());
              window.webkit.messageHandlers.followModeChanged.postMessage('true');
            } else if (followMode) {
              map.panTo([lat, lon], {animate: true, duration: 0.5});
            }
          }

          function openUploadForQid(qid) {
            var m = currentMarkerData[qid];
            if (m) {
              var payload = JSON.stringify({name: m.name, qid: m.qid, img: m.img || '', type: m.type || '', admin: m.admin || '', heritage: m.heritage || '', architect: m.architect || '', style: m.style || ''});
              window.webkit.messageHandlers.openUpload.postMessage(payload);
            }
          }

          function buildPopupHTML(m) {
            var html = '<div class="popup-inner">';
            if (m.img) {
              html += '<img class="popup-thumb" src="' + m.img + '" onerror="this.style.display=\\'none\\'">';
            } else {
              html += '<div class="popup-thumb-placeholder"><svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#bbb" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="6" width="20" height="14" rx="2"/><circle cx="12" cy="13" r="4"/><path d="M7 6L8.5 3h7L17 6"/></svg></div>';
            }
            html += '<div class="popup-info">';
            html += '<div class="popup-name">' + m.name + '</div>';
            if (!m.img) {
              html += '<div class="popup-nophoto">' + _L.noPhoto + '</div>';
            }
            html += '</div></div>';
            html += '<button class="popup-upload-btn" onclick="openUploadForQid(\\'' + m.qid + '\\')">' + _L.uploadPhoto + '</button>';
            return html;
          }

          function addMarkers(data) {
            data.forEach(function(m) {
              if (markerById[m.qid]) return;
              currentMarkerData[m.qid] = m;
              var marker = L.circleMarker([m.lat, m.lon], {
                radius: 9,
                fillColor: m.color,
                color: '#fff',
                weight: 2,
                fillOpacity: 0.9
              }).bindPopup(buildPopupHTML(m), {
                className: 'custom-popup',
                maxWidth: 280,
                minWidth: 200,
                closeButton: false
              });
              marker.addTo(map);
              markerById[m.qid] = marker;
            });
            tryOpenPendingPopup();
          }

          function replaceAllMarkers(data) {
            Object.keys(markerById).forEach(function(qid) {
              map.removeLayer(markerById[qid]);
            });
            markerById = {};
            currentMarkerData = {};
            addMarkers(data);
          }

          function updateMarkers(data) { replaceAllMarkers(data); }

          function updateSingleMarker(qid, color, img) {
            if (currentMarkerData[qid]) {
              currentMarkerData[qid].color = color;
              currentMarkerData[qid].img = img || null;
            }
            var marker = markerById[qid];
            if (marker) {
              marker.setStyle({ fillColor: color });
              if (currentMarkerData[qid]) {
                marker.setPopupContent(buildPopupHTML(currentMarkerData[qid]));
              }
            }
          }

          var pendingPopup = null;

          function focusAndOpenPopup(lat, lon) {
            pendingPopup = {lat: lat, lon: lon};
            map.setView([lat, lon], 17);
            tryOpenPendingPopup();
          }

          function tryOpenPendingPopup() {
            if (!pendingPopup) return;
            var lat = pendingPopup.lat;
            var lon = pendingPopup.lon;
            var minDist = Infinity;
            var nearest = null;
            Object.keys(markerById).forEach(function(qid) {
              var marker = markerById[qid];
              var ll = marker.getLatLng();
              var d = Math.pow(ll.lat - lat, 2) + Math.pow(ll.lng - lon, 2);
              if (d < minDist) {
                minDist = d;
                nearest = marker;
              }
            });
            if (nearest && minDist < 0.0001) {
              nearest.openPopup();
              pendingPopup = null;
            }
          }

          // OSM Boundary Drawing
          var osmLayers = {};
          var osmGeoCache = {};
          var boundariesVisible = false;
          var pendingOsmFetch = false;

          function getOsmKey(m) {
            if (m.osmRel) return 'r' + m.osmRel;
            if (m.osmWay) return 'w' + m.osmWay;
            return null;
          }

          function loadVisibleBoundaries() {
            if (pendingOsmFetch) return;
            var bounds = map.getBounds();
            var relIds = [];
            var wayIds = [];
            var keyMap = {};

            Object.values(currentMarkerData).forEach(function(m) {
              if (!m.osmRel && !m.osmWay) return;
              var ll = L.latLng(m.lat, m.lon);
              if (!bounds.contains(ll)) return;
              var key = getOsmKey(m);
              if (!key || osmLayers[key]) return;
              if (osmGeoCache[key]) {
                drawBoundary(key, osmGeoCache[key]);
                return;
              }
              if (m.osmRel) {
                relIds.push(m.osmRel);
                keyMap[m.osmRel] = key;
              } else if (m.osmWay) {
                wayIds.push(m.osmWay);
                keyMap[m.osmWay] = key;
              }
            });

            if (relIds.length === 0 && wayIds.length === 0) return;

            var parts = [];
            if (relIds.length > 0) parts.push('relation(id:' + relIds.join(',') + ')');
            if (wayIds.length > 0) parts.push('way(id:' + wayIds.join(',') + ')');
            var overpassQuery = '[out:json];(' + parts.join(';') + ';);out geom;';

            pendingOsmFetch = true;
            fetch('https://overpass-api.de/api/interpreter', {
              method: 'POST',
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: 'data=' + encodeURIComponent(overpassQuery)
            })
            .then(function(r) { return r.json(); })
            .then(function(data) {
              pendingOsmFetch = false;
              if (!data.elements) return;
              var hasNew = false;
              data.elements.forEach(function(el) {
                var key = (el.type === 'relation' ? 'r' : 'w') + el.id;
                var coords = extractCoords(el);
                if (coords && coords.length > 0) {
                  osmGeoCache[key] = coords;
                  hasNew = true;
                  if (boundariesVisible) {
                    drawBoundary(key, coords);
                  }
                }
              });
              if (hasNew) {
                window.webkit.messageHandlers.saveOsmCache.postMessage(JSON.stringify(osmGeoCache));
              }
            })
            .catch(function() { pendingOsmFetch = false; });
          }

          function extractCoords(el) {
            if (el.type === 'way' && el.geometry) {
              return [el.geometry.map(function(p) { return [p.lat, p.lon]; })];
            }
            if (el.type === 'relation' && el.members) {
              var rings = [];
              el.members.forEach(function(member) {
                if (member.type === 'way' && member.geometry && member.role !== 'inner') {
                  rings.push(member.geometry.map(function(p) { return [p.lat, p.lon]; }));
                }
              });
              if (rings.length > 1) {
                rings = mergeRings(rings);
              }
              return rings;
            }
            return null;
          }

          function mergeRings(ways) {
            var merged = [];
            var used = new Array(ways.length).fill(false);
            for (var i = 0; i < ways.length; i++) {
              if (used[i]) continue;
              used[i] = true;
              var ring = ways[i].slice();
              var changed = true;
              while (changed) {
                changed = false;
                for (var j = 0; j < ways.length; j++) {
                  if (used[j]) continue;
                  var last = ring[ring.length - 1];
                  var first = ring[0];
                  var wFirst = ways[j][0];
                  var wLast = ways[j][ways[j].length - 1];
                  if (ptEq(last, wFirst)) {
                    ring = ring.concat(ways[j].slice(1));
                    used[j] = true; changed = true;
                  } else if (ptEq(last, wLast)) {
                    ring = ring.concat(ways[j].slice().reverse().slice(1));
                    used[j] = true; changed = true;
                  } else if (ptEq(first, wLast)) {
                    ring = ways[j].slice().concat(ring.slice(1));
                    used[j] = true; changed = true;
                  } else if (ptEq(first, wFirst)) {
                    ring = ways[j].slice().reverse().concat(ring.slice(1));
                    used[j] = true; changed = true;
                  }
                }
              }
              merged.push(ring);
            }
            return merged;
          }

          function ptEq(a, b) {
            return Math.abs(a[0] - b[0]) < 0.0000001 && Math.abs(a[1] - b[1]) < 0.0000001;
          }

          function drawBoundary(key, coordRings) {
            if (osmLayers[key]) return;
            var layer = L.polygon(coordRings, {
              color: '#2563eb',
              weight: 2.5,
              fillColor: '#3b82f6',
              fillOpacity: 0.15,
              opacity: 0.8,
              interactive: false
            }).addTo(map);
            osmLayers[key] = layer;
          }

          function clearAllBoundaries() {
            Object.keys(osmLayers).forEach(function(key) {
              map.removeLayer(osmLayers[key]);
            });
            osmLayers = {};
          }

          map.on('zoomend', function() {
            var zoom = map.getZoom();
            if (zoom >= 16 && !boundariesVisible) {
              boundariesVisible = true;
              loadVisibleBoundaries();
            } else if (zoom < 16 && boundariesVisible) {
              boundariesVisible = false;
              clearAllBoundaries();
            }
          });

          map.on('moveend', function() {
            if (boundariesVisible) {
              loadVisibleBoundaries();
            }
          });

          var viewportTimer = null;
          map.on('moveend', function() {
            clearTimeout(viewportTimer);
            viewportTimer = setTimeout(function() {
              var b = map.getBounds();
              window.webkit.messageHandlers.viewportChanged.postMessage(JSON.stringify({
                south: b.getSouth(),
                north: b.getNorth(),
                west: b.getWest(),
                east: b.getEast(),
                zoom: map.getZoom()
              }));
            }, 300);
          });

          updateUserLocation(\(userLat), \(userLon), 0, false);
          window.webkit.messageHandlers.mapReady.postMessage('ready');
        </script>
        </body>
        </html>
        """

        let readyHandler = MapReadyHandler(coordinator: context.coordinator)
        let positionHandler = SavePositionHandler()
        let uploadHandler = OpenUploadHandler(coordinator: context.coordinator)
        let osmCacheHandler = SaveOsmCacheHandler()
        let viewportHandler = ViewportChangedHandler(coordinator: context.coordinator)
        let followHandler = FollowModeHandler(coordinator: context.coordinator)
        webView.configuration.userContentController.add(readyHandler, name: "mapReady")
        webView.configuration.userContentController.add(positionHandler, name: "savePosition")
        webView.configuration.userContentController.add(uploadHandler, name: "openUpload")
        webView.configuration.userContentController.add(osmCacheHandler, name: "saveOsmCache")
        webView.configuration.userContentController.add(viewportHandler, name: "viewportChanged")
        webView.configuration.userContentController.add(followHandler, name: "followModeChanged")
        let baseURL = Bundle.main.bundleURL
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    // MARK: - Message Handlers

    class MapReadyHandler: NSObject, WKScriptMessageHandler {
        let coordinator: Coordinator
        init(coordinator: Coordinator) { self.coordinator = coordinator }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            coordinator.mapReady = true
            coordinator.onMapReady?()
        }
    }

    class SavePositionHandler: NSObject, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let str = message.body as? String,
                  let data = str.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = json["lat"] as? Double,
                  let lon = json["lon"] as? Double,
                  let zoom = json["zoom"] as? Int else { return }
            SavedMapPosition.save(lat: lat, lon: lon, zoom: zoom)
        }
    }

    class OpenUploadHandler: NSObject, WKScriptMessageHandler {
        let coordinator: Coordinator
        init(coordinator: Coordinator) { self.coordinator = coordinator }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let str = message.body as? String,
                  let data = str.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["name"] as? String,
                  let qid = json["qid"] as? String else { return }
            let img = json["img"] as? String ?? ""
            let type = (json["type"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let admin = (json["admin"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let heritage = (json["heritage"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let architect = (json["architect"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let style = (json["style"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            DispatchQueue.main.async {
                self.coordinator.onUploadTap?(UploadMonumentInfo(
                    name: name, wikidataId: qid, imageUrl: img,
                    instanceOf: type, adminEntity: admin, heritageDesig: heritage,
                    architect: architect, archStyle: style
                ))
            }
        }
    }

    class SaveOsmCacheHandler: NSObject, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let jsonStr = message.body as? String else { return }
            DispatchQueue.global(qos: .utility).async {
                OSMBoundaryCache.save(jsonString: jsonStr)
            }
        }
    }

    class ViewportChangedHandler: NSObject, WKScriptMessageHandler {
        let coordinator: Coordinator
        init(coordinator: Coordinator) { self.coordinator = coordinator }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let str = message.body as? String,
                  let data = str.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let south = json["south"] as? Double,
                  let north = json["north"] as? Double,
                  let west = json["west"] as? Double,
                  let east = json["east"] as? Double,
                  let zoom = json["zoom"] as? Int else { return }
            DispatchQueue.main.async {
                self.coordinator.onViewportChanged?(south, north, west, east, zoom)
            }
        }
    }

    class FollowModeHandler: NSObject, WKScriptMessageHandler {
        let coordinator: Coordinator
        init(coordinator: Coordinator) { self.coordinator = coordinator }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let isFollowing = (message.body as? String) == "true"
            DispatchQueue.main.async {
                self.coordinator.onFollowModeChanged?(isFollowing)
            }
        }
    }
}
