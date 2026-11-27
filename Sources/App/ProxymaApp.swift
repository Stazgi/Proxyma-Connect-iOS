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
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Button(action: vm.toggleTunnel) {
                        ZStack {
                            Circle()
                                .fill(vm.isConnected ? Color.green.opacity(0.2) : Color.blue.opacity(0.15))
                                .frame(width: 124, height: 124)
                            
                            Circle()
                                .stroke(vm.isConnected ? Color.green : Color.blue, lineWidth: 3)
                                .frame(width: 104, height: 104)
                            
                            Image(systemName: "power")
                                .font(.system(size: 40, weight: .bold))
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
                .padding(.top, 12)

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
                    if !vm.savedSubUrl.isEmpty {
                        Section(header: Text("Активная подписка")) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(vm.subTitle.isEmpty ? "Подписка" : vm.subTitle)
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                    Text(vm.savedSubUrl)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                
                                Button(action: vm.refreshSubscription) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                                
                                Button(action: vm.deleteSubscription) {
                                    Image(systemName: "trash.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                        }
                    }
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
                        Text("NexRay")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button("Вставить") {
                            if let paste = UIPasteboard.general.string {
                                vm.inputUrl = paste
                                vm.importFromInput()
                            }
                        }
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(vm: vm)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var vm: ProxymaViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Маршрутизация"), footer: Text("Российские сайты (.ru, .рф), банки и Госуслуги будут открываться напрямую без задержек.")) {
                    Toggle("Обход сайтов РФ (Direct)", isOn: $vm.bypassRussia)
                }

                Section(header: Text("Безопасность и DNS"), footer: Text("Использует защищённый DNS AdGuard для блокировки трекеров и баннеров.")) {
                    Toggle("Блокировка рекламы (AdGuard DNS)", isOn: $vm.blockAdsDns)
                }

                Section(header: Text("Управление данными")) {
                    Button(role: .destructive, action: {
                        vm.clearAllServers()
                        dismiss()
                    }) {
                        Label("Удалить все серверы и подписки", systemImage: "trash")
                    }
                }

                Section(header: Text("О приложении")) {
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text("1.0.0 (Xray Core)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
