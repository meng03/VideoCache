
### Feature
接管网络请求，自主处理下载的数据，方便网络切换，以及缓存实现

### 用法

````
  var urlAsset: AVURLAsset
  let resourceLoaderDelegate = AudioNetManager()
  //拼接特殊前缀
  let url = URL(string: resourceLoaderDelegate.customPrefix + urlSrting)!
  urlAsset = AVURLAsset(url: url)
  //设置资源加载代理
  urlAsset.resourceLoader.setDelegate(resourceLoaderDelegate, queue: .main)
  let playerItem = AVPlayerItem(asset: urlAsset)
  player.replaceCurrentItem(with: playerItem)
````

### 环境
* iOS10.0
* Swift4.2

### 引入

`pod 'VideoNet'`

### 起因

直接使用`AVPlayer`播放视频，在用户切换4G时，只能销毁`AVPlayer`，在用户点允许播放之后，在重新创建，体验比较差。所以考虑如何接管`AVPlayer`的数据加载，当用户切换到4G环境时，只是暂停下载，缓存的数据仍然可用，也无需销毁`AVPlayer`，比较顺畅。
### 选择

查了下`AVPlayer`的文档，官方提供了很好的方案来接管数据加载。对比了下网上的各种方案，觉得官方方案比较简洁。接下来就进行尝试。
### 基本步骤

步骤比较简单，分为如下三步
一、对要播放的URL做些处理，把`schema`改成自定义的形式。这样，`AVPlayer`就会把这个 `URL`的请求转交给我们。

二、自定义一个类，实现`AVAssetResourceLoaderDelegate`协议，重点实现这个协议中的两个方法。`optional public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool`和`optional public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest)`。

三、给AVURLAsset设置资源代理`urlAsset.resourceLoader.setDelegate(delegate, queue: .main)`。
### 具体实现

三个步骤里面，一和三比较简单，接下来详细说一下步骤二。其中有三个比较关键的点。

关键点1：AVPlayer在播放之前会通过`func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool`这个方法询问，是否等待加载数据，并且把请求交给我们，我们会返回true，并且将请求加到请求队列中。然后启动下载。数据返回的时候调用`loadingRequestdataRequest.respond(with: data)`方法，将数据放到`request`中，当这个`request`需要的数据都给够之后，通过`loadingRequest.finishLoading()`告诉`request`，加载好了，`AVPlayer`就会拿到数据来播放。

关键点2：其中第一次的数据加载，只请求前两个字节，然后根据返回，填充`AVAssetResourceLoadingRequest`的`contentInformationRequest`，来告知`AVPlayer`，这个视频的大小，是否支持`byteRange`，以及视频格式。

关键点3：`func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) `当进行seek操作的时候，这个方法会频繁调用，告知之前的请求已经被取消，因为seek之后要去下载选中的片段，所以之前片段的下载需要被停掉。这个时候我们需要把之前的数据请求停掉，不然会浪费用户流量。
