import Foundation
import NetworkExtension
import Network

struct ServerItem: Identifiable, Codable, Equatable {
    var id = UUID()
    let name: String
    let rawUrl: String
    var pingMs: Int?
}

class ProxymaViewModel: ObservableObject {
    @Published var inputUrl: String = ""
    @Published var savedSubUrl: String = ""
    @Published var servers: [ServerItem] = []
    @Published var selectedServer: ServerItem?
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusText: String = "Не подключено"
    
    private var manager: NETunnelProviderManager?

    init() {
        savedSubUrl = UserDefaults.standard.string(forKey: "saved_sub_url") ?? ""
        loadServers()
        loadTunnel()
    }

    func importFromInput() {
        let trimmed = inputUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            savedSubUrl = trimmed
            UserDefaults.standard.set(trimmed, forKey: "saved_sub_url")
            fetchSubscription(from: trimmed, replaceExisting: false)
            inputUrl = ""
        } else {
            parseLines(trimmed, replaceExisting: false)
            inputUrl = ""
        }
    }

    func refreshSubscription() {
        guard !savedSubUrl.isEmpty else { return }
        fetchSubscription(from: savedSubUrl, replaceExisting: true)
    }

    private func fetchSubscription(from urlString: String, replaceExisting: Bool) {
        guard let url = URL(string: urlString) else { return }
        isLoading = true
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                self?.isLoading = false
                guard let data = data, let text = String(data: data, encoding: .utf8) else { return }
                let decoded = self?.decodeBase64(text) ?? text
                self?.parseLines(decoded, replaceExisting: replaceExisting)
            }
        }.resume()
    }

    func pingAllServers() {
        for index in servers.indices {
            servers[index].pingMs = nil
            let raw = servers[index].rawUrl
            let serverId = servers[index].id
            
            guard let url = URL(string: raw), let host = url.host else { continue }
            let port = UInt16(url.port ?? 443)
            
            measureTcpPing(host: host, port: port) { [weak self] ms in
                DispatchQueue.main.async {
                    if let idx = self?.servers.firstIndex(where: { $0.id == serverId }) {
                        self?.servers[idx].pingMs = ms
                    }
                }
            }
        }
    }

    private func measureTcpPing(host: String, port: UInt16, completion: @escaping (Int) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { completion(-1); return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let start = Date()
        var finished = false
        
        connection.stateUpdateHandler = { state in
            guard !finished else { return }
            switch state {
            case .ready:
                finished = true
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                connection.cancel()
                completion(max(1, elapsed))
            case .failed(_):
                finished = true
                connection.cancel()
                completion(-1)
            default:
                break
            }
        }
        
        connection.start(queue: .global(qos: .utility))
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) {
            if !finished {
                finished = true
                connection.cancel()
                completion(-1)
            }
        }
    }

    func deleteServers(at offsets: IndexSet) {
        servers.remove(atOffsets: offsets)
        saveServers()
    }

    private func parseLines(_ text: String, replaceExisting: Bool) {
        var newItems: [ServerItem] = replaceExisting ? [] : servers
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.hasPrefix("vless://") || clean.hasPrefix("vmess://") || clean.hasPrefix("trojan://") {
                let name = extractName(from: clean)
                newItems.append(ServerItem(name: name, rawUrl: clean))
            }
        }
        servers = newItems
        if selectedServer == nil || !servers.contains(where: { $0.id == selectedServer?.id }) {
            selectedServer = servers.first
        }
        saveServers()
        pingAllServers()
    }

    private func extractName(from link: String) -> String {
        if let hashIndex = link.lastIndex(of: "#") {
            let rawName = String(link[link.index(after: hashIndex)...])
            return rawName.removingPercentEncoding ?? rawName
        }
        return "Proxyma Server"
    }

    private func decodeBase64(_ str: String) -> String? {
        var padded = str.trimmingCharacters(in: .whitespacesAndNewlines)
        let rem = padded.count % 4
        if rem > 0 { padded += String(repeating: "=", count: 4 - rem) }
        guard let data = Data(base64Encoded: padded) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: "saved_servers")
        }
    }

    private func loadServers() {
        if let data = UserDefaults.standard.data(forKey: "saved_servers"),
           let decoded = try? JSONDecoder().decode([ServerItem].self, from: data) {
            servers = decoded
            selectedServer = servers.first
            pingAllServers()
        }
    }

    private func loadTunnel() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            if let existing = managers?.first {
                self?.manager = existing
                self?.isConnected = (existing.connection.status == .connected)
                self?.statusText = (self?.isConnected == true) ? "Подключено" : "Не подключено"
            }
        }
    }

    func toggleTunnel() {
        if isConnected {
            manager?.connection.stopVPNTunnel()
            isConnected = false
            statusText = "Не подключено"
            return
        }

        guard let server = selectedServer else { return }

        let targetManager = manager ?? NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.proxyma.connect.tunnel"
        proto.serverAddress = server.name
        proto.providerConfiguration = ["vless_url": server.rawUrl]

        targetManager.protocolConfiguration = proto
        targetManager.localizedDescription = "Proxyma Connect"
        targetManager.isEnabled = true

        targetManager.saveToPreferences { [weak self] error in
            if let error = error {
                self?.statusText = "Ошибка: \(error.localizedDescription)"
                return
            }
            targetManager.loadFromPreferences { _ in
                do {
                    try targetManager.connection.startVPNTunnel()
                    self?.manager = targetManager
                    self?.isConnected = true
                    self?.statusText = "Подключено"
                } catch {
                    self?.statusText = "Сбой: \(error.localizedDescription)"
                }
            }
        }
    }
}
