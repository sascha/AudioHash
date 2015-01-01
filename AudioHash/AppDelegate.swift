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

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        let originalSoundFileURL = NSBundle.mainBundle().URLForResource("siren-original", withExtension: "wav")
        let recordedSoundFileURL = NSBundle.mainBundle().URLForResource("siren-recording", withExtension: "wav")
        
        var originalFileRef = ExtAudioFileRef()
        ExtAudioFileOpenURL(originalSoundFileURL, &originalFileRef)
        
        var recordedFileRef = ExtAudioFileRef()
        ExtAudioFileOpenURL(recordedSoundFileURL, &recordedFileRef)

        let originalFileSampling = sampling(originalFileRef)
        let recordedFileSampling = sampling(recordedFileRef)
        
        let originalFingerprint = fingerprint(originalFileSampling)
        let recordedFingerprint = fingerprint(recordedFileSampling)

        debugPrintln(originalFingerprint)
        
        if originalFingerprint.isEqualTo(recordedFingerprint) {
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

