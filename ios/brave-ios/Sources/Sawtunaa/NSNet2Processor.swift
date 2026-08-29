// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Accelerate
import Foundation
import onnxruntime_objc

/// NSNet2 stateful processor — port of Python NSNet2StatefulProcessor.
///
/// STFT -> log power -> ONNX inference (gain mask) -> ISTFT with overlap-add.
/// GRU hidden states are persisted across frames for streaming.
/// Uses vDSP for FFT (Accelerate framework).
public class NSNet2Processor {

  private static let TAG = "NSNet2"
  private static let SAMPLE_RATE = 48000
  private static let N_WIN = 960
  private static let N_FFT = 1024
  private static let N_HOP = 512
  private static let N_OVERLAP = 448  // N_WIN - N_HOP
  private static let N_BINS = 513  // N_FFT / 2 + 1
  private static let GRU_HIDDEN = 600

  // Reset GRU — porté à l'identique de Nsnet2Stream (macOS = référence).
  // ⚠️ Le périodique aveugle à 30 s du moteur standalone a été ÉCARTÉ côté
  // desktop parce qu'il grésille en pleine parole (cf. docs/sawtunaa/DESKTOP.md
  // § « Port qualité depuis le moteur standalone »). iOS l'avait gardé : c'est
  // corrigé ici. Ce qui le remplace : reset quand le silence de SORTIE dure
  // ≥ 5 s en continu (détection peak-hold, robuste aux blancs entre les mots),
  // + un filet forcé à 5 min. Fixe aussi « parole étouffée après une longue
  // intro musicale » (GRU verrouillé sur la musique).
  private static let SILENCE_RESET_RMS: Float = 0.02
  private static let SILENCE_RESET_HOLD_SEC: Float = 2.0
  private static let SILENCE_RESET_MIN_SAMPLES = 5 * 48000
  private static let GRU_RESET_FORCE_SAMPLES = 300 * 48000

  private var session: ORTSession?

  // STFT windows
  private var win = [Float](repeating: 0, count: N_WIN)
  private var awin = [Float](repeating: 0, count: N_WIN)

  // vDSP FFT setup
  private var fftSetup: FFTSetup?
  private let log2n = vDSP_Length(log2(Double(N_FFT)))

  // GRU hidden states [1, 1, 600]
  private var h1 = [Float](repeating: 0, count: GRU_HIDDEN)
  private var h2 = [Float](repeating: 0, count: GRU_HIDDEN)

  // Overlap-add buffer
  private var synthesisOverlap = [Float](repeating: 0, count: N_OVERLAP)

  // Input accumulation buffer
  private var inputBuf = [Float]()
  private var samplesSinceReset = 0
  // Peak-hold du RMS de sortie + durée de silence continu (cf. reset GRU).
  private var outPeak: Float = 0
  private var silenceSamples = 0

  // Per-frame work buffers
  private var windowed = [Float](repeating: 0, count: N_FFT)
  private var specReal = [Float](repeating: 0, count: N_BINS)
  private var specImag = [Float](repeating: 0, count: N_BINS)
  private var features = [Float](repeating: 0, count: N_BINS)
  private var maskedReal = [Float](repeating: 0, count: N_BINS)
  private var maskedImag = [Float](repeating: 0, count: N_BINS)
  private var synthesized = [Float](repeating: 0, count: N_FFT)

  // vDSP split complex buffers
  private var splitReal = [Float](repeating: 0, count: N_FFT / 2)
  private var splitImag = [Float](repeating: 0, count: N_FFT / 2)

  // Perf logging
  private var frameCount: Int64 = 0
  private var totalProcessMs: Double = 0

  public var isAvailable: Bool { session != nil }

  public init(modelPath: String) {
    setupWindows()
    fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    loadModel(path: modelPath)
  }

  deinit {
    if let setup = fftSetup {
      vDSP_destroy_fftsetup(setup)
    }
  }

  // MARK: - Setup

