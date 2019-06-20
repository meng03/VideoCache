//
//  Model.swift
//  Client
//
//  Created by 孟冰川 on 2019/6/16.
//  Copyright © 2019 36Kr. All rights reserved.
//

import Foundation
import CommonCrypto

class CacheFile {
    
    var url: String
    
    var info: AVContentInfo?
    var ranges: [AVRange]?
    
    
    //如果目录创建失败，就无法缓存，这种情况应该比较少见
    var cachable = true
    
    init(url: String) {
        self.url = url
    }
    
    class func setup(url: String) -> CacheFile{
        if let cacheFile = loadCacheFile(videoUrl: url) {
            return cacheFile
        }else {
            let cacheFile = CacheFile(url: url)
            cacheFile.initDir()
            return cacheFile
        }
    }
    
    func initDir() {
        guard let cacheDir = CacheFile.cacheDirPath() else { return }
        guard let currentDir = CacheFile.dirPathWith(url: url) else { return }
        if !FileManager.default.fileExists(atPath: cacheDir, isDirectory: nil) {
            try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: false, attributes: nil)
        }
        try? FileManager.default.removeItem(atPath: currentDir)
        if !FileManager.default.fileExists(atPath: currentDir, isDirectory: nil) {
            do {
                try FileManager.default.createDirectory(atPath: currentDir, withIntermediateDirectories: false, attributes: nil)
            }catch {
                self.cachable = false
            }
        }
    }
    
    func saveContentInfo() -> Bool{
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        let timestamp = Date().timeIntervalSince1970
        guard let info = info,let ranges = ranges else {
            return false
        }
        guard let infoPath = CacheFile.videoInfoFilePath(url: url) else { return false }
        print(infoPath)
        let dic = NSMutableDictionary()
        dic["utType"] = info.utType
        dic["contentLength"] = info.contentLength
        dic["isByteRangeAccessSupported"] = info.isByteRangeAccessSupported
        FileManager.default.createFile(atPath: infoPath, contents: nil, attributes: nil)
        dic["ranges"] = ranges.map({["location":$0.location,"length": $0.length]})
        let success = dic.write(toFile: infoPath, atomically: false)
        debugPrint("resourceLoader 缓存文件，保存索引耗时：\(Date().timeIntervalSince1970 - timestamp)")
        return success
    }
    
    class func loadCacheFile(videoUrl: String) -> CacheFile? {
        let timestamp = Date().timeIntervalSince1970
        guard let infoPath = videoInfoFilePath(url: videoUrl) else { return nil }
        if !FileManager.default.fileExists(atPath: infoPath) {
            return nil
        }
        guard let dic = NSDictionary(contentsOf: URL(fileURLWithPath: infoPath)) as? [String: Any] else { return nil }
        //提取视频信息
        guard let utType = dic["utType"] as? String,
            let contentLength = dic["contentLength"] as? Int64,
            let isByteRangeAccessSupported = dic["isByteRangeAccessSupported"] as? Bool else {
                return nil
        }
        let contentInfo = AVContentInfo(utType: utType, contentLength: contentLength, isByteRangeAccessSupported: isByteRangeAccessSupported)
        //获取range，没有直接返回
        guard let rangesDic = dic["ranges"] as? [[String: Any]],rangesDic.count > 0 else {
            return nil
        }
        //range转成AVRange数组，并排序
        let ranges = rangesDic.map({ (dic) -> AVRange? in
            if let location = dic["location"] as? Int64,let length = dic["length"] as? Int {
                return AVRange(location: location, length: Int64(length))
            }
            return nil
        })
            .compactMap({$0})
            .sorted(by: { $0.location < $1.location })
        //检查目录下文件个数，并检查ranges个数与文件是否匹配
        guard let dir = dirPathWith(url: videoUrl) else { return nil }
        guard let subPath = FileManager.default.subpaths(atPath: dir),subPath.count > 0 else { return nil }
        if ranges.count != (subPath.count - 1) { return nil }
        
        let file = CacheFile(url: videoUrl)
        file.info = contentInfo
        file.ranges = ranges
        debugPrint("resourceLoader 缓存文件，加载索引文件耗时：\(Date().timeIntervalSince1970 - timestamp)")
        return file
    }
    
    
    func write(data: Data,range: AVRange) -> Bool {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        debugPrint("resourceLoader 写入数据，线程：\(Thread.current)")
        if data.count == 2 {
            debugPrint("resourceLoader 第一次请求的2字节，是为了获取视频信息，不存储")
            return false
        }
        guard let cacheDir = CacheFile.dirPathWith(url: url) else { return false }
        
        if let ranges = ranges,ranges.contains(where: {$0.isEqual(other: range)}) {
            debugPrint("resourceLoader 已有数据，正常应该是不会存在的")
            return true
        }
        //重叠数据需要特殊处理
        //AVPlayer会同时有多个请求，请求的range会有重叠，这里需要对重叠的range进行特殊处理
        debugPrint("resourceLoader write range: \(range)")
        if data.count != range.length {
            debugPrint("resourceLoader 写入数据失败：数据长度(\(data.count))和range的长度(\(range.length))不一致")
            return false
        }
        let filepath = cacheDir + "/" + rangedFileNameWith(range: range)
        FileManager.default.createFile(atPath: filepath, contents: nil, attributes: nil)
        guard let handle = FileHandle(forWritingAtPath: filepath) else {
            return false
        }
        
        handle.write(data)
        handle.closeFile()
        if ranges != nil {
            self.ranges?.append(range)
            self.ranges?.sort(by: { $0.location < $1.location })
        }else {
            ranges = [range]
        }
        if !saveContentInfo() {
            debugPrint("resourceLoader 写入contentInfo失败")
        }
        
        debugPrint("resourceLoader 写入缓存完成")
        return true
    }

    func read(range: AVRange,localRange: AVRange) -> Data? {
        guard let cacheDir = CacheFile.dirPathWith(url: url) else { return nil }
        let filePath = cacheDir + "/" + rangedFileNameWith(range: localRange)
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return nil }
        handle.seek(toFileOffset: UInt64(range.location - localRange.location))
        let data = handle.readData(ofLength: Int(range.length))
        handle.closeFile()
        return data
    }
    
}

