//
//  ViewController.swift
//  VideoPlayer
//
//  Created by 孟冰川 on 2018/8/8.
//  Copyright © 2018年 com.36kr. All rights reserved.
//

import UIKit
import AVFoundation
import Reachability

class ViewController: UIViewController {
    
    let button = UIButton()
    let slider = UISlider()
    
    let reachability = Reachability()
    
    var isplaying = false
    
    var player: VideoPlayer!
    var cacheManager = AudioCacheManager()
    
    override func loadView() {
        super.loadView()
        commonInit()
    }
    
    func commonInit() {
        player = VideoPlayer()
        player.delegate = self
        view.layer.addSublayer(player.playerLayer)
        let url = "http://mvvideo10.meitudata.com/572ff691113842657.mp4"
        player.resourceLoaderDelegate = cacheManager
        player.urlSrting = url
        button.setTitle("暂停", for: .normal)
        button.addTarget(self, action: #selector(self.changeState), for: .touchUpInside)
        view.addSubview(button)
        view.addSubview(slider)
        slider.addTarget(self, action: #selector(slideChange), for: .valueChanged)
        try? reachability?.startNotifier()
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(note:)), name: Notification.Name.reachabilityChanged, object: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white               
    }
    
    @objc func changeState() {
        if isplaying {
            player.pause()
            button.setTitle("播放", for: .normal)
        }else {
            player.play()
            button.setTitle("暂停", for: .normal)
        }
        isplaying = !isplaying
    }
    
    @objc func reachabilityChanged(note: Notification) {
        guard let status = reachability?.connection else { return }
        switch status {
        case .none:
            ()
        case .wifi:
            player.resume()
            debugPrint("切换到WIFI")
        case .cellular:
            player.suspend()
            debugPrint("切换到4G")
        }
    }
    
    @objc func slideChange() {
        player.seekTime(percet: Double(slider.value))
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidLayoutSubviews() {
        player.playerLayer.frame = CGRect(x: 0, y: 0, width: view.frame.width, height: view.frame.height)
        player.playerLayer.backgroundColor = UIColor.brown.cgColor
        button.sizeToFit()
        button.center = CGPoint(x: view.frame.width/2, y: view.frame.height/2)
        slider.frame = CGRect(x: 10, y: view.frame.height - 30, width: view.frame.width - 20, height: 10)
    }

}

extension ViewController: VideoPlayerDelegate {
    func videoPlayerReadyToPlay(player: VideoPlayer) {
        
    }
    
    
    func videoPlayerDidPlaytoEnd(player: VideoPlayer) {
        
    }
    func videoPlayerDidFail(player: VideoPlayer) {
        
    }
    func videoPlayerBufferEmpty(player: VideoPlayer) {
        
    }
    func videoPlayerBufferFull(player: VideoPlayer) {
        
    }
    
    func videoPlayer(_ player: VideoPlayer,duration: TimeInterval) {
        
    }
    func videoPlayer(_ player: VideoPlayer,cacheProgress: Float) {
        
    }
    
    func videoPlayer(_ player: VideoPlayer, statusChange: AVPlayerStatus) {
        print("status:\(statusChange == .readyToPlay)")
    }
    
    func videoPlayer(_ player: VideoPlayer,progress: Float) {
        self.slider.setValue(progress, animated: true)
    }
    
}












