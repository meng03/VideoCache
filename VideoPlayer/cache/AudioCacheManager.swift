//
//  AudioCacheManager.swift
//  VideoPlayer
//
//  Created by 孟冰川 on 2018/8/10.
//  Copyright © 2018年 com.36kr. All rights reserved.
//

import AVFoundation
import MobileCoreServices

class AudioCacheError: Error {
    var errorMsg: String?
    init(msg: String) {
        errorMsg = msg
    }
}

protocol AudioCacheDelegate: AVAssetResourceLoaderDelegate {
    
    var customPrefix: String { get }
    
}

class AudioCacheManager:NSObject,URLSessionDelegate {
    
    var customPrefix = "kr36"
    var session: URLSession!
    var penddingRequest =  [ResourceLoadingRequest]()
    
    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 90
        session = URLSession.init(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    
    func startDownLoad(_ request: ResourceLoadingRequest) {        
        penddingRequest.append(request)
        //loadingRequest 转 URLRequest
        guard let redirectURL = request.loadingRequest.request.url else { return }
        guard let original = URL(string: redirectURL.absoluteString.replacingOccurrences(of: customPrefix, with: "")) else { return }
        var contentRequest = URLRequest(url: original)
        if let range = rangeValue(loadingRequest: request.loadingRequest) {
            let rangeValue = "bytes=\(range.offset)-\(range.offset + Int64(range.length) - 1)"
            contentRequest.setValue(rangeValue, forHTTPHeaderField:"Range")
            request.totalLength = range.length
            debugPrint(rangeValue)
        }
        let task = session.dataTask(with: contentRequest)
        request.dataTask = task
        debugPrint("收到代理的请求，加到队列中，启动下载,taskId: \(task.taskIdentifier)")
        task.resume()
    }
    
    //挂起请求：用于4G切换
    func suspend() {
        penddingRequest.forEach { (request) in
            request.suspend()
        }
    }
    //恢复请求：用于4G切换
    func resume() {
        penddingRequest.forEach { (request) in
            request.resume()
        }
    }
}

extension AudioCacheManager: AudioCacheDelegate {
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        if let index = penddingRequest.firstIndex(where: {$0.loadingRequest == loadingRequest}) {
            let request = penddingRequest[index]
            penddingRequest.remove(at: index)
            request.cancel()
            debugPrint("didCancelLoading: \(String(describing: request.dataTask?.taskIdentifier))")
        }
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        let request = ResourceLoadingRequest(request: loadingRequest)
        startDownLoad(request)
        return true
    }
    
}

extension AudioCacheManager:  URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let current = requestWithTaskId(taskId: dataTask.taskIdentifier),
            let response = response as? HTTPURLResponse else  {
                return
        }
        if let infoRequest = current.loadingRequest.contentInformationRequest {
            if let mimeType = response.mimeType as CFString?{
                let utType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType, nil)?.takeRetainedValue() as String?
                infoRequest.contentType = utType
                debugPrint("setContentInfo: \(utType ?? "")")
            }else {
                completionHandler(.cancel)
                return
            }
            let length = self.responseLength(response: response)
            debugPrint("setContentInfo: \(length)")
            infoRequest.contentLength = length
            let isSupported = response.allHeaderFields["Content-Range"] != nil
            debugPrint("setContentInfo: \(isSupported)")
            infoRequest.isByteRangeAccessSupported = isSupported
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if !data.isEmpty {
            if let request = requestWithTaskId(taskId: dataTask.taskIdentifier) {
                request.currentLength += data.count
                request.loadingRequest.dataRequest?.respond(with: data)
                if request.currentLength == request.totalLength {
                    request.loadingRequest.finishLoading()
                    self.penddingRequest.removeAll(where: {$0.dataTask?.taskIdentifier == dataTask.taskIdentifier})
                    debugPrint("task完成，taskId：\(dataTask.taskIdentifier)")
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error,let request = requestWithTaskId(taskId: task.taskIdentifier) {
            request.finishWithError(error: error)
            debugPrint("didCompleteWithError:\(task.taskIdentifier)")
        }
    }
    
}

//工具方法
extension AudioCacheManager {
    
    func requestWithTaskId(taskId: Int) -> ResourceLoadingRequest? {
        return self.penddingRequest.first(where: {$0.dataTask?.taskIdentifier == taskId})
    }
    
    //获取response中的数据长度
    func responseLength(response: HTTPURLResponse) -> Int64 {
        if let range = response.allHeaderFields["Content-Range"] as? String {
            let component = range.components(separatedBy: "/")
            if component.count > 0 {
                if let last = component.last, let length = Int64(last) {
                    return length
                }
            }
        }else {
            return response.expectedContentLength
        }
        return 0
    }
    //获取请求的range
    func rangeValue(loadingRequest: AVAssetResourceLoadingRequest) -> (offset: Int64,length: Int)? {
        guard let dataRequest = loadingRequest.dataRequest else { return nil }
        return (dataRequest.requestedOffset,dataRequest.requestedLength)
    }
}
