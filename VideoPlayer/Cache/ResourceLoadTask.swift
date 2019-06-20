//
//  SyncCache.swift
//  Client
//
//  Created by 孟冰川 on 2019/6/10.
//  Copyright © 2019 36Kr. All rights reserved.
//

import Foundation
import AVFoundation

//维护一个请求数组
//数组中有两种任务，加载本地缓存任务，下载任务
//顺序执行，完成即respond通知avplayer
//一个AVAssetResourceLoadingRequest 对应一个
class ResourceLoadTask: NSObject {

    var origin: AVAssetResourceLoadingRequest
    var cacheFile: CacheFile
    var rangedRequests = [RangedRequest]()
    
    var isFinished = false
    
    init(request: AVAssetResourceLoadingRequest,cacheFile: CacheFile) {
        self.origin = request
        self.cacheFile = cacheFile
        super.init()
        if let ranges = cacheFile.ranges {
            if let dataRequest = request.dataRequest {
                var range: AVRange
                if dataRequest.requestsAllDataToEndOfResource {
                    range = AVRange(location: dataRequest.requestedOffset, length: cacheFile.info!.contentLength - dataRequest.requestedOffset)
                }else {
                    range = AVRange(location: dataRequest.requestedOffset, length: Int64(dataRequest.requestedLength))
                }
                checkCache(range,exists: ranges)
            }else {
                //TODO: - 如果没有DataRequest，填充info，完成，不知道什么时候会发生，可以观察下
                debugPrint("resourceLoader 没有dataTask的情况，直接fillContentinfo")
                fillContentInfo(request: request)
                request.finishLoading()
            }
        }else {
            debugPrint("resourceLoader 没有缓存，直接构建一个webrequest")
            appendWebRequest(nil)
        }
    }
    
    func suspend() {
        rangedRequests.first(where: {$0.state == .start})?.suspend()
    }
    func resume() {
        rangedRequests.first(where: {$0.state == .suspend})?.resume()
    }
    
    func cancel() {
        rangedRequests.forEach { (request) in
            request.state = .cancel
        }
    }
    
    func startRequest() {
        //考虑内存问题，这里采用顺序处理，处理一块，respond一块
        debugPrint("resourceLoader 任务开始,thread: \(Thread.current)")
        rangedRequests.first?.startLoad(completion: {[weak self] in
            self?.origin.finishLoading()
            self?.isFinished = true
            debugPrint("resourceLoader 任务结束")
        })
    }
    
    func checkCache(_ range: AVRange,exists: [AVRange]){
        //起点相关块，包含起点，或者在起点后
        //终点相关块，包含终点，或者在终点前
        debugPrint("resourceLoader -----分析任务，生成request start------")
        debugPrint("resourceLoader expectRange: \(range)")
        debugPrint("resourceLoader exists: \(exists)")
        guard let startRelativeRange = exists.first(where: {range.location < $0.endOffset}),
            let endRelativeRange = exists.reversed().first(where: {range.endOffset > $0.location }) else {
                //没有起点块，意味着在所有缓存的后面
                //没有终点块，意味着在所有的缓存前面
                //这两种情况都是未命中的
                debugPrint("resourceLoader 缓存未命中，在前后")
                appendWebRequest(range)
                return
        }
        //起点块和终点块不是一个，且终点块在起点块之前，也是未命中
        if !startRelativeRange.isEqual(other: endRelativeRange) && startRelativeRange.location > endRelativeRange.endOffset {
            debugPrint("resourceLoader 缓存未命中，中间")
            appendWebRequest(range)
            return
        }
        //缓存块在数组中的位置,必定存在，所以这里使用强解包
        var startDataIndex = exists.firstIndex(where: {$0.isEqual(other: startRelativeRange)})!
        let endDataIndex = exists.firstIndex(where: {$0.isEqual(other: endRelativeRange)})!
        
        var offset = range.location
        let end = range.endOffset
        while offset < end && startDataIndex <= endDataIndex {
            let startDataRange = exists[startDataIndex]
            var tempEnd: Int64 = offset
            var local = false
            if offset < startDataRange.location {
                local = false
                tempEnd = startDataRange.location
            }else {
                local = true
                tempEnd = startDataRange.endOffset
            }
            tempEnd = min(tempEnd,end)
            let length = Int(tempEnd - offset)
            if local {
                appendLocalRequest(localCacheRange: startDataRange, expectRange: AVRange(location: offset, length: Int64(length)))
                startDataIndex += 1
            }else {
                appendWebRequest(AVRange(location: offset, length: Int64(length)))
            }
            //更新cursor
            offset = tempEnd
            
        }
        
        debugPrint("resourceLoader result:\(rangedRequests))")
        debugPrint("resourceLoader -----checkCahce end-------")
    }
    
    func fillContentInfo(request: AVAssetResourceLoadingRequest) {
        if let info = cacheFile.info {
            request.contentInformationRequest?.contentLength = info.contentLength
            request.contentInformationRequest?.isByteRangeAccessSupported = info.isByteRangeAccessSupported
            request.contentInformationRequest?.contentType = info.utType
        }
    }
    
    
    func rangeValue(loadingRequest: AVAssetResourceLoadingRequest) -> (offset: Int64,length: Int)? {
        guard let dataRequest = loadingRequest.dataRequest else { return nil }
        return (dataRequest.requestedOffset,dataRequest.requestedLength)
    }
    
    //添加request
    func appendWebRequest(_ range: AVRange?) {
        let request = RangedWebRequest(range: range,origin: origin,cacheFile: cacheFile)
        appendRequest(request: request)
    }
    
    func appendLocalRequest(localCacheRange: AVRange,expectRange: AVRange) {
        let request = RangedLocalRequest(origin: origin,localCacheRange: localCacheRange, expectRange: expectRange,cacheFile: cacheFile)
        appendRequest(request: request)
    }
    
    func appendRequest(request: RangedRequest) {
        rangedRequests.last?.next = request
        rangedRequests.append(request)
    }
    
}

extension ResourceLoadTask: RangedRequestDelegate {
    func rangedRequestError(request: RangedRequest, error: AVPlayerCacheError) {
        origin.finishLoading(with: NSError(domain: error.desc, code: -1, userInfo: nil))
    }
}

struct AVPlayerCacheError: Error {
    var desc: String
}
