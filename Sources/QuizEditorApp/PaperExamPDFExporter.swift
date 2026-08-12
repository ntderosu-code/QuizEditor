import AppKit
import WebKit

/// Renders paper-exam HTML to a paginated PDF, entirely offline.
///
/// The exam is built as print-styled HTML by `PaperExamBuilder` (Core, tested);
/// this class loads it into a web view hosted in an offscreen window and runs a
/// panel-less save-to-file `NSPrintOperation`, which honors the document's
/// `@media print` CSS and paginates properly (unlike `createPDF`, which
/// produces one long page). The web view must live in a window and the
/// operation must go through `runModal(for:)` — `run()` on a window-less
/// WKWebView never converges.
final class PaperExamPDFExporter: NSObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var destinationURL: URL?
    private var completion: ((Error?) -> Void)?
    /// Keeps the exporter alive for the duration of one async export.
    private var selfRetain: PaperExamPDFExporter?

    enum ExportError: LocalizedError {
        case loadFailed(underlying: Error?)
        case printFailed

        var errorDescription: String? {
            switch self {
            case .loadFailed(let underlying):
                "The exam page could not be prepared." + (underlying.map { " \($0.localizedDescription)" } ?? "")
            case .printFailed:
                "The PDF could not be written."
            }
        }
    }

    /// Loads `html` offscreen and writes a paginated PDF to `url`.
    /// Calls `completion` on the main thread with nil on success.
    func export(html: String, to url: URL, completion: @escaping (Error?) -> Void) {
        // US Letter; the offscreen window just gives WebKit a real host to
        // lay out and print from.
        let frame = NSRect(x: 0, y: 0, width: 612, height: 792)
        let webView = WKWebView(frame: frame)
        webView.navigationDelegate = self

        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.isReleasedWhenClosed = false

        self.window = window
        self.webView = webView
        self.destinationURL = url
        self.completion = completion
        self.selfRetain = self
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // One turn of the run loop lets layout and data-URI images settle
        // before pagination measures the content.
        DispatchQueue.main.async { [weak self] in
            self?.runPrintOperation(on: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: ExportError.loadFailed(underlying: error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: ExportError.loadFailed(underlying: error))
    }

    private func runPrintOperation(on webView: WKWebView) {
        guard let destinationURL, let window else {
            finish(with: ExportError.printFailed)
            return
        }

        let printInfo = NSPrintInfo()
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destinationURL
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        // The document's @page rule owns the margins; keep the printer's small
        // so they don't stack.
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // WKWebView's print view needs an explicit frame or pagination
        // produces zero pages.
        operation.view?.frame = NSRect(origin: .zero, size: printInfo.paperSize)

        operation.runModal(
            for: window,
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    @objc private func printOperationDidRun(_ printOperation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        finish(with: success ? nil : ExportError.printFailed)
    }

    private func finish(with error: Error?) {
        let completion = self.completion
        self.completion = nil
        // Tear down on the next run-loop turn: this can be reached from inside
        // the print operation's completion, and the offscreen window (never
        // ordered in) must not be closed while that machinery unwinds — just
        // dropping the references releases it.
        DispatchQueue.main.async {
            self.webView?.navigationDelegate = nil
            self.webView = nil
            self.window = nil
            self.destinationURL = nil
            self.selfRetain = nil
            completion?(error)
        }
    }
}
