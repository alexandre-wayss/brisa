import SwiftUI
import AVFoundation
import AppKit
import ApplicationServices
import Carbon

struct Sound: Identifiable {
 let id: String; let name: String; let icon: String; let category: String; let detail: String
}
let library: [Sound] = [
 .init(id:"white",name:"Ruído branco",icon:"waveform",category:"Ruídos",detail:"Uniforme e envolvente"),
 .init(id:"pink",name:"Ruído rosa",icon:"waveform.path",category:"Ruídos",detail:"Suave e equilibrado"),
 .init(id:"brown",name:"Ruído marrom",icon:"waveform.path.ecg",category:"Ruídos",detail:"Grave e profundo"),
 .init(id:"green",name:"Ruído verde",icon:"leaf",category:"Ruídos",detail:"Frequências médias suaves"),
 .init(id:"grey",name:"Ruído cinza",icon:"aqi.medium",category:"Ruídos",detail:"Textura ampla e filtrada"),
 .init(id:"rain",name:"Chuva leve",icon:"cloud.drizzle",category:"Água",detail:"Uma tarde tranquila"),
 .init(id:"heavy",name:"Chuva intensa",icon:"cloud.rain",category:"Água",detail:"Gotas em todas as direções"),
 .init(id:"tent",name:"Chuva na barraca",icon:"tent",category:"Água",detail:"Um pequeno refúgio"),
 .init(id:"thunder",name:"Trovão distante",icon:"cloud.bolt.rain",category:"Água",detail:"Ressonâncias graves"),
 .init(id:"creek",name:"Riacho",icon:"water.waves",category:"Água",detail:"Água em movimento"),
 .init(id:"ocean",name:"Ondas do mar",icon:"water.waves",category:"Água",detail:"Respire com a maré"),
 .init(id:"waterfall",name:"Cachoeira",icon:"drop.fill",category:"Água",detail:"Fluxo contínuo"),
 .init(id:"wind",name:"Vento nas folhas",icon:"wind",category:"Natureza",detail:"Uma brisa que passa"),
 .init(id:"fire",name:"Lareira",icon:"flame",category:"Natureza",detail:"Calor e pequenos estalos"),
 .init(id:"night",name:"Noite no campo",icon:"moon.stars",category:"Natureza",detail:"Grilos ao longe"),
 .init(id:"birds",name:"Amanhecer",icon:"bird",category:"Natureza",detail:"Cantos delicados"),
 .init(id:"fan",name:"Ventilador",icon:"fan",category:"Ambientes",detail:"Conforto constante"),
 .init(id:"cabin",name:"Cabine de avião",icon:"airplane",category:"Ambientes",detail:"Uma viagem serena"),
 .init(id:"train",name:"Trem",icon:"tram",category:"Ambientes",detail:"Ritmo sobre os trilhos"),
 .init(id:"keyboard",name:"Teclado",icon:"keyboard",category:"Ambientes",detail:"Pequenos toques ritmados")
]
struct Mix: Codable, Identifiable { var id = UUID(); var name: String; var levels: [String: Double] }

func loadRecording(_ url:URL) throws -> AVAudioPCMBuffer {
 let file=try AVAudioFile(forReading:url)
 let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length))!
 try file.read(into:buffer)
 return buffer
}
func recordingURL(_ path:String) throws -> URL {
 guard let root=Bundle.main.resourceURL else {throw NSError(domain:"Brisa",code:1,userInfo:[NSLocalizedDescriptionKey:"Pasta de áudio não encontrada."])}
 let url=root.appendingPathComponent("Audio").appendingPathComponent(path)
 guard FileManager.default.fileExists(atPath:url.path) else {throw NSError(domain:"Brisa",code:2,userInfo:[NSLocalizedDescriptionKey:"Gravação ausente: \(path)"])}
 return url
}

