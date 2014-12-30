//
//  AppDelegate.swift
//  AudioHash
//
//  Created by Sascha Schwabbauer on 28/12/14.
//  Copyright (c) 2014 evolved.io. All rights reserved.
//

import UIKit
import AudioToolbox

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    func sampling(audioFile: ExtAudioFileRef) -> Sampling {
        let sampleRate: Float64 = 5536
        let formatID = AudioFormatID(kAudioFormatLinearPCM)
        let formatFlags = AudioFormatFlags(kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved)
        let bitsPerChannel = UInt32(sizeof(Float32)) * 8
        let channelsPerFrame: UInt32 = 1
        let bytesPerFrame = channelsPerFrame * UInt32(sizeof(Float32))
        let framesPerPacket: UInt32 = 1
        let bytesPerPacket = framesPerPacket * bytesPerFrame

        var audioFormat = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: formatID, mFormatFlags: formatFlags, mBytesPerPacket: bytesPerPacket, mFramesPerPacket: framesPerPacket, mBytesPerFrame: bytesPerFrame, mChannelsPerFrame: channelsPerFrame, mBitsPerChannel: bitsPerChannel, mReserved: 0)
        
        ExtAudioFileSetProperty(audioFile, ExtAudioFilePropertyID(kExtAudioFileProperty_ClientDataFormat), UInt32(sizeof(AudioStreamBasicDescription)), &audioFormat)
        
        var numberOfFrames: UInt32 = 10000
        var data = [Float32](count: Int(numberOfFrames), repeatedValue: 0)
        
        let audioBuffer = AudioBuffer(mNumberChannels: 1, mDataByteSize: numberOfFrames * UInt32(sizeof(Float32)), mData: &data)
        var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
        
        var samples = Sampling()
        
        while (numberOfFrames > 0) {
            withUnsafeMutablePointer(&audioBufferList) { ExtAudioFileRead(audioFile, &numberOfFrames, $0) }
            let floatBuffer = UnsafePointer<Float32>(audioBuffer.mData)
            let newSamples = (0 ..< numberOfFrames).map { floatBuffer[Int($0)] }
            samples += newSamples
        }
        
        return samples
    }
    
    func printFingerprint(fingerprint: Fingerprint) {
        for subfingerprint in fingerprint {
            for k in stride(from: sizeof(subfingerprint.dynamicType) * 8 - 1, through: 0, by: -1) {
                let test = pow(Float(2), Float(k))
                let bit = subfingerprint & UInt32(test)
                print("\(bit == 0 ? 0 : 1)")
            }
            println()
        }
    }
    
    func checkForEqualityOfRecordings(fingerprint1: Fingerprint, fingerprint2: Fingerprint, threshold: Float = 0.35, blockSize:Int = 256) -> Bool {
        for i in 0 ..< (fingerprint1.count - blockSize) {
            for j in 0 ..< (fingerprint2.count - blockSize) {
                let ber = bitErrorRateForBlocks(fingerprint1[i ..< (i + blockSize)], block2: fingerprint2[j ..< (j + blockSize)])
                if ber <= threshold {
                    return true
                }
            }
        }
        
        return false
    }
    
    // TODO: Implement better hamming weight algorithm
    func numberOfSetBits(var subfingerprint: UInt32) -> Int {
        var count = 0
        while subfingerprint > 0 {
            if (subfingerprint & 1) == 1 {
                count++
            }
            
            subfingerprint >>= 1
        }
        
        return count
    }
    
    func bitErrorRateForBlocks(block1: Slice<UInt32>, block2: Slice<UInt32>) -> Float {
        let totalNumberOfOneBits = reduce((0 ..< block1.count), 0) { initial, i in
            let xorHash = block1[i] ^ block2[i]
            return initial + self.numberOfSetBits(xorHash)
        }
                
        return Float(totalNumberOfOneBits / (sizeof(UInt32) * 8 * block1.count))
    }

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        let originalSoundFileURL = NSBundle.mainBundle().URLForResource("sirene-original", withExtension: "wav")
        let recordedSoundFileURL = NSBundle.mainBundle().URLForResource("sirene-aufnahme", withExtension: "wav")
        
        var originalFileRef = ExtAudioFileRef()
        ExtAudioFileOpenURL(originalSoundFileURL, &originalFileRef)
        
        var recordedFileRef = ExtAudioFileRef()
        ExtAudioFileOpenURL(recordedSoundFileURL, &recordedFileRef)

        let originalFileSampling = sampling(originalFileRef)
        let recordedFileSampling = sampling(recordedFileRef)
        
        let originalFingerprint = fingerprint(originalFileSampling, 5536)
        let recordedFingerprint = fingerprint(recordedFileSampling, 5536)

        printFingerprint(originalFingerprint)
        
        let equal = checkForEqualityOfRecordings(originalFingerprint, fingerprint2: recordedFingerprint)
        
        if equal {
            println("Recordings are equal")
        } else {
            println("Recordings are not equal")
        }
        
        return true
    }

    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

