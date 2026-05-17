// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import OSLog

/// Streaming WebM (EBML) demuxer. Feed raw bytes via `feed(_:)` as they
/// arrive over the MSE bridge ; the demuxer accumulates internally and
/// returns any VP9 frames that became fully available.
///
/// Scope is deliberately minimal (matches Basarunaa V2.b needs) :
///   - EBML Header → skipped
///   - Segment → entered (always unknown size = streaming)
///   - Tracks → resolves the *video* TrackEntry (Codec ID `V_VP9` only)
///   - Cluster → reads its absolute Timecode then yields SimpleBlocks of the
///     video track as `Frame`s, with PTS = ClusterTC + relative TC.
///
/// Out of scope (will revisit if logs flag it) :
///   - BlockGroup / Block (YouTube uses SimpleBlock exclusively)
///   - Lacing (VP9/WebM never laces in practice)
///   - TimecodeScale ≠ 1ms (YouTube uses the default 1_000_000 ns/tick)
///   - Non-VP9 codecs (`V_VP8`, `V_AV1`) — easy to add when needed
public final class WebMDemuxer: @unchecked Sendable {
  public struct Frame: @unchecked Sendable {
    /// Raw VP9 frame bytes (no NAL/IVF wrapper — VP9 is self-delimited).
    public let data: Data
    /// Absolute PTS in milliseconds.
    public let ptsMs: Int64
    public let isKeyframe: Bool
    public let trackNumber: UInt64
  }

  public struct TrackInfo: Sendable {
    public let trackNumber: UInt64
    public let codecID: String
    public let width: Int?
    public let height: Int?
  }

  // EBML element IDs we care about. Stored *with* the length marker bit,
  // exactly as they appear on the wire.
  private enum ID {
    static let ebml: UInt64       = 0x1A45DFA3
    static let segment: UInt64    = 0x18538067
    static let seekHead: UInt64   = 0x114D9B74
    static let info: UInt64       = 0x1549A966
    static let tracks: UInt64     = 0x1654AE6B
    static let cluster: UInt64    = 0x1F43B675
    static let cues: UInt64       = 0x1C53BB6B
    static let chapters: UInt64   = 0x1043A770
    static let tags: UInt64       = 0x1254C367
    static let attachments: UInt64 = 0x1941A469
    static let trackEntry: UInt64 = 0xAE
    static let trackNumber: UInt64 = 0xD7
    static let trackType: UInt64  = 0x83
    static let codecID: UInt64    = 0x86
    static let video: UInt64      = 0xE0
    static let pixelWidth: UInt64 = 0xB0
    static let pixelHeight: UInt64 = 0xBA
    static let timecode: UInt64   = 0xE7
    static let simpleBlock: UInt64 = 0xA3
    static let blockGroup: UInt64 = 0xA0
  }

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.WebM")
  private let label: String

  /// Internal byte buffer. Volontairement un `[UInt8]` et non un `Data` :
  /// `Data` peut conserver un `startIndex` non-zero après `removeFirst(_:)`,
  /// ce qui fait crasher `buffer[offset]` même quand `offset < buffer.count`
  /// (cf. crash 2026-05-17 sur readVintAt). `Array<UInt8>` réindexe toujours
  /// à 0 — comportement prévisible et 0-based garanti.
  private var buffer: [UInt8] = []
  /// Read cursor — bytes before this are consumed and may be compacted.
  private var cursor = 0
  /// Plafond protectif : si le buffer interne dépasse cette taille sans
  /// produire de frames, on assume un parser blocked sur un master element
  /// incomplet et on reset. 5 MB couvre largement une init segment WebM +
  /// un cluster 1 s à 1080p, sans laisser dériver vers l'OOM.
  private let maxBufferBytes = 5 * 1024 * 1024
  /// Once we cross the Segment header we set this and never reset (parsing
  /// stays in streaming mode for the lifetime of the SourceBuffer).
  private var insideSegment = false
  /// Resolved video TrackEntry (set once Tracks is parsed).
  private(set) public var videoTrack: TrackInfo?
  /// Currently-open Cluster's absolute timecode (ms, since TimecodeScale = 1ms).
  private var currentClusterTimecode: Int64 = 0