final class AudioBank {
 let engine = AVAudioEngine()
 var players: [String: AVAudioPlayerNode] = [:]
 var buffers: [String: AVAudioPCMBuffer] = [:]
 func buffer(_ id: String) throws -> AVAudioPCMBuffer {
  if let b = buffers[id] { return b }
  if id == "keyboard" {let b=try loadRecording(recordingURL("keyboard-ambient.wav"));buffers[id]=b;return b}
  let rate = 24000.0, count = 24000 * 16
  let format = AVAudioFormat(standardFormatWithSampleRate:rate,channels:1)!
  let b = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(count))!
  b.frameLength = AVAudioFrameCount(count)
  let p = b.floatChannelData![0]
  var low = 0.0, slow = 0.0, pink = 0.0
  var seed: UInt64 = 934821
  func rand() -> Double { seed = seed &* 6364136223846793005 &+ 1; return Double(seed >> 33) / Double(UInt32.max) * 4 - 1 }
  for i in 0..<count {
   let t = Double(i)/rate, n = rand()
   low += 0.025*(n-low); slow += 0.002*(n-slow); pink += 0.12*(n-pink)
   let swell = 0.6 + 0.4*sin(2 * .pi*t/8)
   var x: Double = 0
   switch id {
   case "white": x=n*0.23
   case "pink": x=pink*0.8 + low*0.5
   case "brown": x=slow*3.2
   case "green": x=(pink-low)*1.1
   case "grey": x=low*1.4+n*0.09
   case "rain": x=n*0.12+pink*0.35
   case "heavy": x=n*0.22+low*0.7
   case "tent": x=pink*0.8+(n > 0.995 ? n*0.25 : 0)
   case "thunder": x=slow*4*pow(max(0,sin(2 * .pi*t/16)),4)+pink*0.15
   case "creek": x=pink*0.6 + sin(2 * .pi*650*t + 5*sin(2 * .pi*3*t))*0.018*swell
   case "ocean": x=(pink*0.7+n*0.1)*swell
   case "waterfall": x=low*0.8+pink*0.6+n*0.1
   case "wind": x=low*1.5*swell
   case "fire": x=low*0.7+(n > 0.998 ? n*0.65 : 0)
   case "night": x=sin(2 * .pi*3200*t)*pow(max(0,sin(2 * .pi*4*t)),12)*0.07 + low*0.15
   case "birds": x=sin(2 * .pi*1800*t+30*sin(2 * .pi*2*t))*pow(max(0,sin(2 * .pi*t/4)),24)*0.09+pink*0.08
   case "fan": x=low*1.1+sin(2 * .pi*120*t)*0.025
   case "cabin": x=slow*2.2+pink*0.3
   case "train": x=low*0.9+n*0.1*pow(max(0,sin(2 * .pi*2*t)),16)
   default: x=0
   }
   // Gentle loop edges prevent discontinuity clicks.
   let edge = min(1.0,min(Double(i)/1200,Double(count-1-i)/1200))
   p[i]=Float(tanh(x)*edge)
  }
  buffers[id]=b; return b
 }
 func update(_ levels: [String:Double], playing: Bool, master: Double) throws {
  for (id,level) in levels where level > 0 {
   if players[id] == nil {
    let b=try buffer(id), node=AVAudioPlayerNode(); engine.attach(node)
    engine.connect(node,to:engine.mainMixerNode,format:b.format)
    node.scheduleBuffer(b,at:nil,options:.loops); players[id]=node
   }
  }
  if !engine.isRunning { try engine.start() }
  engine.mainMixerNode.outputVolume=Float(master)
  for (id,node) in players { node.volume=Float(levels[id] ?? 0); if playing { if !node.isPlaying { node.play() } } else { node.pause() } }
 }
}

