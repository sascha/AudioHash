//
//  AudioHash.swift
//  AudioHash
//
//  Created by Sascha Schwabbauer on 28/12/14.
//  Copyright (c) 2014 evolved.io. All rights reserved.
//

import Foundation
import Accelerate

typealias Sampling = [Float]

struct Fingerprint: Printable, DebugPrintable, SequenceType {
    private let subfingerprints: [UInt32]
    
    var size: Int {
        return subfingerprints.count
    }
    
    subscript (index: Int) -> UInt32 {
        return subfingerprints[index]
    }
    
    subscript (subRange: Range<Int>) -> Slice<UInt32> {
        return subfingerprints[subRange]
    }
    
    // MARK: - Helpers
    
    private func bitErrorRateForBlocks(block1: Slice<UInt32>, block2: Slice<UInt32>) -> Float {
        let totalNumberOfOneBits = reduce((0 ..< block1.count), 0) { initial, i in
            let xorHash = block1[i] ^ block2[i]
            return initial + Int(self.numberOfSetBits(xorHash))
        }
        
        return Float(totalNumberOfOneBits / (sizeof(UInt32) * 8 * block1.count))
    }
    
    private func numberOfSetBits(var subfingerprint: UInt32) -> UInt32 {
        let masks: [UInt32] = [
            0b01010101010101010101010101010101,
            0b00110011001100110011001100110011,
            0b00001111000011110000111100001111,
            0b00000000111111110000000011111111,
            0b00000000000000001111111111111111
        ]
        
        for var i = 0, shift = UInt32(1); i < 5; i++, shift *= 2 {
            subfingerprint = (subfingerprint & masks[i]) + ((subfingerprint >> shift) & masks[i])
        }
        
        return subfingerprint
    }
    
    // MARK: - Public API
    
