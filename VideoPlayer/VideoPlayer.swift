//
//  VideoPlayer.swift
//  Client
//
//  Created by 孟冰川 on 2018/8/9.
//  Copyright © 2018年 36Kr. All rights reserved.
//
import AVFoundation
import UIKit

protocol VideoPlayerDelegate: class {
    
    func videoPlayerDidPlaytoEnd(player: VideoPlayer)
    func videoPlayerDidFail(player: VideoPlayer)
    func videoPlayerBufferEmpty(player: VideoPlayer)
    func videoPlayerBufferFull(player: VideoPlayer)
    func videoPlayerReadyToPlay(player: VideoPlayer)
    
    func videoPlayer(_ player: VideoPlayer,duration: TimeInterval)
    func videoPlayer(_ player: VideoPlayer,cacheProgress: Float)
    func videoPlayer(_ player: VideoPlayer,progress: Float)
}


/// 播放器状态
///
/// - readyToPlay: 播放器准备完成，可以播放
/// - bufferFull: 播放器当前缓冲完成，可以播放
/// - bufferEmpty: 播放器缓冲中
/// - playToEnd: 播放到结尾
/// - fail: 播放失败
enum VideoPlayerState {
    case readyToPlay
    case bufferFull
    case bufferEmpty
    case playToEnd
    case fail
}

typealias VoidClosureType = () -> ()

class VideoPlayer: NSObject {
    
    ///相关常量
    fileprivate let kPreferredTimescale = CMTimeScale(1 * UInt64(NSEC_PER_SEC))
    ///监听状态的keyPath
    fileprivate let kStatus = "status"
    fileprivate let kLoadedTimeRanges = "loadedTimeRanges"
    fileprivate let kPlaybackBufferEmpty = "playbackBufferEmpty"
    fileprivate let kPlaybackLikelyToKeepUp = "playbackLikelyToKeepUp"
    
    enum VideoPlayState {
        case play
        case pause
    }
    
    weak var delegate : VideoPlayerDelegate?
    weak var resourceLoaderDelegate: AudioCacheManager?
    lazy var playerLayer: AVPlayerLayer = {
        let playerLayer = AVPlayerLayer.init(player: self.player)
        playerLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        playerLayer.backgroundColor = UIColor.black.cgColor
        return playerLayer
    }()
    /// 视频总时间
    var totalTime: TimeInterval {
        //防止除数为0的问题
        guard let totalTime = currentItem?.duration,totalTime != CMTime.indefinite else {
            return 1
        }
        return max(CMTimeGetSeconds(totalTime),1)
    }
    
    ///缓冲时间
    fileprivate var loadedTime: TimeInterval {
        let loadedTimeRange = currentItem?.loadedTimeRanges
        guard let timeRange = loadedTimeRange?.first as? CMTimeRange else {
            return 0
        }
        let startTime: TimeInterval = CMTimeGetSeconds(timeRange.start)
        let durationTime: TimeInterval = CMTimeGetSeconds(timeRange.duration)
        return startTime + durationTime
    }
    
    /// 监听状态
    fileprivate var didAddedObserver = false
    fileprivate var playerTimeObserve: Any?
    /// 播放器实例
    fileprivate var player: AVPlayer = AVPlayer()
    /// 当前播放位置
    fileprivate var cursor: CMTime?
    fileprivate var currentItem: AVPlayerItem?
    /// 播放状态
    fileprivate var playerState: VideoPlayerState = .bufferEmpty
    fileprivate var playToEnd = false

