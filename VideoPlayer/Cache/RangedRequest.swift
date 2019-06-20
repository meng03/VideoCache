//
//  PlistManager.swift
//  Client
//
//  Created by 孟冰川 on 2019/6/17.
//  Copyright © 2019 36Kr. All rights reserved.
//

import Foundation
import AVFoundation
import MobileCoreServices

protocol RangedRequestDelegate: class {
    func rangedRequestError(request: RangedRequest,error: AVPlayerCacheError)
}

typealias RangedRequestCompletion = () -> Void

enum RangedRequestState {
    case initial
    case start
    case suspend
    case finish
    case cancel
    case error
}

class RangedRequest: NSObject {
    
    //出错了通知task，提前结束
    weak var delegate: RangedRequestDelegate?
    var next: RangedRequest?
    var origin: AVAssetResourceLoadingRequest!
    
    var cacheFile: CacheFile!
    
    var state: RangedRequestState = .initial
    
    //需要请求的range
    var range = AVRange()
    
    var isLocal: Bool {
        return false
    }
    
    var data: Data?
    
    //这个block在最后一个request结束时调用
    var completionBlock: RangedRequestCompletion?
    
    func startLoad(completion: RangedRequestCompletion?) {
        if state != .initial { return }
        self.completionBlock = completion
        loadImpl()
        state = .start
    }
    
    func finishLoad(with error: AVPlayerCacheError?) {
        if let error = error {
            state = .error
            delegate?.rangedRequestError(request: self, error: error)
            return
        }
        //没有下一个了，就执行block通知任务完成
        if let next = next {
            next.startLoad(completion: completionBlock)
        }else {
            completionBlock?()
        }
        state = .finish
    }
    
    override var description: String {
        return "|\(range),\(isLocal ? "cache" : "web")|"
    }
    
    func loadImpl() {
        //子类实现
    }
    
    func suspend() {
        //子类实现
    }
    func resume() {
        //子类实现
    }
}

class RangedLocalRequest: RangedRequest {
    
    var localCacheRange: AVRange
    
    override var isLocal: Bool {
        return true
    }
    
    init(origin: AVAssetResourceLoadingRequest,localCacheRange: AVRange,expectRange: AVRange,cacheFile: CacheFile) {
        self.localCacheRange = localCacheRange
        super.init()
        self.origin = origin
        self.cacheFile = cacheFile
        self.range = expectRange
    }
    
    override func loadImpl() {
        let start = Date().timeIntervalSince1970
        debugPrint("resourceLoader 加载本地缓存，range: \(range)，\(Thread.current)")
        if let data = cacheFile.read(range: range,localRange: localCacheRange) {
            if let contentInfo = origin.contentInformationRequest,let localInfo = cacheFile.info {
                contentInfo.contentLength = localInfo.contentLength
                contentInfo.contentType = localInfo.utType
                contentInfo.isByteRangeAccessSupported = localInfo.isByteRangeAccessSupported
            }
            origin.dataRequest?.respond(with: data)
            debugPrint("resourceLoader loadImpl 耗时\(Date().timeIntervalSince1970 - start)")
            finishLoad(with: nil)
        }else {
            debugPrint("resourceLoader 加载本地缓存失败")
            debugPrint("resourceLoader loadImpl 耗时\(Date().timeIntervalSince1970 - start)")
            finishLoad(with: AVPlayerCacheError(desc: "AVPlayerCacheError 加载本地缓存失败"))
        }
        
    }
    
    override func suspend() {
        
    }
    
    override func resume() {
        
    }
    
}

class RangedWebRequest: RangedRequest {
    
    var dataTask: URLSessionDataTask?
    var currentLength: Int64 = 0
    var totalLength: Int64 = 0
    
    var session: URLSession!
    
    override var state: RangedRequestState {
        didSet {
            if state == .cancel {
                cancel()
            }
        }
    }
    
    var cancelledTask = [Int]()
    
    override var isLocal: Bool {
        return false
    }
    
    //网络切换,停止下载
    override func suspend() {
        //4G环境停止下载
        if let state = dataTask?.state ,state == .running {
            dataTask?.suspend()
        }
        state = .suspend
    }
    //恢复下载
    override func resume() {
        if !isRequestRuning() { return }
        if let state = dataTask?.state ,state == .suspended {
            dataTask?.resume()
        }
        state = .start
    }
    
    func isRequestRuning() -> Bool {
        if origin.isCancelled || origin.isFinished {
            return false
        }else {
            return true
        }
    }
    
