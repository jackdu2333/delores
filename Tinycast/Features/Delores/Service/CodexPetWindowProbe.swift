import AppKit
import CoreGraphics
import CryptoKit
import Darwin
import Foundation

/// Reads Codex's private pet preference and live mascot geometry via its avatar overlay.
@MainActor
final class DeloresCodexPetWindowProbe {
    private nonisolated static let devToolsListURL = URL(string: "http://127.0.0.1:9341/json/list")!
    private nonisolated static let refreshInterval: Duration = .milliseconds(180)
    private nonisolated static let cachedFrameLifetime: TimeInterval = 0.75
    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private struct OverlayObservation: Sendable {
        let petVisibilityPreference: Bool?
        let measurement: OverlayMeasurement?
    }

    private struct OverlayMeasurement: Sendable {
        let rect: CGRect
        let activityRect: CGRect?
        let screenOrigin: CGPoint
    }

    private var refreshTask: Task<Void, Never>?
    private var cachedFrame: CGRect?
    private var cachedActivityFrame: CGRect?
    private var cachedOverlayVisible = false
    private var cachedAt = -Double.infinity
    private var failedRefreshes = 0
    private var cachedPetVisibilityPreference: Bool?
    var onAutomaticPetEnabledChange: (() -> Void)?

    var hasVisiblePet: Bool { currentFrame != nil }
    var isCodexPetEnabled: Bool { cachedPetVisibilityPreference ?? hasVisiblePet }

