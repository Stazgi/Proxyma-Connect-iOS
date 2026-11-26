import Foundation
import NetworkExtension

struct ServerItem: Identifiable, Codable, Equatable {
    var id = UUID()
    let name: String
    let rawUrl: String
}

class ProxymaViewModel: ObservableObject {
    @Published var inputUrl: String = ""
    @Published var servers: [ServerItem] = []
    @Published var selectedServer: ServerItem?
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusText: String = "Не подключено"
    
    private var manager: NETunnelProviderManager?

    init() {
        loadServers()
        loadTunnel()
    }

    func importFromInput() {
        let trimmed = inputUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            guard let url = URL(string: trimmed) else { return }
            isLoading = true
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    guard let data = data, let text = String(data: data, encoding: .utf8) else { return }
                    let decoded = self?.decodeBase64(text) ?? text
                    self?.parseLines(decoded)
                    self?.inputUrl = ""
                }
            }.resume()
        } else {
            parseLines(trimmed)
            inputUrl = ""
        }
    }

    func deleteServers(at offsets: IndexSet) {
        servers.remove(atOffsets: offsets)
        saveServers()
    }

    private func parseLines(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.hasPrefix("vless://") || clean.hasPrefix("vmess://") || clean.hasPrefix("trojan://") {
                let name = extractName(from: clean)
                let item = ServerItem(name: name, rawUrl: clean)
                servers.append(item)
                if selectedServer == nil { selectedServer = item }
            }
        }
        saveServers()
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
