//
//  ResourceLoadingRequest.swift
//  VideoPlayer
//
//  Created by 孟冰川 on 2018/8/10.
//  Copyright © 2018年 com.36kr. All rights reserved.
//

import AVFoundation

class ResourceLoadingRequest {
    
    var loadingRequest: AVAssetResourceLoadingRequest
    var dataTask: URLSessionDataTask?
    var currentLength = 0
    var totalLength = 0
    
    init(request: AVAssetResourceLoadingRequest) {
        self.loadingRequest = request
    }
    
    func cancel() {
        //loadingRequest被cancel掉，也停掉dataTask
        dataTask?.cancel()
    }
    
    func finishWithError(error: Error?) {
        if isRequestRuning() {
            loadingRequest.finishLoading(with: error)
        }
        dataTask?.cancel()
    }
    
    //网络切换,停止下载
    func suspend() {
        //4G环境停止下载
        if let state = dataTask?.state ,state == .running {
            dataTask?.suspend()
        }
    }
    //恢复下载
    func resume() {
        if !isRequestRuning() { return }
        if let state = dataTask?.state ,state == .suspended {
            dataTask?.resume()
        }
    }
    
    func isRequestRuning() -> Bool {
        if loadingRequest.isCancelled || loadingRequest.isFinished {
            return false
        }else {
            return true
        }
    }
}
