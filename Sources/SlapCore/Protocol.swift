/// slapd sends these lines over the Unix socket:
///   "hello"          — right after connecting, the sensor is running
///   "impact 0.423"   — a slap with a strength of 0.423 g
public enum SlapProtocol {
    public static let socketPath = "/var/run/slapd.sock"
}
