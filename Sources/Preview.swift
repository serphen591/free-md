import Cocoa
import WebKit
import UniformTypeIdentifiers

final class AssetHandler: NSObject, WKURLSchemeHandler {
    var documentDirectory: URL?
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let root = documentDirectory?.resolvingSymlinksInPath(), let requestURL = urlSchemeTask.request.url else { urlSchemeTask.didFailWithError(AppError.message("未设置文档目录")); return }
        let relative = String(requestURL.path.dropFirst())
        let url = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        let allowed = ["png","jpg","jpeg","gif","webp","svg","bmp","heic","tiff"]
        guard url.path.hasPrefix(root.path + "/"), allowed.contains(url.pathExtension.lowercased()) else { urlSchemeTask.didFailWithError(AppError.message("不支持的预览资源")); return }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attrs[.size] as? Int ?? 0) <= 30_000_000 else { throw AppError.message("图片过大") }
            let data = try Data(contentsOf: url)
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            urlSchemeTask.didReceive(URLResponse(url: requestURL, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
            urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
final class PreviewView: WKWebView, WKNavigationDelegate, WKScriptMessageHandler {
    let assets: AssetHandler
    var ready = false
    var pending = ""
    var onLink: ((String) -> Void)?
    init() {
        assets = AssetHandler()
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(assets, forURLScheme: "mdasset")
        config.websiteDataStore = .nonPersistent()
        super.init(frame: .zero, configuration: config)
        navigationDelegate = self
        configuration.userContentController.add(self, name: "link")
        setValue(false, forKey: "drawsBackground")
        if let resource = Bundle.main.resourceURL {
            loadFileURL(resource.appendingPathComponent("preview.html"), allowingReadAccessTo: resource)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render(pending) }
    func render(_ text: String) {
        pending = text
        guard ready, let d = try? JSONSerialization.data(withJSONObject: [text]), let s = String(data: d, encoding: .utf8) else { return }
        evaluateJavaScript("window.renderMarkdown.apply(null, \(s))", completionHandler: nil)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let link = message.body as? String { onLink?(link) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url { onLink?(url.absoluteString) }
            decisionHandler(.cancel)
        } else if navigationAction.request.url?.isFileURL == true { decisionHandler(.allow) }
        else { decisionHandler(.cancel) }
    }
}
