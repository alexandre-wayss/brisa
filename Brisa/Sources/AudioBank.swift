import Foundation
import AVFoundation

// Overlap the tail with the head instead of fading the loop to silence.
// The output wraps from head[overlap - 1] to head[overlap].
func seamlessLoop(_ source: AVAudioPCMBuffer, seconds: Double = 1.5) -> AVAudioPCMBuffer {
 let count = Int(source.frameLength)
 let overlap = min(Int(source.format.sampleRate * seconds), count / 4)
 guard overlap > 1, let input = source.floatChannelData,
       let result = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: AVAudioFrameCount(count - overlap)),
       let output = result.floatChannelData else { return source }
 result.frameLength = AVAudioFrameCount(count - overlap)
 let middle = count - 2 * overlap
 for channel in 0..<Int(source.format.channelCount) {
  for i in 0..<middle { output[channel][i] = input[channel][i + overlap] }
  for i in 0..<overlap {
   let phase = Double(i) / Double(overlap - 1) * .pi / 2
   output[channel][middle + i] = input[channel][count - overlap + i] * Float(cos(phase)) + input[channel][i] * Float(sin(phase))
  }
 }
 return result
}
func loadRecording(_ url:URL) throws -> AVAudioPCMBuffer {
 let file=try AVAudioFile(forReading:url)
 let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length))!
 try file.read(into:buffer)
 return buffer
}
func recordingURL(_ path:String) throws -> URL {
 guard let root=Bundle.main.resourceURL else {throw NSError(domain:"Brisa",code:1,userInfo:[NSLocalizedDescriptionKey:"Audio folder not found."])}
 let url=root.appendingPathComponent("Audio").appendingPathComponent(path)
 guard FileManager.default.fileExists(atPath:url.path) else {throw NSError(domain:"Brisa",code:2,userInfo:[NSLocalizedDescriptionKey:"Recording missing: \(path)"])}
 return url
}

final class AudioBank {
 let engine = AVAudioEngine()
 var players: [String: AVAudioPlayerNode] = [:]
 var buffers: [String: AVAudioPCMBuffer] = [:]
 func buffer(_ id: String) throws -> AVAudioPCMBuffer {
  if let b = buffers[id] { return b }
  let recordings = [
   "keyboard": "keyboard-ambient.wav",
   "realFireplace": "real/real-fireplace.wav",
   "beachWaves": "real/real-beach-waves.wav",
   "coffeeShop": "real/real-coffee-shop.wav"
  ]
  if let path = recordings[id] {let b=seamlessLoop(try loadRecording(recordingURL(path)));buffers[id]=b;return b}
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
   p[i]=Float(tanh(x))
  }
  let loop = seamlessLoop(b)
  buffers[id]=loop; return loop
 }
 func update(_ levels: [String:Double], playing: Bool, master: Double) throws {
  guard playing else {
   for node in players.values { node.pause() }
   return
  }
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