    func applyEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        cachedFrame = nil
        cachedActivityFrame = nil
        cachedOverlayVisible = false
        cachedAt = -Double.infinity
        failedRefreshes = 0
        cachedPetVisibilityPreference = nil
    }

    func anchor(on screen: NSScreen) -> DeloresCompanionAnchor? {
        guard let frame = currentFrame else { return nil }
        guard screen.frame.contains(frame.midPoint) else { return nil }
        return (
            center: frame.midPoint,
            edge: DeloresCompanionWander.edge(for: frame.midPoint, in: screen.frame),
            radius: max(frame.width, frame.height) / 2)
    }

    /// A drag that starts here belongs to Codex's pet, not to a window behind it.
    func containsPet(at point: CGPoint) -> Bool {
        guard let frame = currentFrame else { return false }
        return frame.insetBy(dx: -12, dy: -12).contains(point)
    }

    func activityFrame(on screen: NSScreen) -> CGRect? {
        guard let frame = currentActivityFrame, screen.frame.intersects(frame) else { return nil }
        return frame.intersection(screen.frame)
    }

    private var currentFrame: CGRect? {
        guard cachedOverlayVisible, let cachedFrame, ProcessInfo.processInfo.systemUptime - cachedAt
            <= Self.cachedFrameLifetime
        else { return nil }
        return cachedFrame
    }

    private var currentActivityFrame: CGRect? {
        guard cachedOverlayVisible, let cachedActivityFrame,
            ProcessInfo.processInfo.systemUptime - cachedAt <= Self.cachedFrameLifetime
        else { return nil }
        return cachedActivityFrame
    }

    private func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let observation = await Self.readObservation()
                guard !Task.isCancelled, let self else { return }
                self.update(observation)
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    private func update(_ observation: OverlayObservation?) {
        let wasEnabled = isCodexPetEnabled
        guard let observation else {
            failedRefreshes += 1
            cachedPetVisibilityPreference = nil
            if failedRefreshes >= 3 {
                cachedFrame = nil
                cachedActivityFrame = nil
                cachedAt = -Double.infinity
            }
            notifyAutomaticPetEnabledChange(from: wasEnabled)
            return
        }
        failedRefreshes = 0
        cachedPetVisibilityPreference = observation.petVisibilityPreference
        guard let measurement = observation.measurement else {
            cachedFrame = nil
            cachedActivityFrame = nil
            cachedOverlayVisible = false
            cachedAt = -Double.infinity
            notifyAutomaticPetEnabledChange(from: wasEnabled)
            return
        }
        let quartzFrame = CGRect(
            x: measurement.screenOrigin.x + measurement.rect.minX,
            y: measurement.screenOrigin.y + measurement.rect.minY,
            width: measurement.rect.width,
            height: measurement.rect.height)
        cachedOverlayVisible = Self.isVisibleCodexOverlay(at: quartzFrame.midPoint)
        let geometry = AXGeometry(screens: NSScreen.screens)
        cachedFrame = geometry.flip(quartzFrame)
        cachedActivityFrame = measurement.activityRect.map { rect in
            geometry.flip(
                CGRect(
                    x: measurement.screenOrigin.x + rect.minX,
                    y: measurement.screenOrigin.y + rect.minY,
                    width: rect.width,
                    height: rect.height))
        }
        cachedAt = ProcessInfo.processInfo.systemUptime
        notifyAutomaticPetEnabledChange(from: wasEnabled)
    }

    private func notifyAutomaticPetEnabledChange(from previousValue: Bool) {
        guard previousValue != isCodexPetEnabled else { return }
        onAutomaticPetEnabledChange?()
    }

    private static func isVisibleCodexOverlay(at point: CGPoint) -> Bool {
        let processIDs = Set(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.openai.codex"
            ).map(\.processIdentifier))
        guard !processIDs.isEmpty else { return false }
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { window in
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                processIDs.contains(pid),
                let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                layer > 0,
                let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                alpha > 0,
                let onScreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue,
                onScreen,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds)
            else { return false }
            return frame.contains(point)
        }
    }

    private nonisolated static func readObservation() async -> OverlayObservation? {
        do {
            let request = URLRequest(url: devToolsListURL, timeoutInterval: 0.75)
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                let targets = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return nil }

            for target in targets where target["type"] as? String == "page"
                && (target["url"] as? String)?.contains("avatar-overlay") == true
            {
                guard let webSocketURL = target["webSocketDebuggerUrl"] as? String,
                    let url = URL(string: webSocketURL),
                    url.host == "127.0.0.1", url.port == 9341,
                    let observation = await readObservation(from: url)
                else { continue }
                return observation
            }
        } catch {
            return nil
        }
        return nil
    }

    private nonisolated static func readObservation(
        from url: URL
    ) async -> OverlayObservation? {
        let expression = """
        (() => {
            let petVisibilityPreference = null;
            try {
                const stored = window.localStorage.getItem(
                    "codex:persisted-atom:avatar-overlay-pet-visible"
                );
                if (stored !== null) {
                    const parsed = JSON.parse(stored);
                    if (typeof parsed === "boolean") petVisibilityPreference = parsed;
                }
            } catch {}
            const element =
                document.querySelector('[data-avatar-mascot="true"]') ||
                document.querySelector('[data-avatar-overlay-hit-region="mascot"]');
            let mascot = null;
            if (element) {
                const rect = element.getBoundingClientRect();
                const style = getComputedStyle(element);
                if (rect.width > 0 && rect.height > 0 &&
                    style.display !== "none" && style.visibility !== "hidden" &&
                    Number(style.opacity) > 0) {
                    const activity =
                        document.querySelector('[class*="ActivityStackViewport"]') ||
                        document.querySelector('[class*="activityPill"]');
                    const activityStyle = activity && getComputedStyle(activity);
                    const activityRect = activity && activityStyle.display !== "none" &&
                        activityStyle.visibility !== "hidden" && Number(activityStyle.opacity) > 0
                        ? activity.getBoundingClientRect()
                        : null;
                    mascot = {
                        x: rect.x,
                        y: rect.y,
                        width: rect.width,
                        height: rect.height,
                        activity: activityRect && activityRect.width > 0 && activityRect.height > 0
                            ? {
                                x: activityRect.x,
                                y: activityRect.y,
                                width: activityRect.width,
                                height: activityRect.height
                            }
                            : null
                    };
                }
            }
            return {
                petVisibilityPreference,
                mascot,
                screenX: window.screenX,
                screenY: window.screenY
            };
        })()
        """
        let command: [String: Any] = [
            "id": 1,
            "method": "Runtime.evaluate",
            "params": ["expression": expression, "returnByValue": true],
        ]
        guard let commandData = try? JSONSerialization.data(withJSONObject: command),
            let responseData = await Task.detached(priority: .utility, operation: {
                DeloresCodexWebSocket.request(url: url, payload: commandData)
            }).value,
            let envelope = try? JSONSerialization.jsonObject(with: responseData)
                as? [String: Any],
            (envelope["id"] as? NSNumber)?.intValue == 1,
            let result = envelope["result"] as? [String: Any],
            let remoteResult = result["result"] as? [String: Any],
            let value = remoteResult["value"] as? [String: Any],
            let screenX = value["screenX"] as? NSNumber,
            let screenY = value["screenY"] as? NSNumber
        else { return nil }
        let preference = value["petVisibilityPreference"] as? Bool
        var measurement: OverlayMeasurement?
        let activityRect: CGRect?
        if let mascot = value["mascot"] as? [String: Any],
            let x = mascot["x"] as? NSNumber,
            let y = mascot["y"] as? NSNumber,
            let width = mascot["width"] as? NSNumber,
            let height = mascot["height"] as? NSNumber
        {
            if let activity = mascot["activity"] as? [String: Any],
                let activityX = activity["x"] as? NSNumber,
                let activityY = activity["y"] as? NSNumber,
                let activityWidth = activity["width"] as? NSNumber,
                let activityHeight = activity["height"] as? NSNumber
            {
                activityRect = CGRect(
                    x: activityX.doubleValue, y: activityY.doubleValue,
                    width: activityWidth.doubleValue, height: activityHeight.doubleValue)
            } else {
                activityRect = nil
            }
            measurement = OverlayMeasurement(
                rect: CGRect(
                    x: x.doubleValue, y: y.doubleValue,
                    width: width.doubleValue, height: height.doubleValue),
                activityRect: activityRect,
                screenOrigin: CGPoint(x: screenX.doubleValue, y: screenY.doubleValue))
        }
        return OverlayObservation(
            petVisibilityPreference: preference, measurement: measurement)
    }
}