  public init(label: String = "default") {
    self.label = label
  }

  /// Feed bytes from one `appendBuffer` chunk. Returns any frames newly
  /// completed by this feed.
  public func feed(_ bytes: Data) -> [Frame] {
    buffer.append(contentsOf: bytes)
    var frames: [Frame] = []
    parse(into: &frames)
    compact()
    return frames
  }

  /// Drop all state — call on SourceBuffer recreate / page reset.
  public func reset() {
    buffer.removeAll(keepingCapacity: true)
    cursor = 0
    insideSegment = false
    videoTrack = nil
    currentClusterTimecode = 0
  }

  // MARK: - Parsing loop

  /// Main parser : at each iteration, try to read one top-level element
  /// header (ID + size) at the current cursor. If incomplete, bail out and
  /// wait for more bytes. Otherwise route the element to the right handler.
  ///
  /// We never throw on malformed bytes — we just log and try to resync at
  /// the next byte. MSE delivers segment-aligned bytes in practice so this
  /// should be rare ; the safety net is there for the chunk-straddling case.
  private func parse(into frames: inout [Frame]) {
    while cursor < buffer.count {
      let elementStart = cursor
      guard let (id, idLen) = readVintAt(cursor, keepMarker: true) else { return }
      let afterId = cursor + idLen
      guard let (size, sizeLen, isUnknownSize) = readSizeVintAt(afterId) else { return }
      let dataStart = afterId + sizeLen
      let dataEnd = isUnknownSize ? -1 : dataStart + Int(size)

      // Master elements (entered, not consumed wholesale)
      let isMaster = isMasterElement(id)
      if isMaster {
        // Special : Segment + Cluster typically arrive with unknown size or
        // very large size — we enter without checking dataEnd.
        switch id {
        case ID.segment:
          cursor = dataStart
          insideSegment = true
          continue
        case ID.tracks:
          // Tracks fits in the init segment (small). Skip if incomplete.
          guard !isUnknownSize, dataEnd <= buffer.count else { return }
          parseTracks(start: dataStart, end: dataEnd)
          cursor = dataEnd
          continue
        case ID.cluster:
          cursor = dataStart
          currentClusterTimecode = 0   // reset until we see the Timecode child
          continue
        case ID.trackEntry, ID.video, ID.blockGroup:
          // These are nested inside parents — we should not see them at the
          // top level. Skip past them defensively.
          if !isUnknownSize, dataEnd <= buffer.count {
            cursor = dataEnd
          } else {
            return
          }
          continue
        default:
          // Other masters we don't care about (SeekHead, Cues, Info, etc.)
          if isUnknownSize {
            // Unknown size on a master we don't enter ⇒ we'd never know
            // where it ends. Conservative : abort streaming for this buffer
            // pass, will retry once we get more bytes.
            return
          }
          guard dataEnd <= buffer.count else { return }
          cursor = dataEnd
          continue
        }
      }

      // Non-master : need the full payload to act.
      if isUnknownSize {
        // Non-master with unknown size is invalid EBML — log and resync.
        log.error("\(self.label, privacy: .public) non-master element id=\(String(id, radix: 16), privacy: .public) with unknown size")
        cursor = elementStart + 1
        continue
      }
      guard dataEnd <= buffer.count else { return }

      switch id {
      case ID.timecode:
        if let tc = readUInt(at: dataStart, length: Int(size)) {
          currentClusterTimecode = Int64(tc)
        }
      case ID.simpleBlock:
        if let frame = parseSimpleBlock(start: dataStart, end: dataEnd) {
          frames.append(frame)
        }
      default:
        break  // unknown / uninteresting element : skip
      }
      cursor = dataEnd
    }
  }

  /// Heuristic master-element classification. We list only the IDs we may
  /// encounter at the top level of a Segment (or nested in Tracks).
  private func isMasterElement(_ id: UInt64) -> Bool {
    switch id {
    case ID.ebml, ID.segment, ID.seekHead, ID.info, ID.tracks, ID.cluster,
         ID.cues, ID.chapters, ID.tags, ID.attachments,
         ID.trackEntry, ID.video, ID.blockGroup:
      return true
    default:
      return false
    }
  }