struct InputTone: Identifiable {
 let id:String; let name:String; let detail:String; let count:Int
}
let keyboardTones:[InputTone]=[
 .init(id:"kc1000",name:"Cherry KC 1000",detail:"Gravação real · 32 toques diferentes",count:32),
 .init(id:"mechanical",name:"Mecânico — gravação real",detail:"Feedbackdesignz · 3 amostras de toques",count:3)
]
let mouseTones:[InputTone]=[
 .init(id:"mouse-recorded",name:"Mouse — toque seco",detail:"Gravação de joebro10 · 8 amostras",count:8),
 .init(id:"mouse-clean",name:"Mouse — clique completo",detail:"Gravação de Six Ways · pressionar e soltar",count:1)
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
   Task { @MainActor in
    guard let self=self else{return}
    let current=AXIsProcessTrusted(), listen=CGPreflightListenEventAccess()
    self.secureInput=IsSecureEventInputEnabled()
    if current != self.trusted || listen != self.listenAllowed {
     self.trusted=current;self.listenAllowed=listen;self.configure()
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

struct InputSoundsView:View {
 @ObservedObject var input:InputSounds
 @Environment(\.dismiss) private var dismiss
 var body:some View {
  VStack(alignment:.leading,spacing:16){
   HStack{Text("Sons ao interagir").font(.title2.weight(.semibold));Spacer();Button("Concluído"){dismiss()}}
   Text("Gravações reais a cada tecla ou clique, inclusive em outros apps. Mantenha o Brisa aberto.").foregroundStyle(.secondary)
   Toggle("Som ao pressionar uma tecla",isOn:$input.keyboard).onChange(of:input.keyboard){_ in input.configure()}
   HStack{
    Picker("Teclado",selection:$input.keyboardStyle){ForEach(keyboardTones){Text($0.name).tag($0.id)}}
    Button("Ouvir"){input.play(mouse:false)}.help("Ouvir estilo de teclado")
   }
   Text(keyboardTones.first(where:{$0.id==input.keyboardStyle})?.detail ?? "").font(.caption).foregroundStyle(.secondary)
   Toggle("Som ao clicar com o mouse",isOn:$input.mouse).onChange(of:input.mouse){_ in input.configure()}
   HStack{
    Picker("Mouse",selection:$input.mouseStyle){ForEach(mouseTones){Text($0.name).tag($0.id)}}
    Button("Ouvir"){input.play(mouse:true)}.help("Ouvir estilo de mouse")
   }
   Text(mouseTones.first(where:{$0.id==input.mouseStyle})?.detail ?? "").font(.caption).foregroundStyle(.secondary)
   HStack{Text("Volume");Slider(value:$input.volume,in:0...1);Text("\(Int(input.volume*100))%").monospacedDigit().frame(width:42)}
   Divider()
   VStack(alignment:.leading,spacing:10){
    Label(!input.keyboard ? "Teclado desligado":input.keyboardConnected ? "Teclado global conectado":"Teclado disponível apenas no Brisa",systemImage:input.keyboardConnected ? "checkmark.circle":"keyboard")
     .foregroundStyle(input.keyboardConnected ? accent:Color.secondary)
    if input.secureInput {Text("A entrada segura está ativa no macOS. Saia do campo protegido ou desative a entrada segura no app que a ativou para ouvir as teclas.").font(.caption).foregroundStyle(.orange)}
    if input.keyboard && !input.keyboardConnected {
     Text("O macOS ainda não liberou esta versão do Brisa. Em Privacidade e Segurança, remova a entrada antiga do Brisa de Acessibilidade e adicione este app novamente. Se necessário, autorize também Monitoramento de Entrada e reabra o Brisa.").font(.caption)
     HStack{
      Button("Acessibilidade…"){input.requestPermission()}
      Button("Monitoramento de Entrada…"){input.requestInputPermission()}
     }
     Button("Mostrar este Brisa no Finder"){NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])}
    }
    Button("Reconectar teclado"){input.reconnectKeyboard()}
   }
   Text("O Brisa não lê nem salva o texto digitado. Campos protegidos pelo macOS podem não emitir som. Suas opções e o volume são restaurados ao abrir o Brisa.").font(.caption).foregroundStyle(.secondary)
   if let failure=input.failure {Text("Falha no áudio: \(failure)").font(.caption).foregroundStyle(.red)}
  }.padding(28).frame(width:560).tint(accent).preferredColorScheme(.dark)
 }
}

@MainActor final class Model: ObservableObject {
 let inputSounds=InputSounds()
 @Published var levels: [String:Double] = [:]
 @Published var favorites: Set<String> = []
 @Published var mixes: [Mix] = []
 @Published var playing=false
 @Published var master=(UserDefaults.standard.object(forKey:"masterVolume") as? Double) ?? 0.65 {
  didSet {UserDefaults.standard.set(master,forKey:"masterVolume")}
 }
 @Published var remaining=0
 @Published var error: String?
 private var volumeBeforeMute: Double = 0.65
 let audio=AudioBank()
 var timer: Timer?
 init() {
  levels=UserDefaults.standard.dictionary(forKey:"levels") as? [String:Double] ?? [:]
  favorites=Set(UserDefaults.standard.stringArray(forKey:"favorites") ?? [])
  if let d=UserDefaults.standard.data(forKey:"mixes"),let m=try? JSONDecoder().decode([Mix].self,from:d) { mixes=m }
  volumeBeforeMute=master > 0 ? master : 0.65
  timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in Task { @MainActor in
   guard let self=self,self.remaining>0 else{return}; self.remaining-=1
   if self.remaining==0 { self.playing=false; self.sync() }
   else if self.remaining<=15 { self.audio.engine.mainMixerNode.outputVolume=Float(self.master)*Float(self.remaining)/15 }
  }}
 }
 func sync() { do { try audio.update(levels,playing:playing,master:master) } catch { self.error=error.localizedDescription; playing=false }; UserDefaults.standard.set(levels,forKey:"levels") }
 func toggle(_ id:String) { if levels[id] != nil {levels.removeValue(forKey:id)} else {levels[id]=0.05;playing=true}; if levels.isEmpty{playing=false};sync() }
 func play() { if levels.isEmpty{levels["rain"]=0.05}; playing.toggle();sync() }
 func toggleMute() { if master > 0 {volumeBeforeMute=master;master=0} else {master=volumeBeforeMute};sync() }
 func replace(with sound:Sound) { levels=[sound.id:0.05];playing=true;sync() }
 var nowPlayingTitle:String { let names=levels.keys.compactMap{id in library.first(where:{$0.id==id})?.name}; return names.isEmpty ? "Nenhum som selecionado" : names.prefix(2).joined(separator:" + ") }
 func favorite(_ id:String) { if favorites.contains(id){favorites.remove(id)}else{favorites.insert(id)};UserDefaults.standard.set(Array(favorites),forKey:"favorites") }
 func save(_ name:String) { mixes.append(Mix(name:name,levels:levels));persistMixes() }
 func persistMixes(){if let d=try? JSONEncoder().encode(mixes){UserDefaults.standard.set(d,forKey:"mixes")}}
 func preset(_ levels:[String:Double]) {self.levels=levels;playing=true;sync()}
}
let accent=Color(red:0.66,green:0.79,blue:0.63)
struct WelcomeView: View {
 @State private var page = 0
 let finish: () -> Void
 private let pages = [
  ("wind", "A quieter space", "Build a personal soundscape for focus, rest, or sleep."),
  ("slider.horizontal.3", "Make it yours", "Mix sounds, tune every level, and save your favorite environments."),
  ("menubar.rectangle", "Always within reach", "Control Brisa from the menu bar. Keyboard sounds are optional and stay on your Mac.")
 ]
 var body: some View {
  ZStack {
   LinearGradient(colors:[Color(red:0.035,green:0.075,blue:0.075),Color(red:0.08,green:0.15,blue:0.13)],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
   Circle().fill(accent.opacity(0.24)).frame(width:360).blur(radius:85).offset(x:150,y:-220)
   VStack(spacing:0) {
    HStack {Spacer();Button("Skip") { finish() }.buttonStyle(.plain).foregroundStyle(.secondary).padding(22)}
    let item=pages[page]
    VStack(spacing:22) {
     Image(systemName:item.0).font(.system(size:48,weight:.light)).foregroundStyle(accent).frame(width:104,height:104).background(.ultraThinMaterial,in:Circle()).overlay(Circle().stroke(.white.opacity(0.18),lineWidth:1))
     Text(item.1).font(.system(size:28,weight:.semibold,design:.rounded))
     Text(item.2).font(.system(size:15)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(width:330)
    }.id(page).transition(.opacity.combined(with:.scale(scale:0.96))).frame(height:285)
    HStack(spacing:7){ForEach(pages.indices,id:\.self){index in Circle().fill(index==page ? accent:Color.white.opacity(0.22)).frame(width:index==page ? 18:6,height:6)}}.padding(.bottom,28)
    Button(page == pages.count-1 ? "Start listening" : "Continue") { if page == pages.count-1 {finish()} else {withAnimation{page += 1}} }
     .buttonStyle(.plain).font(.system(size:14,weight:.semibold)).foregroundStyle(Color.black.opacity(0.8)).frame(width:190,height:46).background(accent,in:Capsule()).padding(.bottom,36)
   }
  }.frame(width:500,height:470).preferredColorScheme(.dark).tint(accent)
 }
}
struct ContentView: View {
 @ObservedObject var model: Model
 @State private var category="Todos os sons"
 @State private var search=""
 @State private var save=false
 @State private var mixName=""
 @State private var editingMix: Mix?
 @State private var showInputSounds=false
 @State private var showWelcome=false
 let categories=["Todos os sons","Favoritos","Ruídos","Água","Natureza","Ambientes","Minhas misturas"]
 var filtered:[Sound] {library.filter{(category=="Todos os sons" || category=="Favoritos" && model.favorites.contains($0.id) || category==$0.category) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))}}
 var body: some View {
 ZStack {
  LinearGradient(colors:[Color(red:0.045,green:0.065,blue:0.07),Color(red:0.08,green:0.115,blue:0.105),Color(red:0.045,green:0.055,blue:0.06)],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
  Circle().fill(accent.opacity(0.18)).frame(width:500).blur(radius:100).offset(x:390,y:-300)
  Circle().fill(Color.cyan.opacity(0.10)).frame(width:430).blur(radius:100).offset(x:-420,y:330)
  VStack(spacing:0){
   HStack(spacing:16){
    HStack(spacing:9){Image(systemName:"wind").font(.system(size:21,weight:.medium));Text("brisa").font(.system(size:24,weight:.semibold,design:.rounded))}.foregroundStyle(accent)
    Spacer()
    Button{showInputSounds=true}label:{Label("Interagir",systemImage:"keyboard").font(.system(size:12,weight:.medium)).padding(.horizontal,13).padding(.vertical,9).background(.white.opacity(0.08),in:Capsule())}.buttonStyle(.plain)
    HStack(spacing:7){Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("Buscar",text:$search).textFieldStyle(.plain).frame(width:150)}.padding(.horizontal,13).padding(.vertical,9).background(.white.opacity(0.08),in:Capsule())
   }.padding(.horizontal,34).padding(.top,25).padding(.bottom,18)
   ScrollView(.horizontal,showsIndicators:false){
    HStack(spacing:8){ForEach(categories,id:\.self){filter in
     Button{withAnimation(.easeInOut(duration:0.2)){category=filter}}label:{HStack(spacing:6){Image(systemName:icon(filter));Text(filter);if filter=="Favoritos" && !model.favorites.isEmpty {Text("\(model.favorites.count)").foregroundStyle(category==filter ? Color.black.opacity(0.55):.secondary)}}.font(.system(size:12,weight:.medium)).padding(.horizontal,13).padding(.vertical,9).background(category==filter ? accent:.white.opacity(0.07),in:Capsule()).foregroundStyle(category==filter ? Color.black.opacity(0.82):.primary)}.buttonStyle(.plain)
    }}.padding(.horizontal,34)
   }.padding(.bottom,20)
   HStack(alignment:.firstTextBaseline){VStack(alignment:.leading,spacing:4){Text(category).font(.system(size:30,weight:.semibold,design:.rounded));Text(category=="Minhas misturas" ? "Seus ambientes salvos." : "Selecione, combine e ajuste ao seu ritmo.").font(.system(size:13)).foregroundStyle(.secondary)};Spacer()}.padding(.horizontal,34).padding(.bottom,18)
   ScrollView {
    VStack(alignment:.leading,spacing:20){
     if category=="Todos os sons" && search.isEmpty {
      HStack(spacing:12){preset("Foco profundo","scope",["brown":0.05,"rain":0.05]);preset("Pausa tranquila","leaf",["ocean":0.05,"wind":0.05]);preset("Boa noite","moon",["pink":0.05,"night":0.05])}
     }
     if category=="Minhas misturas" {
      if model.mixes.isEmpty{empty("Seu ambiente, do seu jeito","Ative alguns sons e salve sua primeira mistura.")}
      ForEach(model.mixes){mix in
       HStack(spacing:16){
        Button{
         if model.playing && model.levels == mix.levels {model.playing=false;model.sync()}
         else {model.preset(mix.levels)}
        }label:{
         Image(systemName:model.playing && model.levels == mix.levels ? "pause.fill":"play.fill")
          .font(.system(size:15)).foregroundStyle(Color.black.opacity(0.8))
          .frame(width:40,height:40).background(accent,in:Circle())
        }.buttonStyle(.plain)
         .accessibilityLabel(model.playing && model.levels == mix.levels ? "Pausar \(mix.name)":"Reproduzir \(mix.name)")
        Button{model.preset(mix.levels)}label:{
         VStack(alignment:.leading,spacing:5){Text(mix.name).font(.system(size:15,weight:.medium));Text("\(mix.levels.count) sons").font(.caption).foregroundStyle(.secondary)}
        }.buttonStyle(.plain)
        Spacer()
        if model.playing && model.levels == mix.levels {Text("Reproduzindo").font(.caption).foregroundStyle(accent)}
        Button{editingMix=mix}label:{Image(systemName:"pencil")}.buttonStyle(.borderless).accessibilityLabel("Editar \(mix.name)").help("Editar mistura")
        Button{model.mixes.removeAll{$0.id==mix.id};model.persistMixes()}label:{Image(systemName:"trash")}.buttonStyle(.borderless).accessibilityLabel("Excluir \(mix.name)")
       }.padding(20).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:14))
      }
     } else {
      if filtered.isEmpty {empty("Nenhum som por aqui",category=="Favoritos" ? "Toque no coração para guardar seus sons preferidos.":"Experimente outra busca.")}
      LazyVGrid(columns:[GridItem(.adaptive(minimum:210),spacing:14)],spacing:14){ForEach(filtered){sound in card(sound)}}
     }
    }.padding(.horizontal,34).padding(.bottom,18)
   }
   player.padding(.horizontal,26).padding(.bottom,22)
  }
 }.frame(minWidth:920,minHeight:640).preferredColorScheme(.dark).tint(accent)
 .sheet(isPresented:$save){VStack(alignment:.leading,spacing:20){Text("Salvar mistura").font(.title2);TextField("Nome da mistura",text:$mixName);HStack{Button("Cancelar"){save=false};Spacer();Button("Salvar"){model.save(mixName.trimmingCharacters(in:.whitespaces));save=false;mixName=""}.disabled(mixName.trimmingCharacters(in:.whitespaces).isEmpty)}}.padding(30).frame(width:360)}
 .sheet(isPresented:$showInputSounds){InputSoundsView(input:model.inputSounds)}
 .sheet(isPresented:$showWelcome){WelcomeView{UserDefaults.standard.set(true,forKey:"didSeeWelcome");showWelcome=false}}
 .sheet(item:$editingMix){mix in
  MixEditor(mix:mix){updated in
   if let index=model.mixes.firstIndex(where:{$0.id==updated.id}) {
    let wasCurrent=model.levels == model.mixes[index].levels
    model.mixes[index]=updated
    model.persistMixes()
    if wasCurrent {model.levels=updated.levels;model.sync()}
   }
  }
 }
 .alert("Não foi possível iniciar o áudio",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})){Button("OK"){model.error=nil}}message:{Text(model.error ?? "")}
 .onAppear { if !UserDefaults.standard.bool(forKey:"didSeeWelcome") { showWelcome=true } }
 }
 func icon(_ c:String)->String {switch c {case "Favoritos":return "heart";case "Ruídos":return "waveform";case "Água":return "drop";case "Natureza":return "leaf";case "Ambientes":return "building.2";case "Minhas misturas":return "slider.horizontal.3";default:return "square.grid.2x2"}}
 func empty(_ title:String,_ detail:String)->some View {VStack(spacing:12){Image(systemName:"wind").font(.largeTitle).foregroundStyle(accent);Text(title).font(.title3);Text(detail).foregroundStyle(.secondary)}.frame(maxWidth:.infinity).padding(.vertical,70)}
 func preset(_ name:String,_ symbol:String,_ levels:[String:Double])->some View {Button{model.preset(levels)}label:{HStack{Image(systemName:symbol).foregroundStyle(accent);Text(name).font(.system(size:12,weight:.medium));Spacer();Image(systemName:"arrow.up.right").font(.caption).foregroundStyle(.secondary)}.padding(18).frame(maxWidth:.infinity).background(accent.opacity(0.07),in:RoundedRectangle(cornerRadius:13))}.buttonStyle(.plain)}
 func card(_ sound:Sound)->some View {
 let active=model.levels[sound.id] != nil
 return VStack(alignment:.leading,spacing:15){
  HStack{Button{model.toggle(sound.id)}label:{Image(systemName:sound.icon).font(.system(size:27,weight:.light)).foregroundStyle(active ? accent:.secondary).frame(width:44,height:38)}.buttonStyle(.plain).accessibilityLabel("Ativar \(sound.name)");Spacer();Button{model.favorite(sound.id)}label:{Image(systemName:model.favorites.contains(sound.id) ? "heart.fill":"heart").foregroundStyle(model.favorites.contains(sound.id) ? accent:Color.secondary)}.buttonStyle(.plain).accessibilityLabel("Favoritar \(sound.name)")}
  Button{model.toggle(sound.id)}label:{VStack(alignment:.leading,spacing:5){Text(sound.name).font(.system(size:15,weight:.medium));Text(sound.detail).font(.system(size:11)).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)
  HStack{if active {Slider(value:Binding(get:{model.levels[sound.id] ?? 0.5},set:{model.levels[sound.id]=$0;model.sync()}),in:0...1).accessibilityLabel("Volume de \(sound.name)");Text("\(Int((model.levels[sound.id] ?? 0)*100))").font(.system(size:10,design:.monospaced)).foregroundStyle(accent).frame(width:25)}else{Text("Adicionar ao ambiente").font(.system(size:10)).foregroundStyle(.tertiary);Spacer();Button{model.toggle(sound.id)}label:{Image(systemName:"plus.circle").foregroundStyle(.secondary)}.buttonStyle(.plain)}}.frame(height:20)
 }.padding(18).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).fill(active ? accent.opacity(0.12):.white.opacity(0.025)).allowsHitTesting(false)).overlay(RoundedRectangle(cornerRadius:20).stroke(active ? accent.opacity(0.55):.white.opacity(0.13),lineWidth:1).allowsHitTesting(false)).shadow(color:.black.opacity(0.14),radius:14,y:7)
 }
 var player:some View {
 HStack(spacing:18){
  Button{model.play()}label:{Image(systemName:model.playing ? "pause.fill":"play.fill").font(.system(size:21,weight:.bold)).foregroundStyle(Color.black.opacity(0.78)).frame(width:56,height:56).background(accent,in:Circle()).shadow(color:accent.opacity(0.35),radius:12,y:5)}.buttonStyle(.plain).keyboardShortcut(.space,modifiers:[]).accessibilityLabel(model.playing ? "Pausar":"Reproduzir")
  VStack(alignment:.leading,spacing:6){HStack(spacing:7){Circle().fill(model.playing ? accent:Color.secondary).frame(width:7,height:7);Text(model.playing ? "Reproduzindo agora" : "Pronto para tocar").font(.system(size:14,weight:.semibold))};Text("\(model.levels.count) sons na sua mistura").font(.system(size:11)).foregroundStyle(.secondary)}
  Spacer(minLength:8)
  VStack(alignment:.trailing,spacing:6){HStack(spacing:8){Image(systemName:"speaker.wave.2").font(.caption).foregroundStyle(.secondary);Slider(value:$model.master,in:0...1).frame(width:130).onChange(of:model.master){_ in model.sync()}.accessibilityLabel("Volume geral");Text("\(Int(model.master*100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width:31)};Text(model.remaining>0 ? String(format:"Termina em %02d:%02d",model.remaining/60,model.remaining%60):"Sem temporizador").font(.system(size:10)).foregroundStyle(.secondary)}
  Menu{Button("Desativar"){model.remaining=0;model.sync()};ForEach([5,15,25,30,60,90],id:\.self){m in Button("\(m) minutos"){model.remaining=m*60;model.sync()}}}label:{Image(systemName:"timer").font(.system(size:15,weight:.medium)).frame(width:38,height:38).background(.white.opacity(0.10),in:Circle())}.menuStyle(.borderlessButton).fixedSize()
  Button("Limpar"){model.levels=[:];model.playing=false;model.sync()}.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).disabled(model.levels.isEmpty)
  Button{save=true}label:{Image(systemName:"plus").font(.system(size:13,weight:.bold)).frame(width:38,height:38).background(accent.opacity(0.20),in:Circle())}.buttonStyle(.plain).foregroundStyle(accent).accessibilityLabel("Salvar mistura").disabled(model.levels.isEmpty)
 }.padding(16).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:24)).overlay(RoundedRectangle(cornerRadius:24).stroke(.white.opacity(0.16),lineWidth:1).allowsHitTesting(false)).shadow(color:.black.opacity(0.22),radius:22,y:10)
 }
}
struct MixEditor: View {
 @Environment(\.dismiss) private var dismiss
 @State private var draft: Mix
 let onSave: (Mix)->Void
 init(mix:Mix,onSave:@escaping (Mix)->Void) {
  _draft=State(initialValue:mix);self.onSave=onSave
 }
 var body:some View {
  VStack(alignment:.leading,spacing:18){
   Text("Editar mistura").font(.title2.weight(.semibold))
   TextField("Nome da mistura",text:$draft.name).textFieldStyle(.roundedBorder)
   Text("Escolha os sons e ajuste os volumes.").font(.callout).foregroundStyle(.secondary)
   ScrollView {
    VStack(spacing:12){ForEach(library){sound in
     HStack(spacing:12){
      Toggle(isOn:Binding(get:{draft.levels[sound.id] != nil},set:{enabled in
       if enabled {draft.levels[sound.id]=0.05}else{draft.levels.removeValue(forKey:sound.id)}
      })){Label(sound.name,systemImage:sound.icon)}.toggleStyle(.checkbox).frame(width:220,alignment:.leading)
      if draft.levels[sound.id] != nil {
       Slider(value:Binding(get:{draft.levels[sound.id] ?? 0.5},set:{draft.levels[sound.id]=$0}),in:0...1).accessibilityLabel("Volume de \(sound.name)")
       Text("\(Int((draft.levels[sound.id] ?? 0)*100))%").font(.caption.monospacedDigit()).frame(width:40,alignment:.trailing)
      }else{Spacer()}
     }.padding(.vertical,5)
    }}.padding(4)
   }
   Divider()
   HStack{
    Text("\(draft.levels.count) sons selecionados").font(.caption).foregroundStyle(.secondary)
    Spacer()
    Button("Cancelar"){dismiss()}.keyboardShortcut(.cancelAction)
    Button("Salvar alterações"){
     draft.name=draft.name.trimmingCharacters(in:.whitespacesAndNewlines)
     onSave(draft);dismiss()
    }.keyboardShortcut(.defaultAction).disabled(draft.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.levels.isEmpty)
   }
  }.padding(26).frame(width:560,height:600).tint(accent).preferredColorScheme(.dark)
 }
}
struct MenuBarPlayerView: View {
 @ObservedObject var model: Model
 var body: some View {
  VStack(spacing:16){
   HStack(spacing:11){
    Image(systemName:"wind").font(.system(size:17,weight:.semibold)).foregroundStyle(accent).frame(width:34,height:34).background(accent.opacity(0.16),in:Circle())
    VStack(alignment:.leading,spacing:2){Text("brisa").font(.system(size:15,weight:.semibold,design:.rounded));Text(model.playing ? "Em reprodução" : "Pausado").font(.system(size:10,weight:.medium)).foregroundStyle(model.playing ? accent:.secondary)}
    Spacer()
    Button{NSApp.activate(ignoringOtherApps:true);NSApp.windows.first?.makeKeyAndOrderFront(nil)}label:{Image(systemName:"arrow.up.left.and.arrow.down.right").font(.caption).frame(width:28,height:28).background(.white.opacity(0.08),in:Circle())}.buttonStyle(.plain).help("Abrir Brisa")
   }
   VStack(alignment:.leading,spacing:5){Text(model.nowPlayingTitle).font(.system(size:16,weight:.medium)).lineLimit(1);Text("\(model.levels.count) sons na mistura").font(.system(size:11)).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)
   HStack(spacing:12){
    Button{model.play()}label:{Image(systemName:model.playing ? "pause.fill":"play.fill").font(.system(size:15,weight:.bold)).foregroundStyle(Color.black.opacity(0.8)).frame(width:42,height:42).background(accent,in:Circle())}.buttonStyle(.plain).accessibilityLabel(model.playing ? "Pausar":"Reproduzir")
    Button{model.toggleMute()}label:{Image(systemName:model.master == 0 ? "speaker.slash.fill":"speaker.wave.2.fill").font(.system(size:14)).frame(width:34,height:34).background(.white.opacity(0.09),in:Circle())}.buttonStyle(.plain).accessibilityLabel(model.master == 0 ? "Ativar som":"Mutar")
    Slider(value:$model.master,in:0...1).frame(width:116).onChange(of:model.master){_ in model.sync()}.accessibilityLabel("Volume geral")
    Text("\(Int(model.master*100))%").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).frame(width:27)
   }
   Divider().overlay(.white.opacity(0.16))
   HStack{Text("Trocar som").font(.system(size:12,weight:.medium));Spacer();Menu{ForEach(library){sound in Button{model.replace(with:sound)}label:{Label(sound.name,systemImage:sound.icon)}}}label:{HStack(spacing:5){Text("Escolher");Image(systemName:"chevron.up.chevron.down").font(.caption2)}.font(.system(size:12,weight:.medium)).foregroundStyle(accent).padding(.horizontal,11).padding(.vertical,7).background(accent.opacity(0.15),in:Capsule())}.menuStyle(.borderlessButton).fixedSize()}
   ScrollView(.horizontal,showsIndicators:false){HStack(spacing:7){ForEach(library.prefix(6)){sound in Button{model.replace(with:sound)}label:{Image(systemName:sound.icon).font(.system(size:14)).frame(width:35,height:35).background(model.levels[sound.id] != nil ? accent.opacity(0.24):.white.opacity(0.07),in:RoundedRectangle(cornerRadius:11))}.buttonStyle(.plain).help(sound.name)}}}
   HStack{Menu{Button("Desativar"){model.remaining=0;model.sync()};ForEach([5,15,25,30,60],id:\.self){minutes in Button("\(minutes) minutos"){model.remaining=minutes*60;model.sync()}}}label:{Label(model.remaining > 0 ? String(format:"%02d:%02d",model.remaining/60,model.remaining%60):"Timer",systemImage:"timer")}.menuStyle(.borderlessButton).font(.system(size:11)).foregroundStyle(.secondary);Spacer();Button("Limpar"){model.levels=[:];model.playing=false;model.sync()}.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(.secondary).disabled(model.levels.isEmpty)}
  }.padding(18).frame(width:325).background(.ultraThinMaterial).preferredColorScheme(.dark).tint(accent)
 }
}
@main struct BrisaApp:App {
 @StateObject private var model=Model()
 var body:some Scene {
  WindowGroup {ContentView(model:model)}.windowStyle(.hiddenTitleBar).defaultSize(width:1080,height:770)
  MenuBarExtra("Brisa",systemImage:"wind") {MenuBarPlayerView(model:model)}.menuBarExtraStyle(.window)
 }
}
