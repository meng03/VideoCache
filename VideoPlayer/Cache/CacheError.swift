//
//  CacheError.swift
//  VideoPlayer
//
//  Created by 孟冰川 on 2019/7/6.
//  Copyright © 2019 com.36kr. All rights reserved.
//

import Foundation

//参考Kingfisher的error逻辑
public enum VideoPlayerCacheError: Error {
    public enum CacheErrorReason {
        case loadFileCacheFail(range: AVRange)
        case loadMemoryCacheFail(range: AVRange)
    }
    case cacheError(reason: CacheErrorReason)
}

extension VideoPlayerCacheError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cacheError(let reason):
            return reason.errorDescripton
        }
    }
}

extension VideoPlayerCacheError.CacheErrorReason {
    var errorDescripton: String? {
        switch self {
        case .loadFileCacheFail(let range):
            return "加载文件\(range)失败"
        case .loadMemoryCacheFail(let range):
            return "加载内存\(range)失败"
        }
    }
}
