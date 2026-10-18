import SafariServices

/// Safari runs the JavaScript in the embedded extension. No native messaging,
/// shared credentials, or access to the user's anime library is needed.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        context.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
