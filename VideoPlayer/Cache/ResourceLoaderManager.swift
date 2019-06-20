//
//  ResourceLoader.swift
//  Client
//
//  Created by 孟冰川 on 2019/6/15.
//  Copyright © 2019 36Kr. All rights reserved.
//

import Foundation
import AVFoundation

let ResourceLoaderPrefix = "resourceLoaderPrefix"

protocol AudioCacheDelegate: AVAssetResourceLoaderDelegate {
    
    var customPrefix: String { get }
    
    //挂起请求：用于4G切换
    func suspend()
    
    //恢复请求：用于4G切换
    func resume()
    
    func setup(url: String)
    
}

/// 根据AVPlayer的请求，构建task
/// 管理task队列
/// 一个视频url对应一个
class ResourceLoaderManager: NSObject {
    
    var url: String!
    
    //缓存的文件信息
    var cacheFile: CacheFile!
    
    var tasks: [ResourceLoadTask] = []
    
    let serialQueue = DispatchQueue(label: "resourceLoader")
    
}

extension ResourceLoaderManager: AudioCacheDelegate {
    
    var customPrefix: String {
        return ResourceLoaderPrefix
    }
    
    func setup(url: String) {
        self.url = url
        self.cacheFile = CacheFile.setup(url: url)
    }
    
    
    //挂起请求：用于4G切换
    func suspend() {
        tasks.forEach { (task) in
            task.suspend()
        }
    }
    //恢复请求：用于4G切换
    func resume() {
        tasks.forEach { (task) in
            task.resume()
        }
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        tasks.removeAll(where: {$0.isFinished})
        if let index = tasks.firstIndex(where: {$0.origin == loadingRequest}) {
            let task = tasks[index]
            tasks.remove(at: index)
            task.cancel()
        }
        debugPrint("resourceLoader didCancel,requestCount: \(tasks.count)")
    }
    
    //起点，接收AVplayer的请求
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        tasks.removeAll(where: {$0.isFinished})
        let task = ResourceLoadTask(request: loadingRequest, cacheFile: cacheFile)
        tasks.append(task)
        task.startRequest()
        debugPrint("resourceLoader add request,requestCount: \(tasks.count)")
        return true
    }
    
}

