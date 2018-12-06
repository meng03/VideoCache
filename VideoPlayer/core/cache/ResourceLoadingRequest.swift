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
    
    func stop() {
        //4G环境停止下载
        dataTask?.cancel()
        loadingRequest.finishLoading(with: nil)
    }
}
