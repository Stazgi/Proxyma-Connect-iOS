import SwiftUI

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
    @StateObject private var vm = ProxymaViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 14) {
                    Button(action: vm.toggleTunnel) {
                        ZStack {
                            Circle()
                                .fill(vm.isConnected ? Color.green.opacity(0.2) : Color.blue.opacity(0.15))
                                .frame(width: 130, height: 130)
                            
                            Circle()
                                .stroke(vm.isConnected ? Color.green : Color.blue, lineWidth: 3)
                                .frame(width: 110, height: 110)
                            
                            Image(systemName: "power")
                                .font(.system(size: 42, weight: .bold))
                                .foregroundColor(vm.isConnected ? .green : .blue)
                        }
                    }
                    .disabled(vm.selectedServer == nil && !vm.isConnected)
                    
                    Text(vm.statusText)
                        .font(.headline)
                        .foregroundColor(vm.isConnected ? .green : .gray)
                    
                    if let current = vm.selectedServer {
                        Text(current.name)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.top, 16)

                HStack(spacing: 8) {
                    TextField("Вставьте подписку или vless://", text: $vm.inputUrl)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Button(action: vm.importFromInput) {
                        if vm.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                    .disabled(vm.inputUrl.isEmpty || vm.isLoading)
                }
                .padding(.horizontal)

                List {
                    Section(header: HStack {
                        Text("Серверы (\(vm.servers.count))")
                        Spacer()
                        if !vm.servers.isEmpty {
                            Button(action: vm.pingAllServers) {
                                Label("Пинг", systemImage: "speedometer")
                                    .font(.caption)
                                    .textCase(.none)
                            }
                        }
                    }) {
                        if vm.servers.isEmpty {
                            Text("Добавьте ключ vless:// или ссылку подписки")
                                .foregroundColor(.secondary)
                                .font(.footnote)
                        } else {
                            ForEach(vm.servers) { server in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(server.name)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(server.rawUrl.prefix(26) + "...")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    
                                    if let ms = server.pingMs {
                                        if ms > 0 {
                                            Text("\(ms) ms")
                                                .font(.caption.monospacedDigit())
                                                .foregroundColor(ms < 150 ? .green : (ms < 350 ? .orange : .red))
                                        } else {
                                            Text("Таймаут")
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                        }
                                    }
                                    
                                    if vm.selectedServer?.id == server.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    vm.selectedServer = server
                                }
                            }
                            .onDelete(perform: vm.deleteServers)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundColor(.blue)
                            .font(.subheadline)
                        Text("Proxyma Connect")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if !vm.savedSubUrl.isEmpty {
                            Button(action: vm.refreshSubscription) {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        Button("Вставить") {
                            if let paste = UIPasteboard.general.string {
                                vm.inputUrl = paste
                                vm.importFromInput()
                            }
                        }
                    }
                }
            }
        }
    }
}