  // MARK: - Tracks

  private func parseTracks(start: Int, end: Int) {
    var p = start
    while p < end {
      guard let (id, idLen) = readVintAt(p, keepMarker: true) else { return }
      let afterId = p + idLen
      guard let (size, sizeLen, _) = readSizeVintAt(afterId) else { return }
      let dataStart = afterId + sizeLen
      let dataEnd = dataStart + Int(size)
      guard dataEnd <= end else { return }

      if id == ID.trackEntry {
        parseTrackEntry(start: dataStart, end: dataEnd)
        if videoTrack != nil { return }   // first video track wins
      }
      p = dataEnd
    }
  }

  private func parseTrackEntry(start: Int, end: Int) {
    var trackNumber: UInt64?
    var trackType: UInt64?
    var codecID: String?
    var width: Int?
    var height: Int?

    var p = start
    while p < end {
      guard let (id, idLen) = readVintAt(p, keepMarker: true) else { return }
      let afterId = p + idLen
      guard let (size, sizeLen, _) = readSizeVintAt(afterId) else { return }
      let dataStart = afterId + sizeLen
      let dataEnd = dataStart + Int(size)
      guard dataEnd <= end else { return }

      switch id {
      case ID.trackNumber:
        trackNumber = readUInt(at: dataStart, length: Int(size))
      case ID.trackType:
        trackType = readUInt(at: dataStart, length: Int(size))
      case ID.codecID:
        codecID = readString(at: dataStart, length: Int(size))
      case ID.video:
        parseVideo(start: dataStart, end: dataEnd, width: &width, height: &height)
      default:
        break
      }
      p = dataEnd
    }
    guard let tn = trackNumber, let tt = trackType, tt == 1, let cid = codecID else {
      return
    }
    let info = TrackInfo(trackNumber: tn, codecID: cid, width: width, height: height)
    videoTrack = info
    log.info(
      """
      \(self.label, privacy: .public) video_track_found track=\(tn, privacy: .public) \
      codec=\(cid, privacy: .public) w=\(width ?? -1, privacy: .public) h=\(height ?? -1, privacy: .public)
      """
    )
  }

  private func parseVideo(start: Int, end: Int, width: inout Int?, height: inout Int?) {
    var p = start
    while p < end {
      guard let (id, idLen) = readVintAt(p, keepMarker: true) else { return }
      let afterId = p + idLen
      guard let (size, sizeLen, _) = readSizeVintAt(afterId) else { return }
      let dataStart = afterId + sizeLen
      let dataEnd = dataStart + Int(size)
      guard dataEnd <= end else { return }
      switch id {
      case ID.pixelWidth:
        width = Int(readUInt(at: dataStart, length: Int(size)) ?? 0)
      case ID.pixelHeight:
        height = Int(readUInt(at: dataStart, length: Int(size)) ?? 0)
      default:
        break
      }
      p = dataEnd
    }
  }

  // MARK: - SimpleBlock

  /// SimpleBlock payload layout :
  ///   - TrackNumber: VINT (1-4 bytes, size marker masked off)
  ///   - Timecode   : int16 BE signed, relative to Cluster Timecode
  ///   - Flags      : 1 byte — bit 7 = keyframe, bits 4-5 = lacing
  ///   - Frame(s)
  private func parseSimpleBlock(start: Int, end: Int) -> Frame? {
    guard let (track, trackLen, _) = readSizeVintAt(start) else { return nil }
    let tcPos = start + trackLen
    guard tcPos + 3 <= end else { return nil }
    let tcHi = UInt16(buffer[tcPos])
    let tcLo = UInt16(buffer[tcPos + 1])
    let tcRaw = Int16(bitPattern: (tcHi << 8) | tcLo)
    let flags = buffer[tcPos + 2]
    let dataStart = tcPos + 3
    let dataEnd = end
    guard dataEnd > dataStart else { return nil }

    // Filter on video track only.
    guard let vt = videoTrack, vt.trackNumber == track else { return nil }

    // Lacing : 00 = no lacing (just one frame in data).
    let lacing = (flags >> 1) & 0b11
    if lacing != 0 {
      // Lacing not supported (YouTube/VP9 never laces) — log once per
      // session to keep us honest.
      log.error("\(self.label, privacy: .public) lacing=\(lacing, privacy: .public) not supported, dropping block")
      return nil
    }

    let pts = currentClusterTimecode + Int64(tcRaw)
    let isKey = (flags & 0x80) != 0
    let payload = Data(buffer[dataStart..<dataEnd])
    return Frame(data: payload, ptsMs: pts, isKeyframe: isKey, trackNumber: track)
  }

