import Cocoa
import WebKit

let args = CommandLine.arguments
let htmlPath = args[1]
let outDir = args[2]
let ids: [String] = args.count > 3 ? Array(args[3...]) : []
let pageWidth: CGFloat = 1760

final class Runner: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let window: NSWindow
    var pending: [String] = []

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 1200), configuration: config)
        window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: pageWidth, height: 1200), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.contentView = webView
        window.orderBack(nil)
        webView.navigationDelegate = self
        let url = URL(fileURLWithPath: htmlPath)
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.callAsyncJavaScript("await document.fonts.ready; await new Promise(r => setTimeout(r, 600)); return document.documentElement.scrollHeight", arguments: [:], in: nil, in: .page) { result in
            let height = (try? result.get()) as? Double ?? 3000
            let h = CGFloat(height)
            self.window.setContentSize(NSSize(width: pageWidth, height: h))
            self.webView.frame = NSRect(x: 0, y: 0, width: pageWidth, height: h)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.collect() }
        }
    }

    func collect() {
        let js = """
        const ids = \(ids.isEmpty ? "[...document.querySelectorAll('[data-shot]')].map(e => e.id)" : "\(ids)");
        return ids.map(id => { const r = document.getElementById(id).getBoundingClientRect(); return [id, r.left + scrollX, r.top + scrollY, r.width, r.height]; });
        """
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            guard case .success(let value) = result, let rows = value as? [[Any]] else {
                print("js error: \(result)"); exit(1)
            }
            self.shoot(rows: rows, index: 0)
        }
    }

    func shoot(rows: [[Any]], index: Int) {
        if index >= rows.count { exit(0) }
        let row = rows[index]
        let id = row[0] as! String
        let x = CGFloat((row[1] as! NSNumber).doubleValue)
        let y = CGFloat((row[2] as! NSNumber).doubleValue)
        let w = CGFloat((row[3] as! NSNumber).doubleValue)
        let h = CGFloat((row[4] as! NSNumber).doubleValue)
        let cfg = WKSnapshotConfiguration()
        cfg.rect = NSRect(x: x, y: y, width: w, height: h)
        cfg.snapshotWidth = NSNumber(value: Double(w * 1.5))
        cfg.afterScreenUpdates = true
        webView.takeSnapshot(with: cfg) { image, error in
            if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                let path = "\(outDir)/\(id).png"
                try? png.write(to: URL(fileURLWithPath: path))
                print("wrote \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
            } else {
                print("snapshot failed \(id): \(String(describing: error))")
            }
            self.shoot(rows: rows, index: index + 1)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let runner = Runner()
DispatchQueue.main.asyncAfter(deadline: .now() + 180) { print("timeout"); exit(2) }
app.run()
