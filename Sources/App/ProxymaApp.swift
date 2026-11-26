import SwiftUI
import NetworkExtension

@main
struct ProxymaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var vlessLink: String = ""
    @State private var isConnected: Bool = false
    @State private var statusText: String = "Отключено"
    @State private var manager: NETunnelProviderManager?

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Статус подключения
                VStack(spacing: 8) {
                    Image(systemName: isConnected ? "shield.checkered" : "shield.slash")
                        .font(.system(size: 64))
                        .foregroundColor(isConnected ? .green : .gray)
                    
                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(isConnected ? .green : .secondary)
                }
                .padding(.top, 20)

                // Поле ввода ключа VLESS / VMess
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ключ подключения (vless://)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        TextField("Вставьте ссылку...", text: $vlessLink)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                        
                        Button("Вставить") {
                            if let paste = UIPasteboard.general.string {
                                vlessLink = paste
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)

                // Кнопка запуска
                Button(action: toggleTunnel) {
                    Text(isConnected ? "Отключиться" : "Подключиться")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isConnected ? Color.red : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal)
                .disabled(vlessLink.isEmpty && !isConnected)

                Spacer()
            }
            .navigationTitle("Proxyma Connect")
            .onAppear(perform: loadTunnel)
        }
    }

    private func loadTunnel() {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            if let existing = managers?.first {
                self.manager = existing
                self.isConnected = (existing.connection.status == .connected)
                self.statusText = isConnected ? "Подключено" : "Отключено"
            }
        }
    }

    private func toggleTunnel() {
        if isConnected {
            manager?.connection.stopVPNTunnel()
            isConnected = false
            statusText = "Отключено"
            return
        }

        let targetManager = manager ?? NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.proxyma.connect.tunnel"
        proto.serverAddress = "Proxyma Server"
        proto.providerConfiguration = ["vless_url": vlessLink]

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
                    self.statusText = "Сбой запуска: \(error.localizedDescription)"
                }
            }
        }
    }
}