  // MARK: - VINT / primitive reads

  /// Read an EBML variable-length integer. With `keepMarker=true`, returns the
  /// full bit pattern of the wire bytes (used for Element IDs). With
  /// `keepMarker=false`, masks off the length marker bit (used for Sizes).
  ///
  /// Returns nil if not enough bytes are available yet.
  private func readVintAt(_ offset: Int, keepMarker: Bool) -> (UInt64, Int)? {
    guard offset < buffer.count else { return nil }
    let first = buffer[offset]
    if first == 0 { return nil }   // invalid : 0 not a valid VINT start
    var length = 1
    var mask: UInt8 = 0x80
    while length <= 8 {
      if (first & mask) != 0 { break }
      mask >>= 1
      length += 1
    }
    if length > 8 { return nil }
    guard offset + length <= buffer.count else { return nil }
    var value: UInt64
    if keepMarker {
      value = UInt64(first)
    } else {
      value = UInt64(first & (mask - 1))
    }
    for i in 1..<length {
      value = (value << 8) | UInt64(buffer[offset + i])
    }
    return (value, length)
  }

  /// Sizes have a marker bit + an "unknown size" sentinel (all-ones payload).
  /// Returns (size, length, isUnknownSize).
  private func readSizeVintAt(_ offset: Int) -> (UInt64, Int, Bool)? {
    guard offset < buffer.count else { return nil }
    let first = buffer[offset]
    if first == 0 { return nil }
    var length = 1
    var mask: UInt8 = 0x80
    while length <= 8 {
      if (first & mask) != 0 { break }
      mask >>= 1
      length += 1
    }
    if length > 8 { return nil }
    guard offset + length <= buffer.count else { return nil }
    let payloadMask = UInt64(mask - 1)
    var value: UInt64 = UInt64(first) & payloadMask
    var allOnes = (value == payloadMask)
    for i in 1..<length {
      let b = buffer[offset + i]
      value = (value << 8) | UInt64(b)
      if b != 0xFF { allOnes = false }
    }
    return (value, length, allOnes)
  }

  private func readUInt(at offset: Int, length: Int) -> UInt64? {
    guard length > 0, length <= 8, offset + length <= buffer.count else { return nil }
    var v: UInt64 = 0
    for i in 0..<length {
      v = (v << 8) | UInt64(buffer[offset + i])
    }
    return v
  }

  private func readString(at offset: Int, length: Int) -> String? {
    guard length >= 0, offset + length <= buffer.count else { return nil }
    if length == 0 { return "" }
    let sub = Data(buffer[offset..<(offset + length)])
    return String(data: sub, encoding: .ascii) ?? String(data: sub, encoding: .utf8)
  }

  // MARK: - Buffer management

  /// Drop bytes already consumed before `cursor` to keep memory bounded.
  /// We keep the cursor's tail intact so a half-parsed element survives.
  /// Au-delà de `maxBufferBytes` sans avoir avancé le cursor, on suppose un
  /// parser bloqué sur un master element incomplet ⇒ reset complet.
  private func compact() {
    if cursor > 64 * 1024 {
      buffer.removeFirst(cursor)
      cursor = 0
    }
    if buffer.count > maxBufferBytes {
      log.error(
        """
        \(self.label, privacy: .public) buffer_overflow size=\(self.buffer.count, privacy: .public) \
        cursor=\(self.cursor, privacy: .public) — forcing reset (videoTrack preserved)
        """
      )
      // On préserve `videoTrack` (déjà résolu) pour ne pas re-charger en
      // boucle si le bug réapparait — on perd des frames le temps de
      // resync sur la prochaine init segment / keyframe.
      buffer.removeAll(keepingCapacity: false)
      cursor = 0
      currentClusterTimecode = 0
    }
  }
}
