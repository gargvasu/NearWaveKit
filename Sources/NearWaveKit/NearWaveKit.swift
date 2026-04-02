// The Swift Programming Language
// https://docs.swift.org/swift-book

// MARK: - NearWaveKit Public API Re-exports
//
// Import this module to access all NearWaveKit types:
//
//   import NearWaveKit
//
//   let service: NSDTService = NSDTServiceImpl()
//   service.onDataReceived = { data in print(data) }
//   service.startListening()
//   service.send(data: [0x48, 0x65, 0x6C, 0x6C, 0x6F])  // "Hello"
//
// All public types are exported directly from this module:
//   - NSDTConfig
//   - NSDTService (protocol)
//   - NSDTServiceImpl
//   - Frame
//   - Checksum
//   - BitConverter
//   - FSKEncoder
//   - FSKDecoder
//   - AudioEngineManager
//   - NWLog
