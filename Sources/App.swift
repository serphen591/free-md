import Cocoa
import WebKit
import UniformTypeIdentifiers

let ink = NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.30, alpha: 1)
func label(_ s: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let l = NSTextField(labelWithString: s); l.font = .systemFont(ofSize: size, weight: weight); l.textColor = color; l.lineBreakMode = .byTruncatingTail; return l
}
func button(_ title: String, _ symbol: String, _ action: Selector, target: AnyObject) -> NSButton {
    let b = NSButton(title: title, target: target, action: action)
    b.bezelStyle = .texturedRounded
    if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) { b.image = image; b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading }
    b.toolTip = title; return b
}
final class PanelView: NSView {
    let fill: NSColor
    init(_ color: NSColor) { fill = color; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { fill.setFill(); dirtyRect.fill() }
}
struct SidebarRow { var title: String; var detail: String; var icon: String; var key: String; var url: URL? }
final class DocumentSidebarCell: NSTableCellView {
    let closeButton = NSButton()
    var onClose: (() -> Void)?
    private var hoverTracking: NSTrackingArea?

    init(title: String, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(frame: .zero)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭文档")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "关闭“\(title)”"
        closeButton.setAccessibilityLabel("关闭“\(title)”")
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = hoverTracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
        refreshHover()
    }
    override func layout() { super.layout(); refreshHover() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.refreshHover() }
    }
    private func refreshHover() {
        guard let window = window else { closeButton.isHidden = true; return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        closeButton.isHidden = bounds.isEmpty || !NSMouseInRect(point, bounds, isFlipped)
    }
    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }
    @objc private func closeClicked() { onClose?() }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var window: NSWindow!
    var documents: [DocumentState] = []
    var active: DocumentState? { documents.first { $0.id == activeID } }
    var activeID = ""
    var editor = NSTextView()
    var editorScroll = NSScrollView()
    let preview = PreviewView()
    let contentSplit = NSSplitView()
    let mainSplit = NSSplitView()
    let table = NSTableView()
    let outlineTable = NSTableView()
    let search = NSSearchField()
    let modeControl = NSSegmentedControl(labels: ["文件", "片段", "动作"], trackingMode: .selectOne, target: nil, action: nil)
    let viewControl = NSSegmentedControl(labels: ["编辑", "双栏", "预览"], trackingMode: .selectOne, target: nil, action: nil)
    let titleLabel = label("未命名", size: 14, weight: .semibold)
    let pathLabel = label("本地 Markdown 工作台", size: 11, color: .secondaryLabelColor)
    let statusLabel = label("准备就绪", size: 11, color: .secondaryLabelColor)
    let folderLabel = label("工作空间", size: 11, weight: .semibold, color: .secondaryLabelColor)
    let sidebarFooter = label("内容仅保存在这台 Mac", size: 10, color: .tertiaryLabelColor)
    var rows: [SidebarRow] = []
    var currentHeadings: [Heading] = []
    var folderURL: URL?
    var folderFiles: [URL] = []
    var clips: [Clip] = []
    var changing = false
    var loadedState = false
    var debounce: Timer?
    var selectedClip: String?
    var outlineVisible = true
    var outlinePane: NSView!
    var fontSize: CGFloat = 15
    var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(appName) }
    var mode: Int { modeControl.selectedSegment }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        setupMenu(); setupWindow(); loadState()
        if documents.isEmpty { let doc = DocumentState(); doc.title = "欢迎使用"; doc.text = welcome; doc.savedText = welcome; documents.append(doc) }
        if active == nil { activeID = documents[0].id }
        activate(activeID)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.arguments.contains("--self-test") { runSelfTest() }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if window == nil { setupMenu(); setupWindow(); loadState() }
        for f in filenames { openURL(URL(fileURLWithPath: f)) }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { persist(); return confirmAll() ? .terminateNow : .terminateCancel }
    func applicationWillTerminate(_ notification: Notification) { persist() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { persist(); if confirmAll() { sender.orderOut(nil) }; return false }
    func windowDidBecomeKey(_ notification: Notification) { checkExternalChange() }

    func setupMenu() {
        let root = NSMenu()
        func menu(_ title: String) -> NSMenu { let item = NSMenuItem(); item.title = title; let m = NSMenu(title: title); item.submenu = m; root.addItem(item); return m }
        func add(_ m: NSMenu, _ title: String, _ sel: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command], _ target: AnyObject? = nil) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.keyEquivalentModifierMask = mods; i.target = target; m.addItem(i)
        }
        let app = menu(appName)
        add(app,"关于免费版md",#selector(about),"",[],self); app.addItem(.separator())
        add(app,"隐藏免费版md",#selector(NSApplication.hide(_:)),"h")
        add(app,"退出免费版md",#selector(NSApplication.terminate(_:)),"q")
        let file = menu("文件")
        add(file,"新建文档",#selector(newDocument),"n",[.command],self)
        add(file,"打开文件…",#selector(openFile),"o",[.command],self)
        add(file,"打开文件夹…",#selector(openFolder),"o",[.command,.shift],self)
        add(file,"刷新文件列表",#selector(refreshFolder),"r",[.command,.shift],self)
        file.addItem(.separator())
        add(file,"保存",#selector(save),"s",[.command],self)
        add(file,"另存为…",#selector(saveAs),"s",[.command,.shift],self)
        add(file,"关闭当前文档",#selector(closeDocument),"w",[.command],self)
        file.addItem(.separator())
        add(file,"导出 HTML…",#selector(exportHTML),"e",[.command,.shift],self)
        add(file,"导出 PDF…",#selector(exportPDF),"p",[.command,.shift],self)
        add(file,"在访达中显示",#selector(revealFile),"",[],self)
        let edit = menu("编辑")
        add(edit,"撤销",Selector(("undo:")),"z"); add(edit,"重做",Selector(("redo:")),"z",[.command,.shift]); edit.addItem(.separator())
        add(edit,"剪切",#selector(NSText.cut(_:)),"x"); add(edit,"复制",#selector(NSText.copy(_:)),"c"); add(edit,"粘贴",#selector(NSText.paste(_:)),"v"); add(edit,"全选",#selector(NSText.selectAll(_:)),"a")
        edit.addItem(.separator()); add(edit,"查找…",#selector(findText),"f",[.command],self); add(edit,"查找并替换…",#selector(replaceText),"f",[.command,.option],self)
        let format = menu("格式")
        add(format,"加粗",#selector(bold),"b",[.command],self); add(format,"斜体",#selector(italic),"i",[.command],self)
        add(format,"插入链接",#selector(insertLink),"k",[.command],self); add(format,"插入代码块",#selector(insertCode),"k",[.command,.shift],self)
        add(format,"插入标题",#selector(insertHeading),"1",[.command],self); add(format,"插入任务",#selector(insertTask),"l",[.command,.shift],self)
        add(format,"插入当前日期",#selector(insertDate),"d",[.command,.shift],self)
        let view = menu("显示")
        add(view,"切换大纲",#selector(toggleOutline),"b",[.command,.shift],self)
        add(view,"放大字体",#selector(zoomIn),"+",[.command],self); add(view,"缩小字体",#selector(zoomOut),"-",[.command],self)
        let actions = menu("文本动作")
        for (idx,a) in textActions.enumerated() { let item = NSMenuItem(title:a.title, action:#selector(actionMenu(_:)),keyEquivalent:""); item.target=self; item.tag=idx; actions.addItem(item) }
        actions.addItem(.separator()); add(actions,"正则查找替换…",#selector(regexReplace),"",[],self)
        let snippets = menu("片段")
        add(snippets,"收藏剪贴板文本",#selector(captureClipboard),"v",[.command,.shift],self)
        add(snippets,"收藏当前选区",#selector(captureSelection),"c",[.command,.shift],self)
        add(snippets,"打开本地数据目录",#selector(showSupport),"",[],self)
        let help = menu("帮助"); add(help,"使用指南",#selector(showGuide),"",[],self)
        NSApp.mainMenu = root
    }

    func setupWindow() {
        guard window == nil else { return }
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:1280,height:840),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = appName; window.minSize = NSSize(width:900,height:600); window.center(); window.delegate=self
        window.setFrameAutosaveName("FreeMDWindow"); window.titlebarAppearsTransparent=true; window.isReleasedWhenClosed=false
        let root = NSView(); window.contentView = root
        mainSplit.isVertical = true; mainSplit.dividerStyle = .thin; mainSplit.translatesAutoresizingMaskIntoConstraints=false
        root.addSubview(mainSplit)
        NSLayoutConstraint.activate([mainSplit.topAnchor.constraint(equalTo:root.topAnchor),mainSplit.bottomAnchor.constraint(equalTo:root.bottomAnchor),mainSplit.leadingAnchor.constraint(equalTo:root.leadingAnchor),mainSplit.trailingAnchor.constraint(equalTo:root.trailingAnchor)])
        let side = NSVisualEffectView(); side.material = .sidebar; side.blendingMode = .behindWindow; mainSplit.addArrangedSubview(side)
        side.widthAnchor.constraint(greaterThanOrEqualToConstant:210).isActive=true
        side.widthAnchor.constraint(lessThanOrEqualToConstant:340).isActive=true
        let brand = label(appName,size:20,weight:.bold,color:ink)
        let note = label("让文字，回到自己手中。",size:11,color:.secondaryLabelColor)
        let logo = NSImageView(); logo.image=NSImage(named:NSImage.applicationIconName); logo.setContentHuggingPriority(.required,for:.horizontal)
        logo.widthAnchor.constraint(equalToConstant:42).isActive=true; logo.heightAnchor.constraint(equalToConstant:42).isActive=true
        let brandText=NSStackView(views:[brand,note]); brandText.orientation = .vertical; brandText.alignment = .leading; brandText.spacing=4
        let brandRow=NSStackView(views:[logo,brandText]); brandRow.spacing=10
        modeControl.selectedSegment=0; search.stringValue=""; search.placeholderString="搜索文件"; modeControl.target=self; modeControl.action=#selector(modeChanged)
        modeControl.segmentStyle = .rounded
        search.placeholderString="搜索文件"; search.delegate=self; search.sendsSearchStringImmediately=true
        let open=button("打开", "folder", #selector(openFolder), target:self)
        let new=button("新建", "square.and.pencil", #selector(newDocument), target:self)
        let buttons=NSStackView(views:[open,new]); buttons.distribution = .fillEqually; buttons.spacing=8
        let top=NSStackView(views:[brandRow,modeControl,search,buttons,folderLabel]); top.orientation = .vertical; top.alignment = .leading; top.spacing=17; top.translatesAutoresizingMaskIntoConstraints=false; side.addSubview(top)
        for v in [modeControl,search,buttons] { v.widthAnchor.constraint(equalTo:top.widthAnchor).isActive=true }
        NSLayoutConstraint.activate([top.topAnchor.constraint(equalTo:side.topAnchor,constant:24),top.leadingAnchor.constraint(equalTo:side.leadingAnchor,constant:18),top.trailingAnchor.constraint(equalTo:side.trailingAnchor,constant:-18)])
        let scroll=NSScrollView(); scroll.hasVerticalScroller=true; scroll.drawsBackground=false; scroll.documentView=table; scroll.translatesAutoresizingMaskIntoConstraints=false; side.addSubview(scroll)
        let col=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("name")); table.addTableColumn(col); table.headerView=nil; table.rowHeight=53; table.intercellSpacing=NSSize(width:0,height:3); table.backgroundColor = .clear; table.style = .sourceList; table.delegate=self; table.dataSource=self; table.allowsEmptySelection=true
        sidebarFooter.translatesAutoresizingMaskIntoConstraints=false; side.addSubview(sidebarFooter)
        let clipButton=button("收藏剪贴板", "plus.rectangle.on.rectangle", #selector(captureClipboard), target:self); clipButton.translatesAutoresizingMaskIntoConstraints=false; side.addSubview(clipButton)
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo:top.bottomAnchor,constant:10),scroll.leadingAnchor.constraint(equalTo:side.leadingAnchor,constant:8),scroll.trailingAnchor.constraint(equalTo:side.trailingAnchor,constant:-8),scroll.bottomAnchor.constraint(equalTo:clipButton.topAnchor,constant:-12),clipButton.leadingAnchor.constraint(equalTo:side.leadingAnchor,constant:18),clipButton.trailingAnchor.constraint(equalTo:side.trailingAnchor,constant:-18),clipButton.bottomAnchor.constraint(equalTo:sidebarFooter.topAnchor,constant:-12),sidebarFooter.centerXAnchor.constraint(equalTo:side.centerXAnchor),sidebarFooter.bottomAnchor.constraint(equalTo:side.bottomAnchor,constant:-15)])
        let area=NSView(); mainSplit.addArrangedSubview(area)
        let header=NSView(); header.translatesAutoresizingMaskIntoConstraints=false; area.addSubview(header)
        let names=NSStackView(views:[titleLabel,pathLabel]); names.orientation = .vertical; names.alignment = .leading; names.spacing=4
        viewControl.selectedSegment=1; viewControl.target=self; viewControl.action=#selector(viewModeChanged); viewControl.segmentStyle = .rounded
        let saveButton=button("保存", "square.and.arrow.down", #selector(save), target:self)
        let outlineButton=button("", "list.bullet.indent", #selector(toggleOutline), target:self); outlineButton.toolTip="显示或隐藏大纲"
        let stack=NSStackView(views:[names,viewControl,outlineButton,saveButton]); stack.spacing=14; stack.translatesAutoresizingMaskIntoConstraints=false; header.addSubview(stack)
        names.setContentHuggingPriority(.defaultLow,for:.horizontal); names.widthAnchor.constraint(greaterThanOrEqualToConstant:100).isActive=true
        NSLayoutConstraint.activate([header.topAnchor.constraint(equalTo:area.topAnchor),header.leadingAnchor.constraint(equalTo:area.leadingAnchor),header.trailingAnchor.constraint(equalTo:area.trailingAnchor),header.heightAnchor.constraint(equalToConstant:76),stack.leadingAnchor.constraint(equalTo:header.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:header.trailingAnchor,constant:-22),stack.centerYAnchor.constraint(equalTo:header.centerYAnchor)])
        let formats=NSStackView(); formats.spacing=5; formats.translatesAutoresizingMaskIntoConstraints=false; area.addSubview(formats)
        let fmt:[(String,String,Selector)] = [("H", "", #selector(insertHeading)),("", "bold", #selector(bold)),("", "italic", #selector(italic)),("", "link", #selector(insertLink)),("", "chevron.left.forwardslash.chevron.right", #selector(insertCode)),("", "checklist", #selector(insertTask)),("", "calendar", #selector(insertDate))]
        for (title,symbol,sel) in fmt { let b=button(title,symbol,sel,target:self); b.bezelStyle = .inline; b.widthAnchor.constraint(equalToConstant:32).isActive=true; formats.addArrangedSubview(b) }
        let tip=label("MARKDOWN",size:10,weight:.medium,color:.tertiaryLabelColor); formats.addArrangedSubview(tip)
        NSLayoutConstraint.activate([formats.topAnchor.constraint(equalTo:header.bottomAnchor,constant:2),formats.leadingAnchor.constraint(equalTo:area.leadingAnchor,constant:22),formats.heightAnchor.constraint(equalToConstant:30)])
        contentSplit.isVertical=true; contentSplit.dividerStyle = .thin; contentSplit.translatesAutoresizingMaskIntoConstraints=false; area.addSubview(contentSplit)
        editorScroll.hasVerticalScroller=true; editorScroll.hasHorizontalScroller=false; editorScroll.autohidesScrollers=true
        editorScroll.documentView=editor; editorScroll.drawsBackground=true; editorScroll.backgroundColor = .textBackgroundColor
        editor.isRichText=false; editor.allowsUndo=true; editor.usesFindBar=true; editor.isIncrementalSearchingEnabled=true; editor.isAutomaticQuoteSubstitutionEnabled=false; editor.isAutomaticDashSubstitutionEnabled=false; editor.isAutomaticTextReplacementEnabled=false; editor.isAutomaticSpellingCorrectionEnabled=false
        editor.isVerticallyResizable=true; editor.isHorizontallyResizable=false; editor.autoresizingMask = [.width]; editor.minSize=NSSize(width:0,height:0); editor.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView=true; editor.textContainer?.containerSize=NSSize(width:400,height:CGFloat.greatestFiniteMagnitude); editor.textContainerInset=NSSize(width:26,height:25)
        editor.font = .monospacedSystemFont(ofSize:fontSize,weight:.regular); editor.textColor = .labelColor; editor.insertionPointColor=ink; editor.delegate=self
        let para=NSMutableParagraphStyle(); para.lineSpacing=6; editor.defaultParagraphStyle=para; editor.typingAttributes=[.font:editor.font!,.foregroundColor:NSColor.labelColor,.paragraphStyle:para]
        contentSplit.addArrangedSubview(editorScroll); contentSplit.addArrangedSubview(preview)
        preview.onLink = { [weak self] link in self?.followLink(link) }
        outlinePane=NSView(); contentSplit.addArrangedSubview(outlinePane)
        outlinePane.widthAnchor.constraint(greaterThanOrEqualToConstant:130).isActive=true; outlinePane.widthAnchor.constraint(lessThanOrEqualToConstant:210).isActive=true
        let ol=label("文档大纲",size:11,weight:.semibold,color:.secondaryLabelColor); ol.translatesAutoresizingMaskIntoConstraints=false; outlinePane.addSubview(ol)
        let os=NSScrollView(); os.documentView=outlineTable; os.hasVerticalScroller=true; os.drawsBackground=false; os.translatesAutoresizingMaskIntoConstraints=false; outlinePane.addSubview(os)
        outlineTable.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("heading"))); outlineTable.headerView=nil; outlineTable.rowHeight=32; outlineTable.delegate=self; outlineTable.dataSource=self; outlineTable.backgroundColor = .clear; outlineTable.selectionHighlightStyle = .regular
        NSLayoutConstraint.activate([ol.topAnchor.constraint(equalTo:outlinePane.topAnchor,constant:22),ol.leadingAnchor.constraint(equalTo:outlinePane.leadingAnchor,constant:14),os.topAnchor.constraint(equalTo:ol.bottomAnchor,constant:14),os.leadingAnchor.constraint(equalTo:outlinePane.leadingAnchor,constant:6),os.trailingAnchor.constraint(equalTo:outlinePane.trailingAnchor,constant:-6),os.bottomAnchor.constraint(equalTo:outlinePane.bottomAnchor)])
        statusLabel.translatesAutoresizingMaskIntoConstraints=false; area.addSubview(statusLabel)
        NSLayoutConstraint.activate([contentSplit.topAnchor.constraint(equalTo:formats.bottomAnchor,constant:8),contentSplit.leadingAnchor.constraint(equalTo:area.leadingAnchor),contentSplit.trailingAnchor.constraint(equalTo:area.trailingAnchor),contentSplit.bottomAnchor.constraint(equalTo:area.bottomAnchor,constant:-30),statusLabel.leadingAnchor.constraint(equalTo:area.leadingAnchor,constant:24),statusLabel.centerYAnchor.constraint(equalTo:area.bottomAnchor,constant:-15)])
        mainSplit.setPosition(250,ofDividerAt:0)
        DispatchQueue.main.async { self.mainSplit.setPosition(250,ofDividerAt:0); self.contentSplit.setPosition(430,ofDividerAt:0); self.contentSplit.setPosition(820,ofDividerAt:1) }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === table ? rows.count : currentHeadings.count }
    func tableView(_ tv: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tv === outlineTable {
            guard row < currentHeadings.count else { return nil }
            let h=currentHeadings[row]; let l=label(String(repeating:"  ",count:max(0,h.level-1))+h.title,size:12,weight:h.level==1 ? .semibold : .regular,color:h.level==1 ? .labelColor : .secondaryLabelColor); l.toolTip=h.title; return l
        }
        guard row < rows.count else { return nil }; let r=rows[row]
        let closable = mode == 0 && documents.contains(where: { $0.id == r.key })
        let cell: NSTableCellView = closable
            ? DocumentSidebarCell(title: r.title) { [weak self] in self?.closeDocumentWithID(r.key) }
            : NSTableCellView()
        let image=NSImageView(); image.image=NSImage(systemSymbolName:r.icon,accessibilityDescription:nil); image.contentTintColor=ink; image.translatesAutoresizingMaskIntoConstraints=false
        let title=label(r.title,size:13,weight:.medium); let detail=label(r.detail,size:10,color:.secondaryLabelColor)
        let text=NSStackView(views:[title,detail]); text.orientation = .vertical; text.alignment = .leading; text.spacing=4; text.translatesAutoresizingMaskIntoConstraints=false
        cell.addSubview(image); cell.addSubview(text); cell.toolTip=r.url?.path ?? r.detail
        NSLayoutConstraint.activate([image.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:8),image.centerYAnchor.constraint(equalTo:cell.centerYAnchor),image.widthAnchor.constraint(equalToConstant:18),image.heightAnchor.constraint(equalToConstant:20),text.leadingAnchor.constraint(equalTo:image.trailingAnchor,constant:10),text.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:closable ? -32 : -8),text.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !changing, let tv=notification.object as? NSTableView else { return }
        if tv === outlineTable {
            guard currentHeadings.indices.contains(tv.selectedRow) else { return }
            let h=currentHeadings[tv.selectedRow]; editor.setSelectedRange(h.range); editor.scrollRangeToVisible(h.range)
            preview.evaluateJavaScript("window.scrollToHeading(\(tv.selectedRow))",completionHandler:nil); return
        }
        guard rows.indices.contains(tv.selectedRow) else { return }; let row=rows[tv.selectedRow]
        if mode==0 { if let url=row.url { openURL(url) } else { activate(row.key) } }
        else if mode==1 { showClip(row.key) }
        else if let i=Int(row.key) { runAction(i) }
    }
    func controlTextDidChange(_ obj: Notification) { reloadRows() }
    func reloadRows() {
        let q=search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        var output:[SidebarRow]=[]
        switch mode {
        case 1:
            folderLabel.stringValue="\(clips.count) 条收藏 · 手动添加"
            for c in clips.sorted(by:{ $0.pinned != $1.pinned ? $0.pinned : $0.date > $1.date }) {
                let name=c.text.components(separatedBy:.newlines).first(where:{ !$0.isEmpty }) ?? "空片段"
                output.append(SidebarRow(title:name,detail:"\(c.text.count) 字符 · \(c.date.formatted(date:.abbreviated,time:.omitted))",icon:c.pinned ? "pin.fill" : "quote.bubble",key:c.id))
            }
        case 2:
            folderLabel.stringValue="选区优先 · 无选区时处理全文"
            output=textActions.enumerated().map { SidebarRow(title:$0.element.title,detail:$0.element.subtitle,icon:$0.element.icon,key:String($0.offset)) }
        default:
            folderLabel.stringValue=folderURL?.lastPathComponent ?? "已打开的文档"
            let opened=Set(documents.compactMap { $0.url?.standardizedFileURL.path })
            output=documents.map { SidebarRow(title:($0.dirty ? "● " : "")+$0.title,detail:$0.url?.deletingLastPathComponent().lastPathComponent ?? "未保存到文件",icon:$0.id==activeID ? "doc.text.fill" : "doc.text",key:$0.id) }
            output += folderFiles.filter { !opened.contains($0.standardizedFileURL.path) }.map { SidebarRow(title:$0.lastPathComponent,detail:$0.deletingLastPathComponent().lastPathComponent,icon:"doc.text",key:$0.path,url:$0) }
        }
        if !q.isEmpty { output=output.filter { row in row.title.localizedCaseInsensitiveContains(q) || row.detail.localizedCaseInsensitiveContains(q) || (mode==1 && (clips.first { $0.id==row.key }?.text.localizedCaseInsensitiveContains(q) ?? false)) } }
        rows=output; changing=true; table.reloadData()
        if mode==0, let idx=rows.firstIndex(where:{$0.key==activeID}) { table.selectRowIndexes(IndexSet(integer:idx),byExtendingSelection:false) }
        changing=false
    }
    @objc func modeChanged() { search.stringValue=""; search.placeholderString=["搜索文件","搜索片段","搜索动作"][mode]; reloadRows() }
    func activate(_ id: String) {
        active?.selection=editor.selectedRange(); activeID=id
        guard let doc=active else { return }
        changing=true; editor.string=doc.text; editor.undoManager?.removeAllActions(); editor.setSelectedRange(NSRange(location:min(doc.selection.location,(doc.text as NSString).length),length:0)); changing=false
        preview.assets.documentDirectory=doc.url?.deletingLastPathComponent(); refreshDocument(); reloadRows(); window.makeFirstResponder(editor); persist()
    }
    func refreshDocument() {
        guard let doc=active else { return }
        titleLabel.stringValue=doc.title; pathLabel.stringValue=doc.url?.path ?? "未保存 · ⌘S 保存到本地"
        window.title="\(doc.title) — \(appName)"; window.isDocumentEdited=doc.dirty; window.representedURL=doc.url
        let line=(doc.text as NSString).substring(to:min(editor.selectedRange().location,(doc.text as NSString).length)).components(separatedBy:"\n").count
        statusLabel.stringValue="\(doc.text.count) 字符    \(doc.text.components(separatedBy:"\n").count) 行    第 \(line) 行    ·    \(doc.dirty ? "有未保存的修改 · 草稿已在本机备份" : "已保存")    ·    \(doc.encoding == .utf8 ? "UTF-8" : String.localizedName(of:doc.encoding))"
        currentHeadings=headings(in:doc.text); outlineTable.reloadData(); preview.render(doc.text); highlight()
    }
    func textDidChange(_ notification: Notification) {
        guard !changing, let doc=active else { return }; doc.text=editor.string
        window.isDocumentEdited=doc.dirty
        debounce?.invalidate(); debounce=Timer.scheduledTimer(withTimeInterval:0.30,repeats:false) { [weak self] _ in self?.refreshDocument(); self?.reloadRows(); self?.persist() }
    }
    func textViewDidChangeSelection(_ notification: Notification) { if !changing { active?.selection=editor.selectedRange() } }
    func highlight() {
        guard let lm=editor.layoutManager else { return }; let s=editor.string as NSString; let all=NSRange(location:0,length:s.length)
        lm.removeTemporaryAttribute(.foregroundColor,forCharacterRange:all); lm.removeTemporaryAttribute(.font,forCharacterRange:all)
        guard s.length < 200_000 else { return }
        let rules:[(String,NSColor)] = [("(?m)^#{1,6} .*$",ink),("(?m)^>.*$",.secondaryLabelColor),("`[^`\n]+`",.systemOrange),("\\*\\*[^*]+\\*\\*",ink),("\\[[^\\]]*\\]\\([^)]*\\)",.systemBlue),("(?m)^\\s*[-*+] ",.systemOrange),("(?s)```.*?```",.secondaryLabelColor)]
        for (pattern,color) in rules { if let re=try? NSRegularExpression(pattern:pattern) { for m in re.matches(in:editor.string,range:all) { lm.addTemporaryAttribute(.foregroundColor,value:color,forCharacterRange:m.range) } } }
    }
    @objc func newDocument() { let d=DocumentState(); documents.append(d); modeControl.selectedSegment=0; search.stringValue=""; search.placeholderString="搜索文件"; activate(d.id) }
    @objc func openFile() { let p=NSOpenPanel(); p.canChooseFiles=true; p.canChooseDirectories=false; p.allowsMultipleSelection=true; if p.runModal() == .OK { p.urls.forEach(openURL) } }
    @objc func openFolder() { let p=NSOpenPanel(); p.canChooseFiles=false; p.canChooseDirectories=true; p.prompt="打开文件夹"; if p.runModal() == .OK, let url=p.url { folderURL=url; refreshFolder(); modeControl.selectedSegment=0; search.stringValue=""; search.placeholderString="搜索文件"; modeChanged(); persist() } }
    @objc func refreshFolder() {
        guard let root=folderURL else { return }; var found:[URL]=[]
        if let e=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) {
            for case let url as URL in e {
                if ["node_modules",".git","build","dist","vendor"].contains(url.lastPathComponent) { e.skipDescendants(); continue }
                if found.count >= 2000 { break }
                if fileTypes.contains(url.pathExtension.lowercased()), (try? url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true { found.append(url) }
            }
        }
        folderFiles=found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }; reloadRows()
    }
    func openURL(_ input: URL) {
        let url=input.standardizedFileURL
        if ["zip","textpack"].contains(url.pathExtension.lowercased()) { openArchive(url); return }
        if url.pathExtension.lowercased()=="textbundle" {
            let text=url.appendingPathComponent("text.md"); if FileManager.default.fileExists(atPath:text.path) { openURL(text); return }
        }
        var dir:ObjCBool=false
        if FileManager.default.fileExists(atPath:url.path,isDirectory:&dir), dir.boolValue { folderURL=url; refreshFolder(); modeControl.selectedSegment=0; search.stringValue=""; search.placeholderString="搜索文件"; modeChanged(); return }
        if let existing=documents.first(where:{$0.url?.standardizedFileURL==url}) { activate(existing.id); return }
        do { let d=try DocumentState(url:url); documents.append(d); modeControl.selectedSegment=0; search.stringValue=""; search.placeholderString="搜索文件"; activate(d.id) } catch { showError(error) }
    }
    @objc func save() { _=saveDocument(active) }
    @objc func saveAs() { _=saveDocument(active,asNew:true) }
    @discardableResult func saveDocument(_ doc: DocumentState?, asNew: Bool=false) -> Bool {
        guard let doc=doc else { return false }; var target=doc.url
        if target==nil || asNew {
            let panel=NSSavePanel(); panel.nameFieldStringValue=doc.url?.lastPathComponent ?? (doc.title=="未命名" ? "未命名.md" : doc.title+".md"); panel.canCreateDirectories=true
            if let dir=doc.url?.deletingLastPathComponent() ?? folderURL { panel.directoryURL=dir }
            guard panel.runModal() == .OK, let url=panel.url else { return false }; target=url
        }
        guard let url=target else { return false }
        if !asNew, let original=doc.originalData, doc.url==url {
            let current=try? Data(contentsOf:url)
            if current != original {
                let a=NSAlert(); a.messageText="文件已被其他程序修改"; a.informativeText="“\(doc.title)”的磁盘内容与打开时不同。覆盖会替换磁盘上的版本。你也可以取消后另存为。"; a.addButton(withTitle:"取消"); a.addButton(withTitle:"仍然覆盖")
                if a.runModal() != .alertSecondButtonReturn { return false }
            }
        }
        do {
            let data:Data
            if asNew { data=Data(doc.text.utf8) } else { data=try doc.encoded() }
            try data.write(to:url,options:.atomic)
            doc.url=url; doc.title=url.lastPathComponent; doc.savedText=doc.text; doc.originalData=data
            if asNew { doc.encoding = .utf8; doc.bom=false }
            preview.assets.documentDirectory=url.deletingLastPathComponent(); refreshDocument(); reloadRows(); persist(); return true
        } catch { showError(error); return false }
    }
    func confirm(_ doc: DocumentState) -> Bool {
        guard doc.dirty else { return true }
        activate(doc.id)
        let a=NSAlert(); a.messageText="要保存“\(doc.title)”吗？"; a.informativeText="保存后再关闭，或选择不保存以放弃本次修改。"; a.addButton(withTitle:"保存"); a.addButton(withTitle:"取消"); a.addButton(withTitle:"不保存")
        switch a.runModal() { case .alertFirstButtonReturn: return saveDocument(doc); case .alertThirdButtonReturn: doc.text=doc.savedText; if activeID==doc.id { changing=true; editor.string=doc.text; changing=false }; persist(); return true; default:return false }
    }
    func confirmAll() -> Bool { for doc in documents { if !confirm(doc) { return false } }; persist(); return true }
    @objc func closeDocument() {
        closeDocumentWithID(activeID)
    }
    func closeDocumentWithID(_ id: String) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        let doc = documents[index]
        let previousActiveID = activeID
        guard confirm(doc) else {
            if activeID != previousActiveID { activate(previousActiveID) }
            return
        }
        documents.removeAll { $0.id == id }
        if documents.isEmpty {
            newDocument()
        } else if activeID == id {
            let next = documents.first(where: { $0.id == previousActiveID }) ?? documents[min(index, documents.count - 1)]
            activate(next.id)
        } else {
            reloadRows()
        }
        persist()
    }
    func checkExternalChange() {
        guard let doc=active, let url=doc.url, !doc.dirty, let data=try? Data(contentsOf:url), data != doc.originalData, let decoded=try? decodeText(data) else { return }
        doc.text=decoded.0; doc.savedText=decoded.0; doc.encoding=decoded.1; doc.bom=decoded.2; doc.originalData=data; activate(doc.id)
    }
    func persist() {
        do {
            let data=try JSONEncoder().encode(documents.map(\.draft)); try data.write(to:support.appendingPathComponent("recovery.json"),options:.atomic)
            let c=try JSONEncoder().encode(clips); try c.write(to:support.appendingPathComponent("snippets.json"),options:.atomic)
            UserDefaults.standard.set(activeID,forKey:"active"); UserDefaults.standard.set(folderURL?.path,forKey:"folder"); UserDefaults.standard.set(fontSize,forKey:"fontSize")
        } catch { statusLabel.stringValue="草稿备份失败，请按 ⌘S 保存：\(error.localizedDescription)" }
    }
    func loadState() {
        guard !loadedState else { return }; loadedState=true
        if let data=try? Data(contentsOf:support.appendingPathComponent("recovery.json")), let drafts=try? JSONDecoder().decode([Draft].self,from:data) {
            documents=drafts.map { d in if let path=d.path, d.text==d.savedText, let disk=try? DocumentState(url:URL(fileURLWithPath:path)) { disk.id=d.id; return disk }; return DocumentState(draft:d) }
        }
        if let data=try? Data(contentsOf:support.appendingPathComponent("snippets.json")), let saved=try? JSONDecoder().decode([Clip].self,from:data) { clips=saved }
        activeID=UserDefaults.standard.string(forKey:"active") ?? ""
        if let path=UserDefaults.standard.string(forKey:"folder"), FileManager.default.fileExists(atPath:path) { folderURL=URL(fileURLWithPath:path); refreshFolder() }
        let size=UserDefaults.standard.double(forKey:"fontSize"); if size>=10 && size<=30 { fontSize=size; editor.font = .monospacedSystemFont(ofSize:fontSize,weight:.regular) }
    }
    func replaceSelection(_ text: String, range: NSRange?=nil) {
        guard active != nil else { return }; let r=range ?? editor.selectedRange()
        if editor.shouldChangeText(in:r,replacementString:text) { editor.textStorage?.replaceCharacters(in:r,with:text); editor.didChangeText(); editor.setSelectedRange(NSRange(location:r.location+(text as NSString).length,length:0)); window.makeFirstResponder(editor) }
    }
    func wrap(_ prefix: String, _ suffix: String, placeholder: String) {
        let r=editor.selectedRange(); let text=r.length>0 ? (editor.string as NSString).substring(with:r) : placeholder
        replaceSelection(prefix+text+suffix)
        editor.setSelectedRange(NSRange(location:r.location+(prefix as NSString).length,length:(text as NSString).length))
    }
    @objc func bold() { wrap("**","**",placeholder:"加粗文本") }
    @objc func italic() { wrap("*","*",placeholder:"斜体文本") }
    @objc func insertLink() { wrap("[","](https://example.com)",placeholder:"链接文字") }
    @objc func insertCode() { wrap("\n```\n","\n```\n",placeholder:"代码") }
    @objc func insertHeading() { replaceSelection("\n## 标题\n") }
    @objc func insertTask() { replaceSelection("\n- [ ] ") }
    @objc func insertDate() { replaceSelection(Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))) }
    @objc func findText() { window.makeFirstResponder(editor); let item=NSMenuItem(); item.tag=NSTextFinder.Action.showFindInterface.rawValue; editor.performFindPanelAction(item) }
    @objc func replaceText() { window.makeFirstResponder(editor); let item=NSMenuItem(); item.tag=NSTextFinder.Action.showReplaceInterface.rawValue; editor.performFindPanelAction(item) }
    @objc func viewModeChanged() {
        editorScroll.isHidden=viewControl.selectedSegment==2; preview.isHidden=viewControl.selectedSegment==0; contentSplit.adjustSubviews()
    }
    @objc func toggleOutline() { outlineVisible.toggle(); outlinePane.isHidden = !outlineVisible; contentSplit.adjustSubviews() }
    @objc func zoomIn() { fontSize=min(30,fontSize+1); editor.font = .monospacedSystemFont(ofSize:fontSize,weight:.regular); persist() }
    @objc func zoomOut() { fontSize=max(10,fontSize-1); editor.font = .monospacedSystemFont(ofSize:fontSize,weight:.regular); persist() }
    @objc func actionMenu(_ item: NSMenuItem) { runAction(item.tag) }
    func runAction(_ index: Int) {
        guard textActions.indices.contains(index), active != nil else { return }
        let selection=editor.selectedRange(); let range=selection.length>0 ? selection : NSRange(location:0,length:(editor.string as NSString).length)
        let input=(editor.string as NSString).substring(with:range)
        do { let result=try textActions[index].transform(input); replaceSelection(result,range:range); editor.undoManager?.setActionName(textActions[index].title) } catch { showError(error) }
    }
    @objc func regexReplace() {
        let a=NSAlert(); a.messageText="正则查找替换"; a.informativeText="对选区执行；未选中时处理全文。支持 $1 等捕获组，可撤销。"
        let pattern=NSTextField(); pattern.placeholderString="正则表达式，例如 ^#+ "
        let replacement=NSTextField(); replacement.placeholderString="替换为（可为空）"
        let stack=NSStackView(views:[pattern,replacement]); stack.orientation = .vertical; stack.spacing=10; stack.frame=NSRect(x:0,y:0,width:360,height:64); pattern.widthAnchor.constraint(equalToConstant:360).isActive=true; replacement.widthAnchor.constraint(equalToConstant:360).isActive=true; a.accessoryView=stack
        a.addButton(withTitle:"替换"); a.addButton(withTitle:"取消")
        guard a.runModal() == .alertFirstButtonReturn, !pattern.stringValue.isEmpty else { return }
        do { let re=try NSRegularExpression(pattern:pattern.stringValue,options:[.anchorsMatchLines]); let sel=editor.selectedRange(); let range=sel.length>0 ? sel : NSRange(location:0,length:(editor.string as NSString).length); let input=(editor.string as NSString).substring(with:range); let result=re.stringByReplacingMatches(in:input,range:NSRange(location:0,length:(input as NSString).length),withTemplate:replacement.stringValue); replaceSelection(result,range:range) } catch { showError(error) }
    }
    @objc func captureClipboard() { guard let text=NSPasteboard.general.string(forType:.string), !text.isEmpty else { showError(AppError.message("剪贴板中没有文本。")); return }; addClip(text) }
    @objc func captureSelection() { let r=editor.selectedRange(); guard r.length>0 else { showError(AppError.message("请先选中要收藏的文本。")); return }; addClip((editor.string as NSString).substring(with:r)) }
    func addClip(_ text: String) { if text.utf8.count>2_000_000 { showError(AppError.message("片段超过 2 MB，请保存为文件。")); return }; clips.insert(Clip(text:text),at:0); modeControl.selectedSegment=1; modeChanged(); persist() }
    func showClip(_ id: String) {
        guard let clip=clips.first(where:{$0.id==id}) else { return }
        let a=NSAlert(); a.messageText="文本片段"; a.informativeText="\(clip.text.count) 字符 · \(clip.date.formatted())"
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:460,height:240)); scroll.hasVerticalScroller=true; scroll.borderType = .bezelBorder
        let text=NSTextView(frame:scroll.bounds); text.isEditable=false; text.isRichText=false; text.string=clip.text; text.font = .systemFont(ofSize:14); text.textContainerInset=NSSize(width:12,height:12); text.autoresizingMask=[.width]; text.textContainer?.widthTracksTextView=true; scroll.documentView=text; a.accessoryView=scroll
        a.addButton(withTitle:"复制"); a.addButton(withTitle:"插入文档"); a.addButton(withTitle:clip.pinned ? "取消置顶" : "置顶"); a.addButton(withTitle:"删除"); a.addButton(withTitle:"关闭")
        let result=a.runModal().rawValue
        if result==1000 { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(clip.text,forType:.string) }
        else if result==1001 { if active==nil { newDocument() }; replaceSelection(clip.text) }
        else if result==1002 { if let i=clips.firstIndex(where:{$0.id==id}) { clips[i].pinned.toggle() } }
        else if result==1003 { let confirm=NSAlert(); confirm.messageText="删除这个片段？"; confirm.addButton(withTitle:"取消"); confirm.addButton(withTitle:"删除"); if confirm.runModal() == .alertSecondButtonReturn { clips.removeAll { $0.id==id } } }
        persist(); reloadRows()
    }
    @objc func revealFile() { if let url=active?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc func showSupport() { NSWorkspace.shared.open(support) }
    @objc func showGuide() { let d=DocumentState(); d.title="使用指南"; d.text=welcome+"\n\n## 保存与恢复\n\n使用 ⌘S 将文档写入磁盘。未保存的编辑会自动备份为本机草稿，下次启动恢复。磁盘文件被其他应用修改时，保存前会提醒。\n\n收藏的文本片段保存在应用的数据目录中；可以通过菜单“片段 → 打开本地数据目录”备份。\n\n预览使用随包内置的渲染资源。远程图片默认不加载，本地图片支持文档目录内的相对路径。\n\n本版本为独立开发的本地应用，不连接 Taio 云服务，也不执行 Taio/JSBox 脚本。`.taioactions` 文件可作为 JSON 查看编辑。\n"; d.savedText=d.text; documents.append(d); activate(d.id) }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options:[.applicationName:appName,.applicationVersion:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0.1",.version:Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "2",.credits:NSAttributedString(string:"本地 Markdown 工作台\n独立开发 · 无账户 · 无订阅\n支持 Apple Silicon 与 Intel Mac\n\n开源组件许可见应用包 Resources/ThirdPartyLicenses.txt。")])
    }
    func followLink(_ value: String) {
        if value.hasPrefix("#") { return }
        if let url=URL(string:value), ["http","https","mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url); return }
        guard !value.contains("://"), let root=active?.url?.deletingLastPathComponent() else { return }
        let path=value.components(separatedBy:"#")[0].removingPercentEncoding ?? value
        let target=root.appendingPathComponent(path).standardizedFileURL
        if fileTypes.contains(target.pathExtension.lowercased()) { openURL(target) }
    }
    func showError(_ error: Error) { let a=NSAlert(error:error); a.runModal() }
    @objc func exportPDF() {
        guard preview.ready, let doc=active else { return }; let p=NSSavePanel(); p.allowedContentTypes=[.pdf]; p.nameFieldStringValue=(doc.url?.deletingPathExtension().lastPathComponent ?? doc.title)+".pdf"
        guard p.runModal() == .OK, let url=p.url else { return }
        preview.createPDF(configuration:WKPDFConfiguration()) { [weak self] result in do { try result.get().write(to:url,options:.atomic) } catch { self?.showError(error) } }
    }
    @objc func exportHTML() {
        guard preview.ready, let doc=active else { return }; let p=NSSavePanel(); p.allowedContentTypes=[.html]; p.nameFieldStringValue=(doc.url?.deletingPathExtension().lastPathComponent ?? doc.title)+".html"
        guard p.runModal() == .OK, let url=p.url else { return }
        preview.evaluateJavaScript("window.exportDocument()") { [weak self] result,error in
            if let error=error { self?.showError(error); return }
            guard var html=result as? String else { return }
            // Embed bundled CSS/fonts and local images to keep the HTML portable.
            if let resources=Bundle.main.resourceURL {
                for name in ["preview.css","vendor/katex.min.css"] {
                    if let css=try? String(contentsOf:resources.appendingPathComponent(name),encoding:.utf8) {
                        var embedded=css
                        if name.contains("katex"), let re=try? NSRegularExpression(pattern:"url\\(([^)]+)\\)") {
                            for m in re.matches(in:css,range:NSRange(location:0,length:(css as NSString).length)).reversed() {
                                let raw=(css as NSString).substring(with:m.range(at:1)).trimmingCharacters(in:CharacterSet(charactersIn:"\"'"))
                                if let d=try? Data(contentsOf:resources.appendingPathComponent("vendor").appendingPathComponent(raw)) { embedded=(embedded as NSString).replacingCharacters(in:m.range,with:"url(data:font/woff2;base64,\(d.base64EncodedString()))") }
                            }
                        }
                        html=html.replacingOccurrences(of:"<!-- \(name) -->",with:"<style>\(embedded)</style>")
                    }
                }
            }
            if let root=doc.url?.deletingLastPathComponent().resolvingSymlinksInPath(), let re=try? NSRegularExpression(pattern:"mdasset://local/[^\" <>]+") {
                for m in re.matches(in:html,range:NSRange(location:0,length:(html as NSString).length)).reversed() {
                    let src=(html as NSString).substring(with:m.range)
                    if let u=URL(string:src) {
                        let target=root.appendingPathComponent(String(u.path.dropFirst())).standardizedFileURL.resolvingSymlinksInPath()
                        if target.path.hasPrefix(root.path+"/"), let d=try? Data(contentsOf:target), d.count<30_000_000 {
                            let mime=UTType(filenameExtension:target.pathExtension)?.preferredMIMEType ?? "image/png"
                            html=(html as NSString).replacingCharacters(in:m.range,with:"data:\(mime);base64,\(d.base64EncodedString())")
                        }
                    }
                }
            }
            do { try html.write(to:url,atomically:true,encoding:.utf8) } catch { self?.showError(error) }
        }
    }
    func runSelfTest() {
        DispatchQueue.main.asyncAfter(deadline:.now()+5) {
            let checks = ["previewReady":self.preview.ready,"documentLoaded":self.active != nil,"editorLoaded":!self.editor.string.isEmpty,"outlineCount":self.currentHeadings.count>0]
            self.preview.evaluateJavaScript("JSON.stringify({headings:document.querySelectorAll('h1,h2').length,table:!!document.querySelector('table'),math:!!document.querySelector('.katex'),mermaid:!!document.querySelector('.mermaid svg'),scriptCount:document.querySelectorAll('article script').length})") { result,error in
                let output:[String:Any] = ["native":checks,"web":result ?? "nil","error":error?.localizedDescription ?? ""]
                if let data=try? JSONSerialization.data(withJSONObject:output,options:.prettyPrinted) { try? data.write(to:URL(fileURLWithPath:"/tmp/freemd-selftest.json")) }
            }
        }
    }
}
