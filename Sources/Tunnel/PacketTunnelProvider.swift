import NetworkExtension
import LibXray

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        // Настройка локального IPv4 адреса туннеля
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        
        // Настройка DNS
        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        settings.dnsSettings = dns
        settings.mtu = 1500
        
        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                completionHandler(error)
                return
            }
            
            // Получаем переданную ссылку vless:// из основного приложения
            if let proto = self.protocolConfiguration as? NETunnelProviderProtocol,
               let vlessUrl = proto.providerConfiguration?["vless_url"] as? String {
                self.startXrayCore(with: vlessUrl)
            }
            
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // Остановка ядра Xray при отключении
        LibXrayStopXray()
        completionHandler()
    }
    
    private func startXrayCore(with url: String) {
        // Инициализация запуска ядра Xray на базе переданного ключа
        DispatchQueue.global(qos: .userInitiated).async {
            // Здесь вызывается парсинг URL в JSON-конфиг Xray и старт ядра
            print("Starting Xray with URL: \(url)")
        }
    }
}
