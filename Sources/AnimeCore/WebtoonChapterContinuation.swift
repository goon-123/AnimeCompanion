import Foundation

/// Only an actual reading gesture/motion may advance a chapter. Image layout,
/// restored offsets, zooming and repeated delegate callbacks cannot skip ahead.
public struct WebtoonChapterContinuation: Sendable {
    private var chapter = ""
    private var interacted = false
    private var issued = false
    public init() {}
    public mutating func reset(chapter: String) { self.chapter = chapter; interacted = false; issued = false }
    public mutating func didScroll() { interacted = true }
    public mutating func claim(chapter: String, enabled: Bool, hasNext: Bool, atEnd: Bool,
        imagesComplete: Bool, allowed: Bool, zoomed: Bool) -> Bool {
        guard chapter == self.chapter, !chapter.isEmpty, !issued, interacted,
              enabled, hasNext, atEnd, imagesComplete, allowed, !zoomed else { return false }
        issued = true
        return true
    }
}