    /// 视频播放URL
    var urlSrting: String? {
        didSet {
            guard let urlSrting = urlSrting, let url = URL(string: urlSrting) else {
                return
            }
            removeObserverProperty()
            removeNotification()
            
            var urlAsset: AVURLAsset
            if let delegate = resourceLoaderDelegate,let url = URL(string: delegate.customPrefix + urlSrting) {
                urlAsset = AVURLAsset(url: url)
                urlAsset.resourceLoader.setDelegate(delegate, queue: .main)
            }else {
                urlAsset = AVURLAsset(url: url)
            }
            let playerItem = AVPlayerItem(asset: urlAsset)
            
            playerItem.preferredForwardBufferDuration = 5
           debugPrint("playerItem 的内容 = \(playerItem.asset)")
            player.replaceCurrentItem(with: playerItem)
            currentItem = playerItem
            debugPrint("currentItem 的内容 = \(String(describing: currentItem?.asset))")
            playToEnd = false
            addObserverProperty()
            addNotification()
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let kPath = keyPath,!playToEnd && playerState != .fail else {
            return
        }
        switch kPath {
        case kStatus:
            switch player.status {
            case .readyToPlay:
                let time = currentItem?.duration
                var second: TimeInterval = 0
                if let time = time {
                    second = CMTimeGetSeconds(time)
                    delegate?.videoPlayer(self, duration: second)
                }
                if isBufferFull() {
                    delegate?.videoPlayerReadyToPlay(player: self)
                    playerState = .readyToPlay
                    debugPrint("=================视频readyToPlay")
                }else {
                    debugPrint("=================视频readyToPlay 但是cursor不在cache中")
                }
            case .failed:
                debugPrint("=================视频播放失败 原因 \(String(describing: player.error))")
                delegate?.videoPlayerDidFail(player: self)
                playerState = .fail
            case .unknown:
                debugPrint("=================视频进入unknown状态")
            }
        case kLoadedTimeRanges,kPlaybackBufferEmpty,kPlaybackLikelyToKeepUp:
            if kPath == kLoadedTimeRanges {
                delegate?.videoPlayer(self, cacheProgress: Float(self.loadedTime / self.totalTime))
            }
            if isBufferFull() {
                delegate?.videoPlayerBufferFull(player: self)
                playerState = .bufferFull
            }else {
                delegate?.videoPlayerBufferEmpty(player: self)
                playerState = .bufferEmpty
            }
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @objc fileprivate func videoDidPlayToEndTime() {
        debugPrint("=================videoDidPlayToEndTime")
        playerState = .playToEnd
        delegate?.videoPlayerDidPlaytoEnd(player: self)
        playToEnd = true
    }
    
    deinit {
        removeObserverProperty()
        removeNotification()
    }
}

//MARK: - 对外提供的方法
extension VideoPlayer {
    
    /// 播放
    ///
    /// - Returns: 是否播放成功
    func play() -> Bool {
        player.play()
        playToEnd = false
        return isBufferFull()
    }
    
    /// 暂停
    func pause() {
        self.cursor = player.currentTime()
        player.pause()
    }
    
    //网络挂起
    func suspend() {
        pause()
        resourceLoaderDelegate?.suspend()
        debugPrint("暂停并挂起请求")
    }
    
    func resume() {
        debugPrint("继续请求，并播放")
        resourceLoaderDelegate?.resume()
        _ = self.play()
    }
    
    /// 选择时间
    ///
    /// - Parameters:
    ///   - time: 选择的时间
    ///   - completion: 完成回调
    func seekTime(time: Double? = nil,completion:VoidClosureType? = nil) {
        var seekedTime = CMTime.zero
        if let time = time {
            seekedTime = CMTime(seconds: time, preferredTimescale: kPreferredTimescale)
        }else if let cursor = cursor{
            seekedTime = cursor
        }
        seekTime(cmTime: seekedTime,completion: completion)
    }
    
    func seekTime(percet: Double,completion:VoidClosureType? = nil) {
        seekTime(time: percet * totalTime, completion: completion)
    }
    
}

//MARK: - 通知和状态监听
extension VideoPlayer {
    
    fileprivate func addObserverProperty() {
        guard let playerItem = currentItem, didAddedObserver == false else { return }
        playerItem.addObserver(self, forKeyPath: kStatus, options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: kLoadedTimeRanges, options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: kPlaybackBufferEmpty, options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: kPlaybackLikelyToKeepUp, options: .new, context: nil)
        //观察播放进度
        playerTimeObserve = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: kPreferredTimescale), queue: DispatchQueue.main, using: {[weak self] (_) in
            self?.cursor = self?.player.currentTime()
            guard let slf = self else { return }
            let currentTimeSecond = Float(playerItem.currentTime().value) / Float(playerItem.currentTime().timescale)
            slf.delegate?.videoPlayer(slf, progress: currentTimeSecond/Float(slf.totalTime))
        })
        didAddedObserver = true
    }
    
    fileprivate func removeObserverProperty() {
        guard let playerItem = currentItem, didAddedObserver == true else { return }
        playerItem.removeObserver(self, forKeyPath: kStatus, context: nil)
        playerItem.removeObserver(self, forKeyPath: kLoadedTimeRanges, context: nil)
        playerItem.removeObserver(self, forKeyPath: kPlaybackBufferEmpty, context: nil)
        playerItem.removeObserver(self, forKeyPath: kPlaybackLikelyToKeepUp, context: nil)
        playerItem.cancelPendingSeeks()
        playerItem.asset.cancelLoading()
        if let playerTimerObserver = playerTimeObserve {
            player.removeTimeObserver(playerTimerObserver)
            playerTimeObserve = nil
        }
        didAddedObserver = false
    }
    
    fileprivate func addNotification() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(videoDidPlayToEndTime),
                                               name: .AVPlayerItemDidPlayToEndTime, object: currentItem)
    }
    
    fileprivate func removeNotification() {
        NotificationCenter.default.removeObserver(self)
    }
    
}

//MARK: - tools
extension VideoPlayer {
    
    //文档中说可能有多个range，经过实验，只有一个，
    //这个range的length，大于preferredDuration就说明是可以播放的状态
    //默认给了个2，iOS10可以设置
    fileprivate func isBufferFull() -> Bool {
        guard let item = currentItem else { return false }
        var preferredForwardBufferDuration: TimeInterval = 2
        if #available(iOS 10.0, *) {
            preferredForwardBufferDuration = item.preferredForwardBufferDuration
        }
//        debugPrint("checkIfInCache:\(item.loadedTimeRanges)")
        return item.loadedTimeRanges.contains(where: { (value) -> Bool in
            guard let timeRange = value as? CMTimeRange else { return false }
            let durationTime: TimeInterval = CMTimeGetSeconds(timeRange.duration)
            return durationTime > preferredForwardBufferDuration
        })
    }
    
    fileprivate func seekTime(cmTime: CMTime,completion:VoidClosureType? = nil) {
        currentItem?.seek(to: cmTime) {[weak self] (finished) in
            ///用户滑动slider，会很频繁的调用seek，这里finished为false时，说明某次是失败的，可以忽略
            if !finished { return }
            self?.cursor = cmTime
            completion?()
        }
    }
}

