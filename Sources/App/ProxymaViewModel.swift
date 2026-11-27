import Foundation
import NetworkExtension
import Network

struct ServerItem: Identifiable, Codable, Equatable {
    var id = UUID()
    let name: String
    let rawUrl: String
    var pingMs: Int?
    var isFromSub: Bool = false
}

class ProxymaViewModel: ObservableObject {
    @Published var inputUrl: String = ""
    @Published var savedSubUrl: String = ""
    @Published var subTitle: String = ""
    @Published var servers: [ServerItem] = []
    @Published var selectedServer: ServerItem?
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusText: String = "Не подключено"
    
    @Published var bypassRussia: Bool = true {
        didSet { UserDefaults.standard.set(bypassRussia, forKey: "bypass_russia") }
    }
    @Published var blockAdsDns: Bool = false {
        didSet { UserDefaults.standard.set(blockAdsDns, forKey: "block_ads_dns") }
    }
    
    private var manager: NETunnelProviderManager?

    init() {
        savedSubUrl = UserDefaults.standard.string(forKey: "saved_sub_url") ?? ""
        subTitle = UserDefaults.standard.string(forKey: "saved_sub_title") ?? ""
        if UserDefaults.standard.object(forKey: "bypass_russia") != nil {
            bypassRussia = UserDefaults.standard.bool(forKey: "bypass_russia")
        }
        blockAdsDns = UserDefaults.standard.bool(forKey: "block_ads_dns")
        loadServers()
        loadTunnel()
    }

    func importFromInput() {
        let trimmed = inputUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            savedSubUrl = trimmed
            UserDefaults.standard.set(trimmed, forKey: "saved_sub_url")
            fetchSubscription(from: trimmed)
            inputUrl = ""
        } else {
            parseLines(trimmed, isSub: false)
            inputUrl = ""
        }
    }

    func refreshSubscription() {
        guard !savedSubUrl.isEmpty else { return }
        fetchSubscription(from: savedSubUrl)
    }

    func deleteSubscription() {
        savedSubUrl = ""
        subTitle = ""
        UserDefaults.standard.removeObject(forKey: "saved_sub_url")
        UserDefaults.standard.removeObject(forKey: "saved_sub_title")
        servers.removeAll { $0.isFromSub }
        if !servers.contains(where: { $0.id == selectedServer?.id }) {
            selectedServer = servers.first
        }
        saveServers()
    }

    func clearAllServers() {
        deleteSubscription()
        servers.removeAll()
        selectedServer = nil
        saveServers()
    }
        private func fetchSubscription(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        isLoading = true
        
        var request = URLRequest(url: url)
        request.setValue("NexRay/1.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                self?.isLoading = false
                guard let self = self, let data = data, let text = String(data: data, encoding: .utf8) else { return }
                
                var detectedName = url.host ?? "Подписка"
                if let httpResp = response as? HTTPURLResponse,
                   let rawTitle = httpResp.value(forHTTPHeaderField: "profile-title") {
                    if rawTitle.hasPrefix("base64:"),
                       let decodedTitle = self.decodeBase64(String(rawTitle.dropFirst(7))) {
                        detectedName = decodedTitle
                    } else if !rawTitle.isEmpty {
                        detectedName = rawTitle
                    }
                }
                self.subTitle = detectedName
                UserDefaults.standard.set(detectedName, forKey: "saved_sub_title")
                
                let decoded = self.decodeBase64(text) ?? text
                self.parseLines(decoded, isSub: true)
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
        if !servers.contains(where: { $0.id == selectedServer?.id }) {
            selectedServer = servers.first
        }
        saveServers()
    }

    private func parseLines(_ text: String, isSub: Bool) {
        var newItems: [ServerItem] = isSub ? servers.filter { !$0.isFromSub } : servers
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.hasPrefix("vless://") || clean.hasPrefix("vmess://") || clean.hasPrefix("trojan://") {
                let name = extractName(from: clean)
                newItems.append(ServerItem(name: name, rawUrl: clean, isFromSub: isSub))
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
        proto.providerConfiguration = [
            "vless_url": server.rawUrl,
            "bypass_russia": bypassRussia,
            "block_ads_dns": blockAdsDns
        ]

        targetManager.protocolConfiguration = proto
        targetManager.localizedDescription = "NexRay"
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
