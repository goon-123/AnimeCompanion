import Foundation

public enum DeviceSyncLocation: String, Sendable {
    case automatic, folder
    /// Existing folder connections remain selected across this upgrade. An
    /// automatic connection never substitutes a local Documents directory.
    public static func restored(saved: String?, hasFolderBookmark: Bool) -> Self? {
        if saved == Self.automatic.rawValue { return .automatic }
        return hasFolderBookmark ? .folder : nil
    }
}
