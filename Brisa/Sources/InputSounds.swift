import Foundation
import Combine
import AVFoundation
import AppKit
import ApplicationServices
import Carbon
struct InputTone: Identifiable {
 let id:String; let name:String; let detail:String; let count:Int
}
let keyboardTones:[InputTone]=[
 .init(id:"kc1000",name:"Cherry KC 1000",detail:"Real recording · 32 distinct key presses",count:32),
 .init(id:"mechanical",name:"Mechanical — real recording",detail:"Feedbackdesignz · 3 keypress samples",count:3)
]
let mouseTones:[InputTone]=[
 .init(id:"mouse-recorded",name:"Mouse — crisp tap",detail:"joebro10 recording · 8 samples",count:8),
 .init(id:"mouse-clean",name:"Mouse — full click",detail:"Six Ways recording · press and release",count:1)
]

@MainActor final class InputSounds: ObservableObject {
 @Published var keyboard=UserDefaults.standard.bool(forKey:"inputKeyboardEnabled") {
  didSet {UserDefaults.standard.set(keyboard,forKey:"inputKeyboardEnabled")}
 }
 @Published var mouse=UserDefaults.standard.bool(forKey:"inputMouseEnabled") {
  didSet {UserDefaults.standard.set(mouse,forKey:"inputMouseEnabled")}
 }
 @Published var volume=(UserDefaults.standard.object(forKey:"inputVolume") as? Double) ?? 0.45 {
  didSet {UserDefaults.standard.set(volume,forKey:"inputVolume")}
 }
 @Published var keyboardStyle=UserDefaults.standard.string(forKey:"keyboardStyle") ?? "kc1000" {
  didSet {UserDefaults.standard.set(keyboardStyle,forKey:"keyboardStyle")}
 }
 @Published var mouseStyle=UserDefaults.standard.string(forKey:"mouseStyle") ?? "mouse-recorded" {
  didSet {UserDefaults.standard.set(mouseStyle,forKey:"mouseStyle")}
 }
 @Published var trusted=AXIsProcessTrusted()
 @Published var listenAllowed=CGPreflightListenEventAccess()
 @Published var keyboardConnected=false
 @Published var secureInput=IsSecureEventInputEnabled()
 private var keyboardTap:CFMachPort?
 private var keyboardSource:CFRunLoopSource?
 @Published var failure: String?
 private let engine=AVAudioEngine()
 private var voices:[AVAudioPlayerNode]=[]
 private var toneBuffers:[String:[AVAudioPCMBuffer]]=[:]
 private var lastSample:[String:Int]=[:]
 private var nextVoice=0
 private var globalMonitor:Any?
 private var localMonitor:Any?
 private var permissionTimer:Timer?
 init() {
  if !keyboardTones.contains(where:{$0.id==keyboardStyle}) {keyboardStyle="kc1000"}
  if !mouseTones.contains(where:{$0.id==mouseStyle}) {mouseStyle="mouse-recorded"}
  permissionTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in
   guard let service=self else{return}
   Task { @MainActor [weak service] in
    guard let service else{return}
    let current=AXIsProcessTrusted(), listen=CGPreflightListenEventAccess()
    service.secureInput=IsSecureEventInputEnabled()
    if current != service.trusted || listen != service.listenAllowed {
     service.trusted=current;service.listenAllowed=listen;service.configure()
    }
   }
  }
  configure()
 }
 func requestPermission() {
  let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
  trusted=AXIsProcessTrustedWithOptions(options)
  configure()
 }
 func reconnectKeyboard() {
  trusted=AXIsProcessTrusted();listenAllowed=CGPreflightListenEventAccess()
  configure()
 }
 func requestInputPermission() {
  _=CGRequestListenEventAccess()
  reconnectKeyboard()
 }
 private func stopKeyboardTap() {
  if let source=keyboardSource {CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes)}
  if let tap=keyboardTap {CGEvent.tapEnable(tap:tap,enable:false);CFMachPortInvalidate(tap)}
  keyboardSource=nil;keyboardTap=nil;keyboardConnected=false
 }
 private func startKeyboardTap() {
  guard keyboard && (trusted || listenAllowed) else{return}
  let mask=CGEventMask(1)<<CGEventType.keyDown.rawValue
  let tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.tailAppendEventTap,options:.listenOnly,eventsOfInterest:mask,callback:{_,type,event,context in
   guard let context=context else{return Unmanaged.passUnretained(event)}
   let owner=Unmanaged<InputSounds>.fromOpaque(context).takeUnretainedValue()
   if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    DispatchQueue.main.async { [weak owner] in
     guard let owner=owner,owner.keyboard,let tap=owner.keyboardTap else{return}
     CGEvent.tapEnable(tap:tap,enable:true)
     owner.keyboardConnected=CGEvent.tapIsEnabled(tap:tap)
    }
   }else if type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat)==0 {
    // Queue only a sound trigger, never the event or its text.
    DispatchQueue.main.async { [weak owner] in
     guard let owner=owner,owner.keyboard,owner.keyboardConnected else{return}
     owner.play(mouse:false)
    }
   }
   return Unmanaged.passUnretained(event)
  },userInfo:Unmanaged.passUnretained(self).toOpaque())
  guard let tap=tap,let source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0) else{return}
  keyboardTap=tap;keyboardSource=source
  CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
  CGEvent.tapEnable(tap:tap,enable:true)
  keyboardConnected=CGEvent.tapIsEnabled(tap:tap)
 }
 func configure() {
  stopKeyboardTap()
  if let token=globalMonitor {NSEvent.removeMonitor(token);globalMonitor=nil}
  if let token=localMonitor {NSEvent.removeMonitor(token);localMonitor=nil}
  guard keyboard || mouse else {engine.pause();return}
  var mask:NSEvent.EventTypeMask=[]
  startKeyboardTap()
  if keyboard && !keyboardConnected {mask.insert(.keyDown)}
  if mouse {mask.formUnion([.leftMouseDown,.rightMouseDown,.otherMouseDown])}
  localMonitor=NSEvent.addLocalMonitorForEvents(matching:mask){[weak self] event in
   self?.handle(event);return event
  }
  var globalMask=mask
  globalMask.remove(.keyDown) // Keyboard is handled by the dedicated passive tap.
  if !globalMask.isEmpty {
   globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:globalMask){[weak self] event in self?.handle(event)}
  }
  do {try prepare()}catch{failure=error.localizedDescription}
 }
 private func prepare() throws {
  if voices.isEmpty {
   let format=AVAudioFormat(standardFormatWithSampleRate:24000,channels:1)!
   for _ in 0..<12 {
    let node=AVAudioPlayerNode();engine.attach(node)
    engine.connect(node,to:engine.mainMixerNode,format:format);voices.append(node)
   }
  }
  if toneBuffers.isEmpty {
   var loaded:[String:[AVAudioPCMBuffer]]=[:]
   for tone in keyboardTones+mouseTones {
    loaded[tone.id]=try (0..<tone.count).map{try loadRecording(recordingURL(String(format:"%@/%02d.wav",tone.id,$0)))}
   }
   toneBuffers=loaded
  }
  if !engine.isRunning {try engine.start()}
 }
 private func handle(_ event:NSEvent) {
  // Inspect only event type and repeat flag. Never read or retain characters/key codes.
  if event.type == .keyDown {
   guard keyboard && !event.isARepeat else{return}
   play(mouse:false)
  }else if mouse {play(mouse:true)}
 }
 func play(mouse:Bool) {
  do {try prepare()}catch{failure=error.localizedDescription;return}
  let tones=mouse ? mouseTones:keyboardTones
  let selected=mouse ? mouseStyle:keyboardStyle
  let id=tones.contains(where:{$0.id==selected}) ? selected:tones[0].id
  guard let samples=toneBuffers[id], !samples.isEmpty else{return}
  let choices=samples.indices.filter{samples.count==1 || $0 != lastSample[id]}
  guard let index=choices.randomElement() else{return}
  lastSample[id]=index
  let buffer=samples[index]
  let node=voices[nextVoice];nextVoice=(nextVoice+1)%voices.count
  node.stop();node.volume=Float(volume)
  node.scheduleBuffer(buffer,at:nil);node.play()
 }
}