  private func setupWindows() {
    // sqrt(hann) window (periodic, sym=False)
    for i in 0..<Self.N_WIN {
      let hann = 0.5 * (1.0 - cos(2.0 * Double.pi * Double(i) / Double(Self.N_WIN)))
      win[i] = Float(sqrt(hann))
    }

    // Synthesis window (canonical dual for perfect reconstruction)
    awin = [Float](repeating: 0, count: Self.N_WIN)
    for k in 0..<Self.N_HOP {
      var indices = [Int]()
      var idx = k
      while idx < Self.N_WIN { indices.append(idx); idx += Self.N_HOP }
      let hVals = indices.map { win[$0] }
      let hSumSq = hVals.reduce(0.0) { $0 + $1 * $1 }
      if hSumSq > 0 {
        for (j, i) in indices.enumerated() {
          awin[i] = hVals[j] / hSumSq
        }
      }
    }
  }

  private func loadModel(path modelPath: String) {
    do {
      let env = try ORTEnv(loggingLevel: .warning)
      let opts = try ORTSessionOptions()
      try opts.setLogSeverityLevel(.warning)
      session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: opts)
      print(
        "[\(Self.TAG)] Model loaded (hop=\(Self.N_HOP), \(Float(Self.N_HOP) / Float(Self.SAMPLE_RATE) * 1000)ms)"
      )
    } catch {
      print("[\(Self.TAG)] ERROR loading model: \(error)")
    }
  }

  // MARK: - Public API

  public func reset() {
    h1 = [Float](repeating: 0, count: Self.GRU_HIDDEN)
    h2 = [Float](repeating: 0, count: Self.GRU_HIDDEN)
    synthesisOverlap = [Float](repeating: 0, count: Self.N_OVERLAP)
    inputBuf.removeAll()
    samplesSinceReset = 0
    outPeak = 0
    silenceSamples = 0
    frameCount = 0
    totalProcessMs = 0
  }

  /// Process a chunk of PCM samples at 48kHz. Returns the same number of samples.
  public func process(_ newSamples: [Float]) -> [Float] {
    let n = newSamples.count
    guard n > 0 else { return [] }

    // Reset évalué au niveau batch, comme Nsnet2Stream::MaybeResetGruStates.
    maybeResetGruStates()

    inputBuf.append(contentsOf: newSamples)

    var outputParts = [[Float]]()
    while inputBuf.count >= Self.N_WIN {
      let frame = Array(inputBuf.prefix(Self.N_WIN))
      let out = processFrame(frame)
      outputParts.append(out)
      inputBuf.removeFirst(Self.N_HOP)
      samplesSinceReset += Self.N_HOP
    }

    let produced = outputParts.flatMap { $0 }
    updateSilenceTracking(produced)

    // Pad front if needed to match input size
    if produced.count < n {
      return [Float](repeating: 0, count: n - produced.count) + produced
    }
    return produced
  }

  // MARK: - Reset GRU (port de Nsnet2Stream)

  private func maybeResetGruStates() {
    let silenceDue = silenceSamples >= Self.SILENCE_RESET_MIN_SAMPLES
    let forceDue = samplesSinceReset >= Self.GRU_RESET_FORCE_SAMPLES
    guard silenceDue || forceDue else { return }
    h1 = [Float](repeating: 0, count: Self.GRU_HIDDEN)
    h2 = [Float](repeating: 0, count: Self.GRU_HIDDEN)
    samplesSinceReset = 0
    if silenceDue {
      silenceSamples = 0
    }
  }

  /// Peak-hold du RMS de sortie : le compteur de silence n'avance que si le
  /// niveau reste sous le seuil, décroissance exponentielle de constante
  /// SILENCE_RESET_HOLD_SEC (un blanc entre deux mots ne compte donc pas).
  private func updateSilenceTracking(_ out: [Float]) {
    let n = out.count
    guard n > 0 else { return }
    var sumSq: Float = 0
    for s in out { sumSq += s * s }
    let rms = (sumSq / Float(n)).squareRoot()
    let decay = exp(-Float(n) / (Float(Self.SAMPLE_RATE) * Self.SILENCE_RESET_HOLD_SEC))
    outPeak = max(rms, outPeak * decay)
    if outPeak >= Self.SILENCE_RESET_RMS {
      silenceSamples = 0
    } else {
      silenceSamples += n
    }
  }

  // MARK: - Frame processing

  private func processFrame(_ buf: [Float]) -> [Float] {
    let t0 = CFAbsoluteTimeGetCurrent()

    // 1. Window (zero-pad to N_FFT)
    for i in 0..<Self.N_WIN { windowed[i] = buf[i] * win[i] }
    for i in Self.N_WIN..<Self.N_FFT { windowed[i] = 0 }

    // 2. RFFT via vDSP
    rfft(windowed, realOut: &specReal, imagOut: &specImag)

    // 3. Log power spectrum
    for i in 0..<Self.N_BINS {
      let power = specReal[i] * specReal[i] + specImag[i] * specImag[i]
      features[i] = Float(log10(max(Double(power), 1e-12)))
    }

    // 4. ONNX inference
    guard let session = session else {
      return Array(buf.prefix(Self.N_HOP))
    }

    do {
      let featData = Data(bytes: features, count: Self.N_BINS * MemoryLayout<Float>.size)
      let h1Data = Data(bytes: h1, count: Self.GRU_HIDDEN * MemoryLayout<Float>.size)
      let h2Data = Data(bytes: h2, count: Self.GRU_HIDDEN * MemoryLayout<Float>.size)

      let featTensor = try ORTValue(
        tensorData: NSMutableData(data: featData),
        elementType: .float,
        shape: [1, 1, NSNumber(value: Self.N_BINS)]
      )
      let h1Tensor = try ORTValue(
        tensorData: NSMutableData(data: h1Data),
        elementType: .float,
        shape: [1, 1, NSNumber(value: Self.GRU_HIDDEN)]
      )
      let h2Tensor = try ORTValue(
        tensorData: NSMutableData(data: h2Data),
        elementType: .float,
        shape: [1, 1, NSNumber(value: Self.GRU_HIDDEN)]
      )

      let outputs = try session.run(
        withInputs: [
          "input": featTensor,
          "gru1_h_in": h1Tensor,
          "gru2_h_in": h2Tensor,
        ],
        outputNames: ["output", "gru1_h_out", "gru2_h_out"],
        runOptions: nil
      )

      // Extract mask
      let maskData = try outputs["output"]!.tensorData() as Data
      maskData.withUnsafeBytes { ptr in
        let floats = ptr.bindMemory(to: Float.self)
        for i in 0..<Self.N_BINS {
          maskedReal[i] = specReal[i] * floats[i]
          maskedImag[i] = specImag[i] * floats[i]
        }
      }

      // Update GRU states
      let h1OutData = try outputs["gru1_h_out"]!.tensorData() as Data
      h1OutData.withUnsafeBytes { ptr in
        let floats = ptr.bindMemory(to: Float.self)
        for i in 0..<Self.GRU_HIDDEN { h1[i] = floats[i] }
      }
      let h2OutData = try outputs["gru2_h_out"]!.tensorData() as Data
      h2OutData.withUnsafeBytes { ptr in
        let floats = ptr.bindMemory(to: Float.self)
        for i in 0..<Self.GRU_HIDDEN { h2[i] = floats[i] }
      }
    } catch {
      print("[\(Self.TAG)] Inference error: \(error)")
      return Array(buf.prefix(Self.N_HOP))
    }

    // 6. IRFFT
    irfft(maskedReal, maskedImag, output: &synthesized)

    // 7. Synthesis window
    for i in 0..<Self.N_WIN { synthesized[i] *= awin[i] }

    // 8. Overlap-add
    for i in 0..<Self.N_OVERLAP { synthesized[i] += synthesisOverlap[i] }

    let output = Array(synthesized.prefix(Self.N_HOP))
    for i in 0..<Self.N_OVERLAP {
      synthesisOverlap[i] = synthesized[Self.N_HOP + i]
    }

    // Per-frame perf is already aggregated per-chunk via chunk_preprocess_done
    // (nsnet2_ms field) — no per-100-frames print needed.
    frameCount += 1
    totalProcessMs += (CFAbsoluteTimeGetCurrent() - t0) * 1000.0

    return output
  }

  // MARK: - FFT via vDSP

  private func rfft(_ input: [Float], realOut: inout [Float], imagOut: inout [Float]) {
    guard let setup = fftSetup else { return }

    var inputCopy = input

    splitReal.withUnsafeMutableBufferPointer { realBuf in
      splitImag.withUnsafeMutableBufferPointer { imagBuf in
        var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)

        // Pack interleaved -> split complex
        inputCopy.withUnsafeMutableBufferPointer { inBuf in
          inBuf.baseAddress!.withMemoryRebound(
            to: DSPComplex.self, capacity: Self.N_FFT / 2
          ) { complex in
            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(Self.N_FFT / 2))
          }
        }

        // Forward FFT
        vDSP_fft_zrip(setup, &split, 1, self.log2n, FFTDirection(kFFTDirection_Forward))
      }
    }

    // Unpack: bin 0 real is in splitReal[0], bin N/2 real is in splitImag[0]
    realOut[0] = splitReal[0]
    imagOut[0] = 0
    for i in 1..<Self.N_FFT / 2 {
      realOut[i] = splitReal[i]
      imagOut[i] = splitImag[i]
    }
    realOut[Self.N_FFT / 2] = splitImag[0]
    imagOut[Self.N_FFT / 2] = 0

    // vDSP returns 2x scale
    var scale: Float = 0.5
    realOut.withUnsafeMutableBufferPointer { buf in
      vDSP_vsmul(buf.baseAddress!, 1, &scale, buf.baseAddress!, 1, vDSP_Length(Self.N_BINS))
    }
    imagOut.withUnsafeMutableBufferPointer { buf in
      vDSP_vsmul(buf.baseAddress!, 1, &scale, buf.baseAddress!, 1, vDSP_Length(Self.N_BINS))
    }
  }

  private func irfft(_ inReal: [Float], _ inImag: [Float], output: inout [Float]) {
    guard let setup = fftSetup else { return }

    // Pack into split complex (vDSP format)
    splitReal[0] = inReal[0]
    splitImag[0] = inReal[Self.N_FFT / 2]
    for i in 1..<Self.N_FFT / 2 {
      splitReal[i] = inReal[i]
      splitImag[i] = inImag[i]
    }

    splitReal.withUnsafeMutableBufferPointer { realBuf in
      splitImag.withUnsafeMutableBufferPointer { imagBuf in
        var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)

        // Inverse FFT
        vDSP_fft_zrip(setup, &split, 1, self.log2n, FFTDirection(kFFTDirection_Inverse))

        // Unpack split complex -> interleaved
        output.withUnsafeMutableBufferPointer { outBuf in
          outBuf.baseAddress!.withMemoryRebound(
            to: DSPComplex.self, capacity: Self.N_FFT / 2
          ) { complex in
            vDSP_ztoc(&split, 1, complex, 2, vDSP_Length(Self.N_FFT / 2))
          }
        }
      }
    }

    // vDSP: zrip(forward) rend 2*DFT et zrip(inverse) rend N*IDFT de ce qu'on
    // lui donne — la normalisation canonique 1/(2N) suppose donc qu'on lui
    // repasse la sortie BRUTE du forward. Ici `rfft` a déjà divisé par 2 pour
    // rendre le vrai spectre (le modèle est nourri avec ça), donc le facteur 2
    // a déjà été payé : la normalisation qui reste est 1/N. Avec 1/(2N) toute
    // la sortie sortait à -6 dB (vérifié par private/tools/sawtunaa-swift-golden,
    // gain optimal mesuré 2.0000, résidu 3e-8 → l'erreur était PUREMENT
    // d'échelle, le reste du portage est exact).
    var scale = 1.0 / Float(Self.N_FFT)
    output.withUnsafeMutableBufferPointer { buf in
      vDSP_vsmul(buf.baseAddress!, 1, &scale, buf.baseAddress!, 1, vDSP_Length(Self.N_FFT))
    }
  }
}
