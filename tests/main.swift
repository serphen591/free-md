import Foundation
func check(_ value: @autoclosure ()->Bool,_ name:String) { if !value() { fatalError("FAIL: "+name) }; print("PASS: "+name) }
let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:root) }
let content="# 中文标题\r\n\r\nHello 🐈\r\n"
let file=root.appendingPathComponent("sample.md")
try Data(content.utf8).write(to:file)
let doc=try DocumentState(url:file)
check(doc.text==content,"UTF-8 / Chinese / emoji / CRLF decoded without loss")
let encoded=try doc.encoded()
check(encoded==Data(content.utf8),"Unchanged content preserves bytes")
let bom=Data([0xEF,0xBB,0xBF])+Data(content.utf8)
try bom.write(to:file)
let bomDoc=try DocumentState(url:file)
let bomEncoded=try bomDoc.encoded()
check(bomEncoded==bom,"UTF-8 BOM preserved")
let utf16=content.data(using:.utf16)!
try utf16.write(to:file)
let utf16Doc=try DocumentState(url:file)
check(utf16Doc.text==content,"UTF-16 detected")
let utf16Encoded=try utf16Doc.encoded()
check(String(data:utf16Encoded,encoding:.utf16)==content,"UTF-16 save preserves text")
do { _=try decodeText(Data([0,1,2,0])); fatalError("binary accepted") } catch { print("PASS: binary files rejected") }
let be=Data([0xFE,0xFF])+content.data(using:.utf16BigEndian)!
try be.write(to:file)
let beDoc=try DocumentState(url:file)
let beOutput=try beDoc.encoded()
check(beOutput==be,"UTF-16 big-endian BOM and byte order preserved")
let hs=headings(in:"# 一\n```md\n# not heading\n```\n## 二 🐈\n")
check(hs.map(\.title)==["一","二 🐈"],"Outline ignores fenced code")
let source="# 一\n```md\n# not heading\n```\n## 二 🐈\n" as NSString
check(source.substring(with:hs[1].range)=="## 二 🐈","Outline uses correct UTF-16 range")
let unique=try textActions[1].transform("一\n二\n一")
check(unique=="一\n二","Deduplication preserves original order")
let formatted=try textActions[6].transform("{\"a\":1}")
check(formatted.contains("\n"),"JSON formatting")
do { _=try textActions[6].transform("invalid"); fatalError("invalid JSON accepted") } catch { print("PASS: invalid JSON reported") }
let draft=doc.draft
let round=try JSONDecoder().decode(Draft.self,from:JSONEncoder().encode(draft))
check(DocumentState(draft:round).text==content,"Recovery round trip")
print("All native core tests passed")
