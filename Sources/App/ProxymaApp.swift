import SwiftUI
import NetworkExtension

struct ServerItem: Identifiable, Codable, Equatable {
    var id = UUID()
    let name: String
    let rawUrl: String
}

@main
struct ProxymaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @State private var inputUrl: String = ""
    @State private var servers: [ServerItem] = []
    @State private var selectedServer: ServerItem?
    @State private var isConnected: Bool = false
    @State private var isLoading: Bool = false
    @State private var statusText: String = "Не подключено"
    @State private var manager: NETunnelProviderManager?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 14) {
                    Button(action: toggleTunnel) {
                        ZStack {
                            Circle()
                                .fill(isConnected ? Color.green.opacity(0.2) : Color.blue.opacity(0.15))
                                .frame(width: 130, height: 130)
                            
                            Circle()
                                .stroke(isConnected ? Color.green : Color.blue, lineWidth: 3)
                                .frame(width: 110, height: 110)
                            
                            Image(systemName: "power")
                                .font(.system(size: 42, weight: .bold))
                                .foregroundColor(isConnected ? .green : .blue)
                        }
                    }
                    .disabled(selectedServer == nil && !isConnected)
                    
                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(isConnected ? .green : .gray)
                    
                    if let current = selectedServer {
                        Text(current.name)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.top, 10)

                HStack(spacing: 8) {
                    TextField("Вставьте подписку или vless://", text: $inputUrl)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Button(action: importFromInput) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                    .disabled(inputUrl.isEmpty || isLoading)
                }
                .padding(.horizontal)

                List {
                    Section(header: Text("Серверы (\(servers.count))")) {
                        if servers.isEmpty {
                            Text("Добавьте ключ vless:// или ссылку подписки")
                                .foregroundColor(.secondary)
                                .font(.footnote)
                        } else {
                            ForEach(servers) { server in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(server.name)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(server.rawUrl.prefix(28) + "...")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedServer?.id == server.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedServer = server
                                }
                            }
                            .onDelete { indexSet in
                                servers.remove(atOffsets: indexSet)
                                saveServers()
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Proxyma Connect")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Вставить") {
                        if let paste = UIPasteboard.general.string {
                            inputUrl = paste
                            importFromInput()
                        }
                    }
                }
            }
            .onAppear {
                loadServers()
                loadTunnel()
            }
        }
    }

    private func importFromInput() {
        let trimmed = inputUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            guard let url = URL(string: trimmed) else { return }
            isLoading = true
            URLSession.shared.dataTask(with: url) { data, _, _ in
                DispatchQueue.main.async {
                    isLoading = false
                    guard let data = data, let text = String(data: data, encoding: .utf8) else { return }
                    let decoded = decodeBase64(text) ?? text
                    parseLines(decoded)
                    inputUrl = ""
                }
            }.resume()
        } else {
            parseLines(trimmed)
            inputUrl = ""
        }
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
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            if let existing = managers?.first {
                self.manager = existing
                self.isConnected = (existing.connection.status == .connected)
                self.statusText = isConnected ? "Подключено" : "Не подключено"
            }
        }
    }

    private func toggleTunnel() {
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

        targetManager.saveToPreferences { error in
            if let error = error {
                statusText = "Ошибка: \(error.localizedDescription)"
                return
            }
            targetManager.loadFromPreferences { _ in
                do {
                    try targetManager.connection.startVPNTunnel()
                    self.manager = targetManager
                    self.isConnected = true
                    self.statusText = "Подключено"
                } catch {
                    self.statusText = "Сбой: \(error.localizedDescription)"
                }
            }
        }
    }
}
