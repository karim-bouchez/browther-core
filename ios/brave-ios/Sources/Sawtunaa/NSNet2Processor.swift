// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Accelerate
import Foundation
import onnxruntime_objc

/// NSNet2 stateful processor — port Swift de `Nsnet2Stream` (macOS, C++), qui
/// est lui-même le port du moteur Python de référence.
///
/// STFT → log power → inférence ONNX (masque de gain) → iSTFT + overlap-add.
/// L'état GRU est conservé d'une frame à l'autre (streaming).
///
/// **Stéréo** : un seul masque par frame, calculé sur le **downmix des
/// spectres** (linéarité de la STFT — donc une seule inférence, le coût ne
/// double pas), puis appliqué **à chaque canal séparément**. C'est ce qui
/// préserve la scène stéréo, exactement comme macOS. Le downmix mono d'avant
/// l'aplatissait sur toutes les vidéos.
///
/// Parité numérique avec la référence Python vérifiée par
/// `private/tools/sawtunaa-swift-golden/run.sh` (~5 s, sans device).
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

  /// 1 ou 2. En production iOS c'est 2 ; 1 sert au harness golden (les vecteurs
  /// de référence sont mono) et au cas où une source n'aurait qu'un canal.
  public let channels: Int

  // STFT windows
  private var win = [Float](repeating: 0, count: N_WIN)
  private var awin = [Float](repeating: 0, count: N_WIN)

  // vDSP FFT setup
  private var fftSetup: FFTSetup?
  private let log2n = vDSP_Length(log2(Double(N_FFT)))

  // GRU hidden states [1, 1, 600]
  private var h1 = [Float](repeating: 0, count: GRU_HIDDEN)
  private var h2 = [Float](repeating: 0, count: GRU_HIDDEN)

  // Overlap-add buffers (un par canal)
  private var overlapL = [Float](repeating: 0, count: N_OVERLAP)
  private var overlapR = [Float](repeating: 0, count: N_OVERLAP)

  // Input accumulation buffers (un par canal)
  private var inputL = [Float]()
  private var inputR = [Float]()
  private var samplesSinceReset = 0
  // Peak-hold du RMS de sortie + durée de silence continu (cf. reset GRU).
  private var outPeak: Float = 0
  private var silenceSamples = 0

  // Per-frame work buffers
  private var windowed = [Float](repeating: 0, count: N_FFT)
  private var specLRe = [Float](repeating: 0, count: N_BINS)
  private var specLIm = [Float](repeating: 0, count: N_BINS)
  private var specRRe = [Float](repeating: 0, count: N_BINS)
  private var specRIm = [Float](repeating: 0, count: N_BINS)
  private var features = [Float](repeating: 0, count: N_BINS)
  private var maskedRe = [Float](repeating: 0, count: N_BINS)
  private var maskedIm = [Float](repeating: 0, count: N_BINS)
  private var synthesized = [Float](repeating: 0, count: N_FFT)

  // vDSP split complex buffers
  private var splitReal = [Float](repeating: 0, count: N_FFT / 2)
  private var splitImag = [Float](repeating: 0, count: N_FFT / 2)

  // Perf logging
  private var frameCount: Int64 = 0
  private var totalProcessMs: Double = 0

  public var isAvailable: Bool { session != nil }

  public init(modelPath: String, channels: Int = 2) {
    self.channels = (channels == 2) ? 2 : 1
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
        "[\(Self.TAG)] Model loaded (hop=\(Self.N_HOP), \(Float(Self.N_HOP) / Float(Self.SAMPLE_RATE) * 1000)ms, channels=\(channels))"
      )
    } catch {
      print("[\(Self.TAG)] ERROR loading model: \(error)")
    }
  }

  // MARK: - Public API

  public func reset() {
    h1 = [Float](repeating: 0, count: Self.GRU_HIDDEN)
    h2 = [Float](repeating: 0, count: Self.GRU_HIDDEN)
    overlapL = [Float](repeating: 0, count: Self.N_OVERLAP)
    overlapR = [Float](repeating: 0, count: Self.N_OVERLAP)
    inputL.removeAll()
    inputR.removeAll()
    samplesSinceReset = 0
    outPeak = 0
    silenceSamples = 0
    frameCount = 0
    totalProcessMs = 0
  }

  /// Traite un bloc de PCM 48 kHz en **planar** (tous les samples du canal
  /// gauche, puis tous ceux du canal droit si `channels == 2`) et rend la
  /// sortie dans le même format.
  ///
  /// ⚠️ La sortie fait **moins** de samples que l'entrée tant que la fenêtre
  /// d'analyse n'est pas remplie (jusqu'à 959 au tout premier bloc), puis
  /// oscille autour de la taille demandée : c'est la latence STFT, et c'est
  /// exactement ce que fait `Nsnet2Stream`. Sur la durée, sortie totale ==
  /// entrée totale. L'ancienne version comblait la différence par des zéros
  /// **en tête**, ce qui injectait un silence dont la longueur dépendait de la
  /// taille du bloc — donc un décalage AV variable après chaque seek.
  public func process(_ planar: [Float]) -> [Float] {
    let n = planar.count / channels
    guard n > 0 else { return [] }

    // Reset évalué au niveau du bloc, comme Nsnet2Stream::MaybeResetGruStates.
    maybeResetGruStates()

    inputL.append(contentsOf: planar[0..<n])
    if channels == 2 {
      inputR.append(contentsOf: planar[n..<(2 * n)])
    }

    var outL = [Float]()
    var outR = [Float]()
    outL.reserveCapacity(n)
    while inputL.count >= Self.N_WIN {
      processFrame(outL: &outL, outR: &outR)
      inputL.removeFirst(Self.N_HOP)
      if channels == 2 {
        inputR.removeFirst(Self.N_HOP)
      }
      samplesSinceReset += Self.N_HOP
    }

    updateSilenceTracking(outL, outR)
    return channels == 2 ? outL + outR : outL
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
  private func updateSilenceTracking(_ outL: [Float], _ outR: [Float]) {
    let n = outL.count
    guard n > 0 else { return }
    var sumSq: Float = 0
    if channels == 2 && outR.count == n {
      for i in 0..<n {
        let s = 0.5 * (outL[i] + outR[i])
        sumSq += s * s
      }
    } else {
      for s in outL { sumSq += s * s }
    }
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

  private func processFrame(outL: inout [Float], outR: inout [Float]) {
    let t0 = CFAbsoluteTimeGetCurrent()

    // 1-2. Fenêtre d'analyse (zero-pad à N_FFT) + RFFT, par canal.
    analyze(inputL, into: &specLRe, &specLIm)
    if channels == 2 {
      analyze(inputR, into: &specRRe, &specRIm)
    }

    // 3. Features log-power sur le spectre du DOWNMIX (moyenne des spectres —
    // linéarité de la STFT, donc une seule inférence par frame).
    for i in 0..<Self.N_BINS {
      var re = specLRe[i]
      var im = specLIm[i]
      if channels == 2 {
        re = 0.5 * (re + specRRe[i])
        im = 0.5 * (im + specRIm[i])
      }
      let power = re * re + im * im
      features[i] = Float(log10(max(Double(power), 1e-12)))
    }

    // 4. Inférence ONNX
    guard let session = session else {
      // Passthrough : rendre l'entrée telle quelle plutôt que du silence.
      outL.append(contentsOf: inputL.prefix(Self.N_HOP))
      if channels == 2 {
        outR.append(contentsOf: inputR.prefix(Self.N_HOP))
      }
      return
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

      // 5. Masque appliqué à CHAQUE canal (le masque, lui, est commun).
      let maskData = try outputs["output"]!.tensorData() as Data
      maskData.withUnsafeBytes { ptr in
        let mask = ptr.bindMemory(to: Float.self)
        for i in 0..<Self.N_BINS {
          maskedRe[i] = specLRe[i] * mask[i]
          maskedIm[i] = specLIm[i] * mask[i]
        }
        synthesize(&overlapL, into: &outL)
        if channels == 2 {
          for i in 0..<Self.N_BINS {
            maskedRe[i] = specRRe[i] * mask[i]
            maskedIm[i] = specRIm[i] * mask[i]
          }
          synthesize(&overlapR, into: &outR)
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
      outL.append(contentsOf: inputL.prefix(Self.N_HOP))
      if channels == 2 {
        outR.append(contentsOf: inputR.prefix(Self.N_HOP))
      }
      return
    }

    // Per-frame perf is already aggregated per-chunk via chunk_preprocess_done
    // (nsnet2_ms field) — no per-100-frames print needed.
    frameCount += 1
    totalProcessMs += (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
  }

  /// Fenêtre d'analyse + RFFT des N_WIN premiers samples de `input`.
  private func analyze(_ input: [Float], into re: inout [Float], _ im: inout [Float]) {
    for i in 0..<Self.N_WIN { windowed[i] = input[i] * win[i] }
    for i in Self.N_WIN..<Self.N_FFT { windowed[i] = 0 }
    rfft(windowed, realOut: &re, imagOut: &im)
  }

  /// iRFFT de `maskedRe`/`maskedIm` + fenêtre de synthèse + overlap-add.
  /// Ajoute N_HOP samples à `out` et met à jour la queue `overlap`.
  private func synthesize(_ overlap: inout [Float], into out: inout [Float]) {
    irfft(maskedRe, maskedIm, output: &synthesized)
    for i in 0..<Self.N_WIN { synthesized[i] *= awin[i] }
    for i in 0..<Self.N_OVERLAP { synthesized[i] += overlap[i] }
    out.append(contentsOf: synthesized.prefix(Self.N_HOP))
    for i in 0..<Self.N_OVERLAP {
      overlap[i] = synthesized[Self.N_HOP + i]
    }
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
    // a déjà été payé : la normalisation qui reste est 1/N — c'est aussi le
    // `kInvN` de Nsnet2Stream. Avec 1/(2N) toute la sortie sortait à -6 dB
    // (vérifié par private/tools/sawtunaa-swift-golden, gain optimal mesuré
    // 2.0000, résidu 3e-8 → l'erreur était PUREMENT d'échelle, le reste du
    // portage est exact).
    var scale = 1.0 / Float(Self.N_FFT)
    output.withUnsafeMutableBufferPointer { buf in
      vDSP_vsmul(buf.baseAddress!, 1, &scale, buf.baseAddress!, 1, vDSP_Length(Self.N_FFT))
    }
  }
}