    //没有期望的range，就按照origin中的range请求
    init(range: AVRange?,origin: AVAssetResourceLoadingRequest,cacheFile: CacheFile) {
        super.init()
        if let range = range {
            self.range = range
        }
        self.cacheFile = cacheFile
        self.origin = origin
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 90
        session = URLSession.init(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    
    func cancel() {
        //loadingRequest被cancel掉，也停掉dataTask
        guard let task = dataTask else { return }
        task.cancel()
        cancelledTask.append(task.taskIdentifier)
    }
    
    func finishWithError(error: Error?) {
        if isRequestRuning() {
            origin.finishLoading(with: error)
        }
    }
    
    override func loadImpl() {
        debugPrint("resourceLoader 加载web request \(range)")
        //loadingRequest 转 URLRequest
        guard let redirectURL = origin.request.url else { return }
        guard let original = URL(string: redirectURL.absoluteString.replacingOccurrences(of: ResourceLoaderPrefix, with: "")) else { return }
        var contentRequest = URLRequest(url: original)
        
        //TODO: - 结构优化
        if self.range.valid {
            let rangeValue = "bytes=\(range.location)-\(range.location + Int64(range.length) - 1)"
            contentRequest.setValue(rangeValue, forHTTPHeaderField:"Range")
            totalLength = range.length
        }else if let range = rangeValue(loadingRequest: origin) {
            self.range = range
            let rangeValue = "bytes=\(range.location)-\(range.location + Int64(range.length) - 1)"
            contentRequest.setValue(rangeValue, forHTTPHeaderField:"Range")
            totalLength = range.length
        }
        
        let task = session.dataTask(with: contentRequest)
        dataTask = task
        debugPrint("resourceLoader 收到代理的请求，加入队列中，启动下载,requestId: \(task.taskIdentifier)")
        task.resume()
    }
    
    func restart() {
        dataTask?.cancel()
        loadImpl()
    }
    
}

extension RangedWebRequest:  URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else  { return }
        if let infoRequest = origin.contentInformationRequest {
            if let mimeType = response.mimeType as CFString?{
                let utType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType, nil)?.takeRetainedValue() as String?
                infoRequest.contentType = utType
            }else {
                completionHandler(.cancel)
                return
            }
            let length = self.responseLength(response: response)
            infoRequest.contentLength = length
            let isSupported = response.allHeaderFields["Content-Range"] != nil
            infoRequest.isByteRangeAccessSupported = isSupported
            if let type = infoRequest.contentType {
                cacheFile.info = AVContentInfo(utType: type, contentLength: length, isByteRangeAccessSupported: isSupported)
            }
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if !data.isEmpty {
            currentLength += Int64(data.count)
            origin.dataRequest?.respond(with: data)
            if let _ = self.data {
                self.data?.append(data)
            }else {
                self.data = data
            }
            if currentLength == totalLength {
                debugPrint("resourceLoader request完成，requestId：\(dataTask.taskIdentifier)")
                finishLoad(with: nil)
                if let data = self.data {
                    _ = cacheFile.write(data: data, range: range)
                   
                }
            }
        }
    }
    
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        //请求失败，存储当前data
        if let data = self.data {
            debugPrint("resourceLoader pre write on cancel \(data.count)")
            _ = cacheFile.write(data: data, range: AVRange(location: range.location, length: Int64(data.count)))
        }
        if let error = error,!cancelledTask.contains(task.taskIdentifier) {
            debugPrint("resourceLoader 服务异常，重试,error: \(error)")
        }
    }
    
}

//工具方法
extension RangedWebRequest {
    
    //    func requestWithTaskId(taskId: Int) -> AVResourceRequest? {
    //        return self.penddingRequest.first(where: {$0.dataTask?.taskIdentifier == taskId})
    //    }
    
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
    func rangeValue(loadingRequest: AVAssetResourceLoadingRequest) -> AVRange? {
        guard let dataRequest = loadingRequest.dataRequest else { return nil }
        return AVRange(location: dataRequest.requestedOffset, length: Int64(dataRequest.requestedLength))
    }
}


//文件操作
//1、创建文件夹，视频信息文件，视频片段
//2、读取索引文件，视频片段
//补充：
//视频信息文件包含，视频的基本信息（长度，是否支持range，类型），索引信息


//Data数据
class RangedData {
    var range: AVRange
    //磁盘数据
    var filePath: String?
    //内存数据
    var data: Data?
    init(range: AVRange) {
        self.range = range
        filePath = rangedFileNameWith(range: range)
    }
    init(range: AVRange,data: Data) {
        self.range = range
        self.data = data
    }
}

func rangedFileNameWith(range: AVRange) -> String {
    return "\(range.location)-\(range.length)".MD5
}

