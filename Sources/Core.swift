import Cocoa

let appName = "免费版md"
let appID = "app.freemd.local"
let fileTypes = ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "txt", "text", "json", "csv", "yaml", "yml", "xml", "log", "css", "js", "html", "taioactions"]

struct Clip: Codable {
    var id = UUID().uuidString
    var text: String
    var date = Date()
    var pinned = false
}
struct Draft: Codable {
    var id: String
    var path: String?
    var title: String
    var text: String
    var savedText: String
    var encoding: UInt
    var bom: Bool
    var originalData: Data?
}
final class DocumentState {
    var id = UUID().uuidString
    var url: URL?
    var title = "未命名"
    var text = ""
    var savedText = ""
    var encoding = String.Encoding.utf8
    var bom = false
    var originalData: Data?
    var selection = NSRange(location: 0, length: 0)
    var dirty: Bool { text != savedText || (url == nil && !text.isEmpty) }
    init() {}
    init(url: URL) throws {
        self.url = url
        title = url.lastPathComponent
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 20_000_000 else { throw AppError.message("文件超过 20 MB，请用专用大文件编辑器打开。") }
        let result = try decodeText(data)
        text = result.0; savedText = text; encoding = result.1; bom = result.2; originalData = data
    }
    init(draft: Draft) {
        id = draft.id; url = draft.path.map { URL(fileURLWithPath: $0) }; title = draft.title
        text = draft.text; savedText = draft.savedText; encoding = String.Encoding(rawValue: draft.encoding)
        bom = draft.bom; originalData = draft.originalData
    }
    var draft: Draft { Draft(id: id, path: url?.path, title: title, text: text, savedText: savedText, encoding: encoding.rawValue, bom: bom, originalData: originalData) }
    func encoded() throws -> Data {
        guard var data = text.data(using: encoding, allowLossyConversion: false) else { throw AppError.message("无法用原编码保存这些字符。请使用“另存为”保存为 UTF-8。") }
        if bom {
            if encoding == .utf8 { data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0) }
            else if encoding == .utf16LittleEndian { data.insert(contentsOf: [0xFF,0xFE],at:0) }
            else if encoding == .utf16BigEndian { data.insert(contentsOf: [0xFE,0xFF],at:0) }
        }
        return data
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
func decodeText(_ data: Data) throws -> (String, String.Encoding, Bool) {
    let bytes = [UInt8](data.prefix(4))
    if bytes.starts(with: [0xEF,0xBB,0xBF]), let s = String(data: data.dropFirst(3), encoding: .utf8) { return (s,.utf8,true) }
    if bytes.starts(with: [0xFF,0xFE]) {
        if let s=String(data:data.dropFirst(2),encoding:.utf16LittleEndian) { return (s,.utf16LittleEndian,true) }
    }
    if bytes.starts(with: [0xFE,0xFF]) {
        if let s=String(data:data.dropFirst(2),encoding:.utf16BigEndian) { return (s,.utf16BigEndian,true) }
    }
    guard !data.prefix(8192).contains(0) else { throw AppError.message("该文件是二进制文件，无法作为文本编辑。原文件未被修改。") }
    if let s = String(data: data, encoding: .utf8) { return (s,.utf8,false) }
    let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    if let s = String(data: data, encoding: gb) { return (s,gb,false) }
    throw AppError.message("无法识别文本编码。请先将文件转换为 UTF-8。")
}
struct Heading { let title: String; let level: Int; let range: NSRange }
func headings(in text: String) -> [Heading] {
    var result: [Heading] = []; var offset = 0; var fence: Character?
    for line in text.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            let c = trimmed.first!
            if fence == nil { fence = c } else if fence == c { fence = nil }
        } else if fence == nil, let match = line.range(of: "^ {0,3}#{1,6} +", options: .regularExpression) {
            let prefix = String(line[..<match.upperBound])
            let title = String(line[match.upperBound...]).replacingOccurrences(of: " +#+ *$", with: "", options: .regularExpression)
            result.append(Heading(title: title, level: prefix.filter { $0 == "#" }.count, range: NSRange(location: offset, length: (line as NSString).length)))
        }
        offset += (line as NSString).length + 1
    }
    return result
}
struct TextAction {
    let title: String; let subtitle: String; let icon: String; let transform: (String) throws -> String
}
let textActions: [TextAction] = [
    TextAction(title: "去除首尾空白", subtitle: "清理每一行多余的空格", icon: "wand.and.stars", transform: { $0.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n") }),
    TextAction(title: "删除重复行", subtitle: "保留第一次出现的内容", icon: "line.3.horizontal.decrease", transform: { var seen = Set<String>(); return $0.components(separatedBy: "\n").filter { seen.insert($0).inserted }.joined(separator: "\n") }),
    TextAction(title: "按行排序", subtitle: "按自然顺序排列文本", icon: "arrow.up.arrow.down", transform: { $0.components(separatedBy: "\n").sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n") }),
    TextAction(title: "移除空行", subtitle: "删除只有空白的行", icon: "line.3.horizontal", transform: { $0.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n") }),
    TextAction(title: "转为大写", subtitle: "UPPERCASE", icon: "textformat.abc", transform: { $0.uppercased() }),
    TextAction(title: "转为小写", subtitle: "lowercase", icon: "textformat", transform: { $0.lowercased() }),
    TextAction(title: "格式化 JSON", subtitle: "校验并缩进 JSON 文本", icon: "curlybraces", transform: { let obj = try JSONSerialization.jsonObject(with: Data($0.utf8), options: [.fragmentsAllowed]); return String(data: try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted,.sortedKeys,.fragmentsAllowed,.withoutEscapingSlashes]), encoding: .utf8)! }),
    TextAction(title: "添加无序列表", subtitle: "为每一行添加 Markdown 列表符号", icon: "list.bullet", transform: { $0.components(separatedBy: "\n").map { "- " + $0 }.joined(separator: "\n") }),
    TextAction(title: "添加任务列表", subtitle: "把文本变成可勾选的清单", icon: "checklist", transform: { $0.components(separatedBy: "\n").map { "- [ ] " + $0 }.joined(separator: "\n") }),
    TextAction(title: "URL 编码", subtitle: "编码 URL 参数中的特殊字符", icon: "link", transform: { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0 }),
    TextAction(title: "URL 解码", subtitle: "还原编码后的 URL 文本", icon: "link", transform: { guard let s = $0.removingPercentEncoding else { throw AppError.message("URL 编码无效。") }; return s }),
    TextAction(title: "Base64 编码", subtitle: "将 UTF-8 文本编码为 Base64", icon: "chevron.left.forwardslash.chevron.right", transform: { Data($0.utf8).base64EncodedString() }),
    TextAction(title: "Base64 解码", subtitle: "还原 Base64 编码的 UTF-8 文本", icon: "chevron.left.forwardslash.chevron.right", transform: { guard let d = Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)), let s = String(data: d, encoding: .utf8) else { throw AppError.message("不是有效的 UTF-8 Base64 文本。") }; return s })
]
let welcome = """
# 留一点空间，给想法。

欢迎使用 **免费版md**，你的本地 Markdown 工作台。

从左上角打开一个文件或文件夹，或者按 `⌘N` 开始一篇新文档。

## 写作，从这里开始

- **本地文件**：直接读写你的 Markdown 和文本文件
- **实时预览**：边写边看，支持表格、代码、数学公式和流程图
- **文本片段**：手动收藏剪贴板里的灵感
- **文本动作**：一键去重、排序、格式化 JSON

> 文件属于你。无需账户，无需订阅，断网也能写。

## 今天的小计划

- [x] 打开免费版md
- [ ] 写下一件值得记录的小事
- [ ] 按 ⌘S 保存到自己的文件夹

## 试试 Markdown

| 功能 | 快捷键 |
| :--- | :--- |
| 打开文件 | ⌘O |
| 保存文件 | ⌘S |
| 查找 / 替换 | ⌘F / ⌥⌘F |
| 加粗 / 斜体 | ⌘B / ⌘I |

```javascript
const idea = "把想法写下来";
console.log(idea);
```

$$
E = mc^2
$$

```mermaid
graph LR
  A[灵感] --> B[记录]
  B --> C[整理]
  C --> D[分享]
```
"""
