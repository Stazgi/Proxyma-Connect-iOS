import NetworkExtension
import Foundation
import LibXray
import Tun2SocksKit

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private let socksPort: Int = 10808
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let proto = self.protocolConfiguration as? NETunnelProviderProtocol,
              let conf = proto.providerConfiguration,
              let vlessUrl = conf["vless_url"] as? String else {
            completionHandler(NSError(domain: "com.proxyma.connect", code: 1, userInfo: [NSLocalizedDescriptionKey: "Неверный ключ"]))
            return
        }
        
        let bypassRussia = (conf["bypass_russia"] as? Bool) ?? true
        let blockAdsDns = (conf["block_ads_dns"] as? Bool) ?? false
        
        guard let configJson = buildXrayConfig(from: vlessUrl, bypassRussia: bypassRussia) else {
            completionHandler(NSError(domain: "com.proxyma.connect", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ошибка конфигурации"]))
            return
        }
        
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        
        let dnsServers = blockAdsDns ? ["94.140.14.14", "94.140.15.15"] : ["1.1.1.1", "8.8.8.8"]
        settings.dnsSettings = NEDNSSettings(servers: dnsServers)
        settings.mtu = 1500
        
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                completionHandler(error)
                return
            }
            
            self.startXrayAndSocks(configJson: configJson)
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        Socks5Tunnel.quit()
        let stopReq: [String: Any] = ["method": "stopXray"]
        if let data = try? JSONSerialization.data(withJSONObject: stopReq),
           let jsonStr = String(data: data, encoding: .utf8) {
            _ = LibXrayInvoke(jsonStr)
        }
        completionHandler()
    }
    
    private func startXrayAndSocks(configJson: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("config.json")
        try? configJson.write(to: configFile, atomically: true, encoding: .utf8)
        
        let runRequest: [String: Any] = [
            "method": "runXray",
            "datDir": tempDir.path,
            "configPath": configFile.path
        ]
        
        if let reqData = try? JSONSerialization.data(withJSONObject: runRequest),
           let reqStr = String(data: reqData, encoding: .utf8) {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = LibXrayInvoke(reqStr)
            }
        }
        
        let socksConfig = """
        tunnel:
          mtu: 1500
        socks5:
          port: \(socksPort)
          address: 127.0.0.1
          udp: 'udp'
        """
        Socks5Tunnel.run(withConfig: .string(content: socksConfig)) { _ in }
    }
        private func buildXrayConfig(from urlString: String, bypassRussia: Bool) -> String? {
        guard let url = URL(string: urlString),
              url.scheme == "vless",
              let uuid = url.user,
              let host = url.host else { return nil }
        
        let port = url.port ?? 443
        var queryDict: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            for item in items {
                queryDict[item.name] = item.value ?? ""
            }
        }
        
        let network = queryDict["type"] ?? "tcp"
        let security = queryDict["security"] ?? "none"
        let sni = queryDict["sni"] ?? host
        let fp = queryDict["fp"] ?? "chrome"
        let pbk = queryDict["pbk"] ?? ""
        let sid = queryDict["sid"] ?? ""
        let flow = queryDict["flow"] ?? ""
        
        var streamSettings: [String: Any] = [
            "network": network,
            "security": security
        ]
        
        if security == "reality" {
            streamSettings["realitySettings"] = [
                "show": false,
                "fingerprint": fp,
                "serverName": sni,
                "publicKey": pbk,
                "shortId": sid
            ]
        } else if security == "tls" {
            streamSettings["tlsSettings"] = [
                "serverName": sni,
                "fingerprint": fp
            ]
        }
        
        if network == "ws" {
            streamSettings["wsSettings"] = [
                "path": queryDict["path"] ?? "/",
                "headers": ["Host": queryDict["host"] ?? sni]
            ]
        } else if network == "grpc" {
            streamSettings["grpcSettings"] = [
                "serviceName": queryDict["serviceName"] ?? ""
            ]
        }
        
        var userDict: [String: Any] = [
            "id": uuid,
            "encryption": "none"
        ]
        if !flow.isEmpty {
            userDict["flow"] = flow
        }
        
        var routingRules: [[String: Any]] = [
            [
                "type": "field",
                "ip": ["geoip:private"],
                "outboundTag": "direct"
            ]
        ]
        
        if bypassRussia {
            routingRules.append([
                "type": "field",
                "domain": ["regexp:.*\\.ru$", "regexp:.*\\.xn--p1ai$"],
                "outboundTag": "direct"
            ])
        }
        
        let config: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [
                [
                    "tag": "socks",
                    "port": socksPort,
                    "listen": "127.0.0.1",
                    "protocol": "socks",
                    "settings": ["udp": true]
                ]
            ],
            "outbounds": [
                [
                    "tag": "proxy",
                    "protocol": "vless",
                    "settings": [
                        "vnext": [
                            [
                                "address": host,
                                "port": port,
                                "users": [userDict]
                            ]
                        ]
                    ],
                    "streamSettings": streamSettings
                ],
                [
                    "tag": "direct",
                    "protocol": "freedom"
                ]
            ],
            "routing": [
                "domainStrategy": "AsIs",
                "rules": routingRules
            ]
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
