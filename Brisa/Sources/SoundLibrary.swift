import Foundation
struct Sound: Identifiable {
 let id: String; let name: String; let icon: String; let category: String; let detail: String
}
let library: [Sound] = [
 .init(id:"white",name:"White Noise",icon:"waveform",category:"Noise",detail:"Even and immersive"),
 .init(id:"pink",name:"Pink Noise",icon:"waveform.path",category:"Noise",detail:"Soft and balanced"),
 .init(id:"brown",name:"Brown Noise",icon:"waveform.path.ecg",category:"Noise",detail:"Low and deep"),
 .init(id:"green",name:"Green Noise",icon:"leaf",category:"Noise",detail:"Gentle mid frequencies"),
 .init(id:"grey",name:"Grey Noise",icon:"aqi.medium",category:"Noise",detail:"Wide filtered texture"),
 .init(id:"rain",name:"Light Rain",icon:"cloud.drizzle",category:"Water",detail:"A quiet afternoon"),
 .init(id:"heavy",name:"Heavy Rain",icon:"cloud.rain",category:"Water",detail:"Rain in every direction"),
 .init(id:"tent",name:"Rain on a Tent",icon:"tent",category:"Water",detail:"A small shelter"),
 .init(id:"thunder",name:"Distant Thunder",icon:"cloud.bolt.rain",category:"Water",detail:"Deep rolling echoes"),
 .init(id:"creek",name:"Creek",icon:"water.waves",category:"Water",detail:"Moving water"),
 .init(id:"ocean",name:"Ocean Waves",icon:"water.waves",category:"Water",detail:"Breathe with the tide"),
 .init(id:"waterfall",name:"Waterfall",icon:"drop.fill",category:"Water",detail:"A continuous flow"),
 .init(id:"wind",name:"Wind in Leaves",icon:"wind",category:"Nature",detail:"A passing breeze"),
 .init(id:"fire",name:"Fireplace",icon:"flame",category:"Nature",detail:"Warmth and quiet crackles"),
 .init(id:"night",name:"Night Field",icon:"moon.stars",category:"Nature",detail:"Crickets in the distance"),
 .init(id:"birds",name:"Sunrise",icon:"bird",category:"Nature",detail:"Delicate birdsong"),
 .init(id:"fan",name:"Fan",icon:"fan",category:"Spaces",detail:"Steady comfort"),
 .init(id:"cabin",name:"Airplane Cabin",icon:"airplane",category:"Spaces",detail:"A calm journey"),
 .init(id:"train",name:"Train",icon:"tram",category:"Spaces",detail:"Rhythm on the rails"),
 .init(id:"keyboard",name:"Keyboard",icon:"keyboard",category:"Spaces",detail:"Small rhythmic taps")
]
struct Mix: Codable, Identifiable { var id = UUID(); var name: String; var levels: [String: Double] }
