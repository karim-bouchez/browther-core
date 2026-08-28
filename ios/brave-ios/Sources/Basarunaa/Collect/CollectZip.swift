// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Basarunaa — écriture ZIP « STORE » (aucune compression), en FLUX.
///
/// Port de `private/extensions/basarunaa/src/collect/zip.js`, à une différence
/// près qui compte sur téléphone : **rien n'est matérialisé en mémoire**.
/// Desktop construit un `Blob` de toutes les entrées et laisse Chromium le
/// garder sur disque ; iOS n'a pas cet intermédiaire, et un pic de 60 Mo dans
/// le processus d'une app qui porte déjà des modèles CoreML est le genre de
/// chose que le système tue sans expliquer. On écrit donc chaque entrée dans le
/// fichier au fur et à mesure, en lisant les images par blocs.
///
/// Pourquoi pas de compression : le corpus est fait de JPEG, déjà compressés.
/// Deflate leur ferait gagner ~0 % pour un coût CPU réel. Un ZIP stored, c'est
/// un en-tête de 30 octets par fichier plus un index en fin d'archive — assez
/// court pour être écrit ici et relu par n'importe quel outil (unzip, Finder,
/// Files.app).
///
/// Pas de ZIP64 : chaque archive est plafonnée (< 4 Go, < 65 535 entrées).

private let crcTable: [UInt32] = {
  var table = [UInt32](repeating: 0, count: 256)
  for n in 0..<256 {
    var c = UInt32(n)
    for _ in 0..<8 {
      c = (c & 1) != 0 ? 0xedb8_8320 ^ (c >> 1) : c >> 1
    }
    table[n] = c
  }
  return table
}()

/// CRC-32 incrémental — le flux impose de le calculer bloc par bloc, alors que
/// desktop tient l'image entière en mémoire et la hache d'un coup.
public struct CRC32 {
  private var state: UInt32 = 0xffff_ffff

  public init() {}

  public mutating func update(_ bytes: some Sequence<UInt8>) {
    var c = state
    for b in bytes {
      c = crcTable[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8)
    }
    state = c
  }

  public var value: UInt32 { state ^ 0xffff_ffff }
}

public func crc32(_ data: Data) -> UInt32 {
  var c = CRC32()
  c.update(data)
  return c.value
}

public enum CollectZipError: Error {
  case cannotCreate(String)
  case tooManyEntries
}

/// Écrivain ZIP séquentiel. Ordre d'usage : `add…` autant de fois que voulu,
/// puis **`finish()` obligatoirement** — sans lui le fichier n'a pas d'index
/// central et aucun outil ne saura le lire.
public final class ZipWriter {
  private struct CentralEntry {
    let name: [UInt8]
    let crc: UInt32
    let size: UInt32
    let offset: UInt32
  }

  private let handle: FileHandle
  private var central: [CentralEntry] = []
  private var offset: UInt32 = 0
  private let dosTime: UInt16
  private let dosDate: UInt16
  private var closed = false

  public private(set) var bytesWritten: Int = 0

  public init(url: URL, now: Date) throws {
    let fm = FileManager.default
    try? fm.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard fm.createFile(atPath: url.path, contents: nil) else {
      throw CollectZipError.cannotCreate(url.lastPathComponent)
    }
    guard let h = try? FileHandle(forWritingTo: url) else {
      throw CollectZipError.cannotCreate(url.lastPathComponent)
    }
    self.handle = h

    // Horodatage DOS. Décomposé en étapes typées : écrite d'un trait,
    // l'expression fait abandonner le vérificateur de types de Swift
    // (« unable to type-check this expression in reasonable time »).
    let cal = Calendar(identifier: .gregorian)
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
    let hour = UInt16(c.hour ?? 0) & 31
    let minute = UInt16(c.minute ?? 0) & 63
    let second = UInt16((c.second ?? 0) / 2) & 31
    self.dosTime = (hour << 11) | (minute << 5) | second

    let year = UInt16(max(1980, c.year ?? 1980) - 1980) & 127
    let month = UInt16(c.month ?? 1) & 15
    let day = UInt16(c.day ?? 1) & 31
    self.dosDate = (year << 9) | (month << 5) | day
  }

  /// Petit fichier déjà en mémoire (manifeste, `stats.json`).
  public func add(name: String, data: Data) {
    write(name: name, size: UInt32(data.count), crc: crc32(data)) { sink in
      sink(data)
    }
  }