extension CacheFile {
    
    class func cacheDirPath() -> String? {
        guard let cacheDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first else {
            assertionFailure("没有拿到cache目录")
            return nil //正常不会发生
        }        
        return cacheDir + "/videoCache"
    }
    
    class func dirPathWith(url: String) -> String? {
        guard let cacheDirPath = cacheDirPath() else {
            return nil
        }
        return cacheDirPath + "/" + url.MD5
    }
    
    class func videoInfoFilePath(url: String) -> String? {
        guard let dir = dirPathWith(url: url) else { return nil }
        return dir + "/info.plist"
    }
    
}

struct AVRange {
    
    var location: Int64
    var length: Int64
    
    var endOffset: Int64 {
        return location + length
    }
    
    init() {
        self.location = 0
        self.length = 0
    }
    
    init(location: Int64, length: Int64) {
        self.location = location
        self.length = length
    }
    
    func isInRange(offset: Int64) -> Bool {
        return offset >= location && offset <= endOffset
    }
    
    func isEqual(other: AVRange) -> Bool {
        return self.location == other.location && self.length == other.length
    }
    
    var valid: Bool {
        return location != 0 || length != 0
    }
    
}


struct AVContentInfo {
    var utType: String
    var contentLength: Int64
    var isByteRangeAccessSupported: Bool
}

extension String {
    var MD5: String {
        let cString = self.cString(using: .utf8)
        let length = CUnsignedInt(
            self.lengthOfBytes(using: .utf8)
        )
        let result = UnsafeMutablePointer<CUnsignedChar>.allocate(capacity:
            Int(CC_MD5_DIGEST_LENGTH)
        )
        
        CC_MD5(cString!, length, result)
        
        return String(format:
            "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                      result[0], result[1], result[2], result[3],
                      result[4], result[5], result[6], result[7],
                      result[8], result[9], result[10], result[11],
                      result[12], result[13], result[14], result[15])
    }
}

