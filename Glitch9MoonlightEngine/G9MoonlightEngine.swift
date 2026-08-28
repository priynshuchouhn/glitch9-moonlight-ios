import Foundation
import UIKit

public struct G9MoonlightConfiguration: Sendable {
    public let host: String
    public let port: UInt16
    public let application: String
    public let clientIdentity: Data
    public let serverCertificate: Data?

    public init(
        host: String,
        port: UInt16,
        application: String,
        clientIdentity: Data,
        serverCertificate: Data? = nil
    ) throws {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedApplication = application.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty, !normalizedHost.contains(where: { $0.isWhitespace }) else {
            throw G9MoonlightError.invalidConfiguration("host")
        }
        guard port > 0 else { throw G9MoonlightError.invalidConfiguration("port") }
        guard !normalizedApplication.isEmpty else {
            throw G9MoonlightError.invalidConfiguration("application")
        }
        guard !clientIdentity.isEmpty else {
            throw G9MoonlightError.invalidConfiguration("clientIdentity")
        }
        self.host = normalizedHost
        self.port = port
        self.application = normalizedApplication
        self.clientIdentity = clientIdentity
        self.serverCertificate = serverCertificate
    }
}

public enum G9MoonlightEvent: Sendable {
    case stageStarted(String)
    case stageCompleted(String)
    case streaming
    case stopped
    case failed(code: String)
}

public enum G9MoonlightError: Error, Equatable {
    case invalidConfiguration(String)
    case alreadyRunning
    case engineUnavailable
}

@MainActor
public protocol G9MoonlightEngine: AnyObject {
    var onEvent: (@Sendable (G9MoonlightEvent) -> Void)? { get set }
    func start(configuration: G9MoonlightConfiguration, renderIn view: UIView) throws
    func stop()
}
