import AppKit
import ApplicationServices
import Foundation
final class Trace {
 var events:[[String:Any]]=[]
 let start=ProcessInfo.processInfo.systemUptime
 func observe(_ type:CGEventType,_ e:CGEvent) {
  guard e.getIntegerValueField(.eventSourceUserData)==0x4c50544c, NSWorkspace.shared.frontmostApplication?.bundleIdentifier=="com.google.Chrome",events.count<128 else{return}
  events.append(["ms":(ProcessInfo.processInfo.systemUptime-start)*1000,"type":type.rawValue,"key":e.getIntegerValueField(.keyboardEventKeycode),"flags":e.flags.rawValue])
 }
}
@main struct Main {
 static func main() throws {
  let trace=Trace(), mask=CGEventMask((1<<CGEventType.keyDown.rawValue)|(1<<CGEventType.keyUp.rawValue)|(1<<CGEventType.flagsChanged.rawValue))
  guard let tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.listenOnly,eventsOfInterest:mask,callback:{ _,t,e,info in
   if let info {Unmanaged<Trace>.fromOpaque(info).takeUnretainedValue().observe(t,e)}
   return Unmanaged.passUnretained(e)
  },userInfo:Unmanaged.passUnretained(trace).toOpaque()),let source=CFMachPortCreateRunLoopSource(nil,tap,0) else{throw CocoaError(.featureUnsupported)}
  CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes);CGEvent.tapEnable(tap:tap,enable:true)
  defer{CGEvent.tapEnable(tap:tap,enable:false);CFMachPortInvalidate(tap);CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes)}
  let process=Process(), pipe=Pipe();process.executableURL=URL(fileURLWithPath:CommandLine.arguments[1]);process.arguments=[CommandLine.arguments[2]];process.standardOutput=pipe
  try process.run()
  var samples:[[String:Any]]=[], last:String="", finished:TimeInterval?
  while ProcessInfo.processInfo.systemUptime-trace.start<20 {
   if NSWorkspace.shared.frontmostApplication?.bundleIdentifier=="com.google.Chrome" {
    let b=NSPasteboard.general, c=b.changeCount, matches=b.string(forType:.string)=="Тестовая подпись\nВторая строка"
    let types=(b.pasteboardItems ?? []).flatMap{$0.types.map{ $0.rawValue }}.sorted()
    let signature=String(c)+String(matches)+types.joined()
    if signature != last {samples.append(["ms":(ProcessInfo.processInfo.systemUptime-trace.start)*1000,"generation":c,"matchesSnippet":matches,"types":types]);last=signature}
   }
   if !process.isRunning {if finished==nil {finished=ProcessInfo.processInfo.systemUptime};if ProcessInfo.processInfo.systemUptime-finished!>1 {break}}
   RunLoop.current.run(until:Date(timeIntervalSinceNow:0.005))
  }
  if process.isRunning {process.terminate();process.waitUntilExit()}
  let result=String(data:pipe.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
  print(String(data:try JSONSerialization.data(withJSONObject:["events":trace.events,"clipboard":samples,"probeOutput":result,"exit":process.terminationStatus,"ordinaryInputLogged":false],options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
 }
}