private enum DeloresCodexWebSocket {
    static func request(url: URL, payload: Data) -> Data? {
        guard url.scheme == "ws", let host = url.host, let port = url.port else { return nil }
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var timeout = timeval(tv_sec: 0, tv_usec: 700_000)
        withUnsafePointer(to: &timeout) { pointer in
            _ = Darwin.setsockopt(
                descriptor, SOL_SOCKET, SO_RCVTIMEO, pointer,
                socklen_t(MemoryLayout<timeval>.size))
            _ = Darwin.setsockopt(
                descriptor, SOL_SOCKET, SO_SNDTIMEO, pointer,
                socklen_t(MemoryLayout<timeval>.size))
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return nil }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }

        let lineBreak = "\r\n"
        let key = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
            .base64EncodedString()
        let acceptSource = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let expectedAccept = Data(Insecure.SHA1.hash(data: Data(acceptSource.utf8)))
            .base64EncodedString()
        let requestLines = [
            "GET \(url.path) HTTP/1.1",
            "Host: \(host):\(port)",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13",
            "",
            "",
        ]
        let request = Data(requestLines.joined(separator: lineBreak).utf8)
        guard send(request, on: descriptor),
            readHandshake(on: descriptor, expectedAccept: expectedAccept),
            send(frame(payload, opcode: 0x1), on: descriptor)
        else { return nil }
        return readTextFrame(on: descriptor)
    }

    private static func send(_ data: Data, on descriptor: Int32) -> Bool {
        var offset = 0
        while offset < data.count {
            let sent = data.withUnsafeBytes { bytes in
                Darwin.send(
                    descriptor, bytes.baseAddress!.advanced(by: offset), data.count - offset, 0)
            }
            guard sent > 0 else { return false }
            offset += sent
        }
        return true
    }

    private static func read(_ count: Int, on descriptor: Int32) -> Data? {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let received = data.withUnsafeMutableBytes { bytes in
                Darwin.recv(descriptor, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
            }
            guard received > 0 else { return nil }
            offset += received
        }
        return data
    }

    private static func readHandshake(on descriptor: Int32, expectedAccept: String) -> Bool {
        var response = Data()
        while response.count < 8_192 {
            guard let byte = read(1, on: descriptor) else { return false }
            response.append(byte)
            if response.suffix(4) == Data([13, 10, 13, 10]) {
                guard let header = String(bytes: response, encoding: .utf8) else { return false }
                let lines = header.components(separatedBy: "\r\n")
                guard lines.first?.contains(" 101 ") == true,
                    let acceptLine = lines.first(where: {
                        $0.lowercased().hasPrefix("sec-websocket-accept:")
                    })
                else { return false }
                return acceptLine
                    .split(separator: ":", maxSplits: 1)
                    .last
                    .map { $0.trimmingCharacters(in: .whitespaces) == expectedAccept } == true
            }
        }
        return false
    }

    private static func frame(_ payload: Data, opcode: UInt8) -> Data {
        var bytes = Data([0x80 | opcode])
        let mask: [UInt8] = (0..<4).map { _ in UInt8.random(in: .min ... .max) }
        if payload.count < 126 {
            bytes.append(0x80 | UInt8(payload.count))
        } else if payload.count <= Int(UInt16.max) {
            bytes.append(0x80 | 126)
            bytes.append(UInt8((payload.count >> 8) & 0xff))
            bytes.append(UInt8(payload.count & 0xff))
        } else {
            return Data()
        }
        bytes.append(contentsOf: mask)
        bytes.append(contentsOf: payload.enumerated().map { index, byte in
            byte ^ mask[index % mask.count]
        })
        return bytes
    }

    private static func readTextFrame(on descriptor: Int32) -> Data? {
        while true {
            guard let header = read(2, on: descriptor) else { return nil }
            let opcode = header[0] & 0x0f
            var length = Int(header[1] & 0x7f)
            if length == 126 {
                guard let extended = read(2, on: descriptor) else { return nil }
                length = Int(extended[0]) << 8 | Int(extended[1])
            } else if length == 127 {
                return nil
            }

            let masked = header[1] & 0x80 != 0
            let mask = masked ? Array(read(4, on: descriptor) ?? Data()) : []
            guard !masked || mask.count == 4, let payload = read(length, on: descriptor) else {
                return nil
            }
            if opcode == 0x1 {
                guard masked else { return payload }
                return Data(payload.enumerated().map { index, byte in
                    byte ^ mask[index % mask.count]
                })
            }
            if opcode == 0x8 { return nil }
            if opcode == 0x9, !send(frame(payload, opcode: 0xA), on: descriptor) {
                return nil
            }
        }
    }
}

private extension CGRect {
    var midPoint: CGPoint { CGPoint(x: midX, y: midY) }
}