  /// Fichier du spool — lu par blocs de 256 Ko. Le CRC impose deux passes sur
  /// les octets (l'en-tête local le précède dans le format), mais jamais plus
  /// d'un bloc à la fois en mémoire.
  public func add(name: String, fileURL: URL) throws {
    let chunkSize = 256 * 1024

    var crc = CRC32()
    var size = 0
    do {
      let reader = try FileHandle(forReadingFrom: fileURL)
      defer { try? reader.close() }
      while let chunk = try reader.read(upToCount: chunkSize), !chunk.isEmpty {
        crc.update(chunk)
        size += chunk.count
      }
    }

    write(name: name, size: UInt32(size), crc: crc.value) { sink in
      guard let reader = try? FileHandle(forReadingFrom: fileURL) else { return }
      defer { try? reader.close() }
      while let chunk = ((try? reader.read(upToCount: chunkSize)) ?? nil), !chunk.isEmpty {
        sink(chunk)
      }
    }
  }

  private func write(
    name: String, size: UInt32, crc: UInt32, payload: ((Data) -> Void) -> Void
  ) {
    let nameBytes = Array(name.utf8)

    var local = Data(capacity: 30)
    local.appendLE(UInt32(0x0403_4b50))  // signature
    local.appendLE(UInt16(20))           // version needed
    local.appendLE(UInt16(0x800))        // flags : bit 11 = nom en UTF-8
    local.appendLE(UInt16(0))            // méthode 0 = stored
    local.appendLE(dosTime)
    local.appendLE(dosDate)
    local.appendLE(crc)
    local.appendLE(size)                 // compressed
    local.appendLE(size)                 // uncompressed
    local.appendLE(UInt16(nameBytes.count))
    local.appendLE(UInt16(0))            // extra
    emit(local)
    emit(Data(nameBytes))

    payload { chunk in self.emit(chunk) }

    central.append(
      CentralEntry(name: nameBytes, crc: crc, size: size, offset: offset))
    offset += 30 + UInt32(nameBytes.count) + size
  }

  private func emit(_ data: Data) {
    guard !data.isEmpty else { return }
    handle.write(data)
    bytesWritten += data.count
  }

  /// Écrit l'index central et ferme. **Sans cet appel, l'archive est
  /// illisible** — c'est le seul état d'échec silencieux du format.
  @discardableResult
  public func finish() throws -> (entries: Int, bytes: Int) {
    guard !closed else { return (central.count, bytesWritten) }
    closed = true
    guard central.count <= 65535 else { throw CollectZipError.tooManyEntries }

    let centralStart = offset
    var centralSize: UInt32 = 0
    for e in central {
      var cen = Data(capacity: 46)
      cen.appendLE(UInt32(0x0201_4b50))
      cen.appendLE(UInt16(20))           // version made by
      cen.appendLE(UInt16(20))           // version needed
      cen.appendLE(UInt16(0x800))        // flags : bit 11 = nom en UTF-8
      cen.appendLE(UInt16(0))            // méthode 0 = stored
      cen.appendLE(dosTime)
      cen.appendLE(dosDate)
      cen.appendLE(e.crc)
      cen.appendLE(e.size)
      cen.appendLE(e.size)
      cen.appendLE(UInt16(e.name.count))
      cen.appendLE(UInt16(0))            // extra
      cen.appendLE(UInt16(0))            // comment
      cen.appendLE(UInt16(0))            // disk
      cen.appendLE(UInt16(0))            // internal attrs
      cen.appendLE(UInt32(0))            // external attrs
      cen.appendLE(e.offset)
      emit(cen)
      emit(Data(e.name))
      centralSize += 46 + UInt32(e.name.count)
    }

    var end = Data(capacity: 22)
    end.appendLE(UInt32(0x0605_4b50))
    end.appendLE(UInt16(0))              // disque courant
    end.appendLE(UInt16(0))              // disque de l'index
    end.appendLE(UInt16(central.count))
    end.appendLE(UInt16(central.count))
    end.appendLE(centralSize)
    end.appendLE(centralStart)
    end.appendLE(UInt16(0))              // longueur du commentaire
    emit(end)

    try? handle.close()
    return (central.count, bytesWritten)
  }

  deinit {
    if !closed { try? handle.close() }
  }
}

extension Data {
  fileprivate mutating func appendLE(_ v: UInt16) {
    append(UInt8(v & 0xff))
    append(UInt8((v >> 8) & 0xff))
  }

  fileprivate mutating func appendLE(_ v: UInt32) {
    append(UInt8(v & 0xff))
    append(UInt8((v >> 8) & 0xff))
    append(UInt8((v >> 16) & 0xff))
    append(UInt8((v >> 24) & 0xff))
  }
}
