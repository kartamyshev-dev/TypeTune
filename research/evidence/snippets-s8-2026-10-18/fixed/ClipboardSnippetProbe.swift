import AppKit
import Foundation
struct ProbeFailure: Error { let message: String }
func require(_ b: @autoclosure ()->Bool,_ s:String) throws { if !b() {throw ProbeFailure(message:s)} }
@main struct Main {
 static func main() throws {
  let mode=CommandLine.arguments[1], root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
  let name="textedit-clipboard-"+mode, output=root.appendingPathComponent("research/evidence/snippets-s8-2026-10-18/fixed/"+name+".json")
  let item = NSPasteboardItem()
  if mode=="image" {
   let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:16,pixelsHigh:16,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:64,bitsPerPixel:32)!
   for i in 0..<1024 {rep.bitmapData![i]=UInt8.random(in:0...255)}
   item.setData(rep.representation(using:.png,properties:[:])!,forType:.png)
  } else {item.setString("S8 clipboard "+UUID().uuidString,forType:.string)}
  item.setData(Data(),forType:NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
  item.setData(Data(),forType:NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
  var childCompleted = false
  let lease=try ClipboardLease(contents:[item],referenceContext:{
   if !childCompleted { return }
   let d=try JSONSerialization.jsonObject(with:Data(contentsOf:output)) as! [String:Any]
   try require((d["error"] == nil || d["error"] is NSNull) && d["completed"] as? Int == 2,"native_reference_not_completed")
  })
  var result:[String:Any]=["mode":mode]
  defer {
   result["clipboardRestore"]=lease.restore()
   let path=root.appendingPathComponent("research/evidence/snippets-s8-2026-10-18/fixed/clipboard-"+mode+".json")
   try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:path)
  }
  let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/env")
  process.arguments=["python3","scripts/record_native_probe.py","--output",output.path,"--app","/Applications/TypeTune.app","--batch","research/private/native-batches/snippets-s8-clipboard-"+mode+".json","--interval-ms","80"]
  try process.run();process.waitUntilExit();childCompleted = true
  result["processExitCode"]=process.terminationStatus;result["syntheticClipboardPreserved"]=lease.syntheticUnchanged()
 }
}
