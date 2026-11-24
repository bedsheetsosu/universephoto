import Foundation
import Network
import Security

public enum TafelNetwork {
    public static let serviceType = "_tafel._tcp"
    public static let pairingServiceType = "_tafelpair._tcp"
    public static let txtHostIDKey = "id"

    /// TCP + TLS 1.2 with a pre-shared key (TLS_PSK_WITH_AES_128_GCM_SHA256), the same scheme
    /// as Äbbl's "Building a custom peer-to-peer protocol" sample. Peers without the key cannot
    /// complete the handshake; all payload is encrypted and authenticated.
    /// Which of the three session connections (decides the QoS service class).
    public enum Channel: Sendable { case control, video, audio }

    /// Which network path a connection may use.
    public enum Link: @unchecked Sendable {
        /// Any path, including Äbbl peer-to-peer Wi-Fi (AWDL).
        case any
        /// Any path except AWDL. Keeping AWDL active makes the Wi-Fi radio hop channels
        /// periodically, which shows up as latency spikes on normal Wi-Fi.
        case noPeerToPeer
        /// Only a wired interface. With the iPad on a cable, iPadOS exposes a USB-Ethernet (NCM)
        /// link to the Mac; whether an app may use it is not documented, so callers fall back to `.any`.
        case wiredOnly
        /// Exactly this interface (keeps video/audio on the same path as the control connection).
        case pinned(NWInterface)
    }

    public static func parameters(psk: Data, identity: String, video: Bool) -> NWParameters {
        parameters(psk: psk, identity: identity, channel: video ? .video : .control)
    }

    public static func parameters(psk: Data, identity: String, channel: Channel, link: Link = .any) -> NWParameters {
        parameters(psks: [(psk, identity)], channel: channel, link: link)
    }

    /// Several keys, each with its own identity (a listener that accepts every paired iPad with
    /// that iPad's own key; the TLS layer picks the key by the identity the client sends).
    public static func parameters(psks: [(key: Data, identity: String)], channel: Channel, link: Link = .any) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        for (psk, identity) in psks {
            let pskData = psk.withUnsafeBytes { DispatchData(bytes: $0) }
            let idData = Data(identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
            sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, pskData as __DispatchData, idData as __DispatchData)
        }
        sec_protocol_options_append_tls_ciphersuite(
            tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.connectionTimeout = 8

        let params = NWParameters(tls: tls, tcp: tcp)
        switch link {
        case .any:
            // Allows Äbbl peer-to-peer Wi-Fi (AWDL) when both devices are not on the same network.
            params.includePeerToPeer = true
        case .noPeerToPeer:
            params.includePeerToPeer = false
        case .wiredOnly:
            params.requiredInterfaceType = .wiredEthernet
            params.includePeerToPeer = false
        case .pinned(let interface):
            params.requiredInterface = interface
            params.includePeerToPeer = true
        }
        switch channel {
        case .control: params.serviceClass = .responsiveData
        case .video: params.serviceClass = .interactiveVideo
        case .audio: params.serviceClass = .interactiveVoice
        }
        return params
    }
}

public extension NWConnection {
    /// Short human-readable name of the path in use ("USB-Kabel", "WLAN", …).
    var linkDescription: String {
        guard let path = currentPath else { return "–" }
        return TafelNetwork.describe(path)
    }
}

public extension TafelNetwork {
    static func describe(_ path: NWPath) -> String {
        guard let i = path.availableInterfaces.first else { return "–" }
        let kind: String
        switch i.type {
        case .wiredEthernet: kind = "USB-Kabel"
        case .wifi: kind = i.name.hasPrefix("awdl") || i.name.hasPrefix("llw") ? "Peer-to-Peer-WLAN" : "WLAN"
        case .loopback: kind = "Loopback"
        case .cellular: kind = "Mobilfunk"
        default:
            if i.name.hasPrefix("awdl") || i.name.hasPrefix("llw") { kind = "Peer-to-Peer-WLAN" }
            // iPad side of the USB link shows up as an "other" interface (en2 / anpi0).
            else if i.name.hasPrefix("en") || i.name.hasPrefix("anpi") { kind = "USB-Kabel" }
            else { kind = "Sonstige" }
        }
        return "\(kind) (\(i.name))"
    }
}

/// Length-prefixed frames over an `NWConnection`.
///
/// Thread-safety: callbacks run on `queue`. `send` may be called from any thread.
public final class FramedConnection: @unchecked Sendable {
    public let connection: NWConnection
    public let queue: DispatchQueue
    public var onFrame: ((Frame) -> Void)?
    public var onState: ((NWConnection.State) -> Void)?
    /// Called once when the connection is finished (failed, cancelled or closed by the peer).
    public var onClose: ((Error?) -> Void)?

    private let lock = NSLock()
    private var _pending = 0
    private var closed = false

    public init(_ connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    /// Bytes handed to the network stack but not yet processed. Used for frame dropping.
    public var pendingBytes: Int { lock.withLock { _pending } }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.onState?(state)
            switch state {
            case .failed(let e): self.finish(e)
            case .cancelled: self.finish(nil)
            default: break
            }
        }
        connection.start(queue: queue)
        receiveHeader()
    }

    public func send(_ type: MessageType, _ payload: Data) {
        let bytes = FrameCodec.encode(type, payload)
        lock.withLock { _pending += bytes.count }
        connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.lock.withLock { self._pending -= bytes.count }
            if let error { self.finish(error) }
        })
    }

    public func sendJSON<T: Encodable>(_ type: MessageType, _ value: T) {
        guard let d = try? JSONWire.encode(value) else { return }
        send(type, d)
    }

    public func cancel() {
        connection.cancel()
    }

    private func finish(_ error: Error?) {
        let first: Bool = lock.withLock {
            if closed { return false }
            closed = true
            return true
        }
        guard first else { return }
        connection.cancel()
        onClose?(error)
        onFrame = nil
        onState = nil
        onClose = nil
    }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: FrameCodec.headerSize, maximumLength: FrameCodec.headerSize) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error { self.finish(error); return }
            guard let data, data.count == FrameCodec.headerSize else {
                if isComplete { self.finish(nil) } else { self.receiveHeader() }
                return
            }
            do {
                let (t, n) = try FrameCodec.parseHeader(data)
                if n == 0 {
                    self.deliver(t, Data())
                    self.receiveHeader()
                } else {
                    self.receivePayload(type: t, length: n)
                }
            } catch {
                self.finish(error)
            }
        }
    }

    private func receivePayload(type: UInt8, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error { self.finish(error); return }
            guard let data, data.count == length else {
                self.finish(isComplete ? nil : WireError.truncated)
                return
            }
            self.deliver(type, data)
            self.receiveHeader()
        }
    }

    private func deliver(_ raw: UInt8, _ payload: Data) {
        // Unknown types are ignored for forward compatibility.
        guard let type = MessageType(rawValue: raw) else { return }
        onFrame?(Frame(type: type, payload: payload))
    }
}