    func isEqualTo(otherFingerprint: Fingerprint, bitErrorRate: Float = 0.35, blockSize: UInt = 256) -> Bool {
        for i in 0 ..< (subfingerprints.count - Int(blockSize)) {
            for j in 0 ..< (otherFingerprint.subfingerprints.count - Int(blockSize)) {
                let ber = bitErrorRateForBlocks(subfingerprints[i ..< (i + Int(blockSize))], block2: otherFingerprint.subfingerprints[j ..< (j + Int(blockSize))])
                if ber <= bitErrorRate {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Printable
    
    var description: String {
        return "Fingerprint with \(subfingerprints.count) subfingerprints"
    }
    
    // MARK: - DebugPrintable
    
    var debugDescription: String {
        var description = ""
        for subfingerprint in subfingerprints {
            for k in stride(from: sizeof(subfingerprint.dynamicType) * 8 - 1, through: 0, by: -1) {
                let test = pow(Float(2), Float(k))
                let bit = subfingerprint & UInt32(test)
                description += "\(bit == 0 ? 0 : 1)"
            }
            description += "\n"
        }
        
        return description
    }
    
    // MARK: - SequenceType
    
    func generate() -> IndexingGenerator<[UInt32]> {
        return subfingerprints.generate()
    }
}

/**
Converts frequencies (Hz) into Bark.

:param: frequency The frequency (Hz) that needs to be converted into Bark.

:returns: The Bark value of the passed frequency.
*/
func hz2bark(frequency: Float) -> Float {
    return 13 * atan(0.00076 * frequency) + 3.5 * atan(pow(frequency / 7500, 2))
}

/**
Generate a matrix of weights to combine FFT bins into Bark bins.

:param: numberOfSamples  The number of samples in the source FFT.
:param: samplingRate     The sampling rate that was used to retrieve the samples.
:param: numberOfFilters  The number of output bands required.
:param: barkWidth        The constant width of each band in Bark.
:param: minimumFrequency The smallest frequency to take into account.
:param: maximumFrequency The biggest frequency to take into account.

:returns: A matrix of weights with `numberOfFilters` rows and `numberOfSamples / 2` columsn.
*/
func fft2bark(numberOfSamples: Int, samplingRate: Int, var numberOfFilters: Int = 0, barkWidth: Float = 1, minimumFrequency: Float, maximumFrequency: Float) -> [[Float]] {
    let minBark = hz2bark(minimumFrequency)
    let barkDifference = hz2bark(maximumFrequency) - minBark
    
    if numberOfFilters == 0 {
        numberOfFilters = 1
    }
    
    // Bark per filter
    let barkSpacing = barkDifference / (Float(numberOfFilters) - 1)
    let binBarks = (0...(numberOfSamples / 2)).map { hz2bark(Float($0 * samplingRate / numberOfSamples)) }
    
    let wts = (0..<numberOfFilters).map { (i: Int) -> [Float] in
        let midBark = minBark + Float(i) * barkSpacing
        return (0...(numberOfSamples / 2)).map { j in
            let lowerBarkBounds = binBarks[j] - midBark - 0.5
            let upperBarkBounds = binBarks[j] - midBark + 0.5
            
            return powf(10, (min(0, min(upperBarkBounds, -2.5 * lowerBarkBounds) / barkWidth)))
        }
    }
    
    return wts
}

/**
Generates a hash for the given sampling.

:param: input        The sampling to generate the audio hash from.
:param: samplingRate The sampling rate that was used to gather the sampling (5536 Hz is recommended).

:returns: The generated hash.
*/
func fingerprint(input: Sampling, samplingRate: Int = 5536) -> Fingerprint {
    let numberOfFilters = 33
    let frameLength = 2048
    let overlap = 31 * frameLength / 32
    let advance = frameLength - overlap
    let numberOfSubfingerprints = input.count / advance - frameLength / advance + 1
    
    let hanningWindow = hanning(frameLength)
    let wts = fft2bark(frameLength, samplingRate, numberOfFilters: numberOfFilters, barkWidth: 1.06, 300, 2000)
    
    var index = 0
    var start = 0
    var end = start + frameLength
    let fftSetup = createFFTSetup(frameLength)
    var previousBarks = [Float](count: numberOfFilters, repeatedValue: 0)
    var subfingerprints = [UInt32](count: numberOfSubfingerprints, repeatedValue: 0)
    
    while end < input.count {
        let workingSamples = input[start..<end]
        let windowedWorkingSamples = multiply(workingSamples, hanningWindow)
        let transformedWorkingSamples = fft(fftSetup, windowedWorkingSamples)
        let magnitudedWorkingSamples = abs(transformedWorkingSamples, frameLength)
        
        let currentBarks = (0..<numberOfFilters).map { (i: Int) -> Float in
            return reduce(0 ..< frameLength / 2, 0) { initial, j in
                return initial + wts[i][j] * magnitudedWorkingSamples[j]
            }
        }
        
        let currentHash = reduce(0 ..< numberOfFilters - 1, UInt32(0)) { initial, m in
            let value = currentBarks[m] - currentBarks[m + 1] - (previousBarks[m] - previousBarks[m + 1])
            var currentHash = initial << 1
            
            if value > 0 {
                currentHash |= 0x1
            }
            
            return currentHash
        }
        
        subfingerprints[index] = currentHash
        previousBarks = currentBarks
        
        index += 1
        start += advance
        end += advance
    }
    
    vDSP_destroy_fftsetup(fftSetup)
    return Fingerprint(subfingerprints: subfingerprints)
}

// MARK: - Accelerate Framework Wrappers

func hanning(length: Int) -> [Float] {
    var hanningWindow = [Float](count: length, repeatedValue: 0)
    vDSP_hann_window( &hanningWindow, vDSP_Length(hanningWindow.count), 0 )
    return hanningWindow
}

func multiply(input1: Slice<Float>, input2: [Float]) -> [Float] {
    var output = [Float](count: min(input1.count, input2.count), repeatedValue: 0)
    vDSP_vmul(input1.withUnsafeBufferPointer { $0.baseAddress }, 1, input2, 1, &output, 1, vDSP_Length(output.count))
    return output
}

func createFFTSetup(length: Int) -> FFTSetup {
    return vDSP_create_fftsetup( vDSP_Length(log2(Double(length))), FFTRadix(kFFTRadix2) )
}

func fft(setup: FFTSetup, input: [Float]) -> DSPSplitComplex {
    var real = [Float](count: input.count / 2, repeatedValue: 0)
    var imag = [Float](count: input.count / 2, repeatedValue: 0)
    var dspSplitComplex = DSPSplitComplex(realp: &real, imagp: &imag)
    
    var inputAsComplex = UnsafePointer<DSPComplex>(input.withUnsafeBufferPointer { $0.baseAddress })
    vDSP_ctoz(inputAsComplex, 2, &dspSplitComplex, 1, vDSP_Length(real.count))
    vDSP_fft_zrip(setup, &dspSplitComplex, 1, vDSP_Length(log2(Double(input.count))), FFTDirection(kFFTDirection_Forward) )
    
    return dspSplitComplex
}

func abs(var input: DSPSplitComplex, length: Int) -> [Float] {
    var result = [Float](count: length, repeatedValue: 0)
    vDSP_zvabs(&input, 1, &result, 1, vDSP_Length(length))
    return result
}
