import Cocoa

func runBounded(_ executable:String,_ arguments:[String],limit:Int=2_000_000) throws -> Data {
    let p=Process(); p.executableURL=URL(fileURLWithPath:executable); p.arguments=arguments
    let pipe=Pipe(); p.standardOutput=pipe; p.standardError=FileHandle.nullDevice
    try p.run(); var result=Data()
    while true {
        let data=pipe.fileHandleForReading.readData(ofLength:65536)
        if data.isEmpty { break }
        result.append(data)
        if result.count>limit { p.terminate(); pipe.fileHandleForReading.closeFile(); p.waitUntilExit(); throw AppError.message("压缩包展开内容超过安全大小限制。") }
    }
    p.waitUntilExit(); guard p.terminationStatus==0 else { throw AppError.message("无法读取压缩包，文件可能已损坏或加密。") }; return result
}
extension AppDelegate {
    func openArchive(_ url:URL) {
        do {
            let data=try runBounded("/usr/bin/unzip",["-Z1",url.path]); guard let listing=String(data:data,encoding:.utf8) else { throw AppError.message("压缩包文件名不是 UTF-8 编码。") }
            let entries=listing.components(separatedBy:"\n").filter{!$0.isEmpty}
            let safe=entries.filter { !$0.hasPrefix("/") && !$0.split(separator:"/").contains("..") && !$0.hasPrefix("__MACOSX/") }
            let markdown=safe.filter { ["md","markdown","txt"].contains(URL(fileURLWithPath:$0).pathExtension.lowercased()) }
            var selected=markdown.first
            if markdown.count>1 {
                let alert=NSAlert(); alert.messageText="从压缩包导入文档"; alert.informativeText="将创建独立副本，原压缩包保持不变。"
                let combo=NSPopUpButton(frame:NSRect(x:0,y:0,width:420,height:28)); combo.addItems(withTitles:markdown); alert.accessoryView=combo; alert.addButton(withTitle:"导入"); alert.addButton(withTitle:"取消")
                guard alert.runModal() == .alertFirstButtonReturn else { return }; selected=combo.titleOfSelectedItem
            }
            guard let member=selected else {
                let d=DocumentState(); d.title=url.lastPathComponent+" · 内容清单"; d.text="# "+url.lastPathComponent+"\n\n共 \(entries.count) 项；未找到 Markdown 或文本文件。\n\n```text\n"+entries.prefix(2000).joined(separator:"\n")+"\n```\n"; d.savedText=d.text; documents.append(d); activate(d.id); return
            }
            let content=try runBounded("/usr/bin/unzip",["-p",url.path,member],limit:20_000_000); _=try decodeText(content)
            let destination=support.appendingPathComponent("Imports").appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
            let imported=destination.appendingPathComponent(URL(fileURLWithPath:member).lastPathComponent)
            try content.write(to:imported,options:.atomic)
            let prefix=(member as NSString).deletingLastPathComponent
            let prefixPath=prefix.isEmpty ? "" : prefix+"/"
            var total=0
            for entry in safe.filter({ $0.hasPrefix(prefixPath) && ["png","jpg","jpeg","gif","svg","webp"].contains(URL(fileURLWithPath:$0).pathExtension.lowercased()) }).prefix(200) {
                let relative=String(entry.dropFirst(prefixPath.count)); let target=destination.appendingPathComponent(relative).standardizedFileURL
                guard target.path.hasPrefix(destination.path+"/") else { continue }
                if let bytes=try? runBounded("/usr/bin/unzip",["-p",url.path,entry],limit:10_000_000) {
                    total += bytes.count; if total>50_000_000 { break }
                    try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true); try bytes.write(to:target,options:.atomic)
                }
            }
            openURL(imported); statusLabel.stringValue="已导入本地副本 · 原压缩包保持不变 · 可用 ⇧⌘S 另存为"
        } catch { showError(error) }
    }
}
