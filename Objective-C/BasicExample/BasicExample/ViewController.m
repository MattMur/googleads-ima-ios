#import "ViewController.h"

@import AVFoundation;
@import GoogleInteractiveMediaAds;
@import NativoVideoControls;

@interface ViewController () <IMAAdsLoaderDelegate, IMAAdsManagerDelegate>

/// Content video player.
@property(nonatomic, strong) AVPlayer *contentPlayer;

/// Play button.
@property(nonatomic, weak) IBOutlet UIButton *playButton;

/// UIView in which we will render our AVPlayer for content.
@property(nonatomic, weak) IBOutlet UIView *videoView;

// SDK
/// Entry point for the SDK. Used to make ad requests.
@property(nonatomic, strong) IMAAdsLoader *adsLoader;

/// Playhead used by the SDK to track content video progress and insert mid-rolls.
@property(nonatomic, strong) IMAAVPlayerContentPlayhead *contentPlayhead;

/// Main point of interaction with the SDK. Created by the SDK as the result of an ad request.
@property(nonatomic, strong) IMAAdsManager *adsManager;

// New properties added
@property (nonatomic) NtvCustomVideoControlsView *fullScreenControlsView;
@property (nonatomic, weak) IBOutlet UIView *videoViewContainer;
@property (nonatomic) AVPlayerLayer *playerLayer;
@property (nonatomic) IMAAdDisplayContainer *adDisplayContainer;

@end

@implementation ViewController

// The content URL to play.
NSString *const kTestAppContentUrl_MP4 =
    @"https://storage.googleapis.com/gvabox/media/samples/stock.mp4";

// Ad tag
NSString *const kTestAppAdTagUrl = @"https://pubads.g.doubleclick.net/gampad/ads?sz=640x480&"
    @"iu=/124319096/external/single_ad_samples&ciu_szs=300x250&impl=s&gdfp_req=1&env=vp&"
    @"output=vast&unviewed_position_start=1&cust_params=deployment%3Ddevsite%26sample_ct%3Dlinear&"
    @"correlator=";

- (void)viewDidLoad {
  [super viewDidLoad];

  self.playButton.layer.zPosition = MAXFLOAT;

  [self setupAdsLoader];
    
    // Wait for contstraints to layout before setup
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setUpContentPlayer];
    });
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onVideoPlayerTouch:)];
    [self.videoViewContainer addGestureRecognizer:tapGesture];
}

//- (IBAction)onPlayButtonTouch:(id)sender {
//  [self requestAds];
//  self.playButton.hidden = YES;
//}

- (void)onVideoPlayerTouch:(UITapGestureRecognizer *)tap {
    [self requestAds];
    self.playButton.hidden = YES;
    [self expandFullScreen];
}

#pragma mark Content Player Setup

- (void)setUpContentPlayer {
  // Load AVPlayer with path to our content.
  NSURL *contentURL = [NSURL URLWithString:kTestAppContentUrl_MP4];
  self.contentPlayer = [AVPlayer playerWithURL:contentURL];

  // Create a player layer for the player.
  self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.contentPlayer];

  // Size, position, and display the AVPlayer.
  self.playerLayer.frame = self.videoView.layer.bounds;
  self.playerLayer.videoGravity = AVLayerVideoGravityResize;
  [self.videoView.layer addSublayer:self.playerLayer];

  // Set up our content playhead and contentComplete callback.
  self.contentPlayhead = [[IMAAVPlayerContentPlayhead alloc] initWithAVPlayer:self.contentPlayer];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(contentDidFinishPlaying:)
                                               name:AVPlayerItemDidPlayToEndTimeNotification
                                             object:self.contentPlayer.currentItem];
}


#pragma mark SDK Setup

- (void)setupAdsLoader {
  self.adsLoader = [[IMAAdsLoader alloc] initWithSettings:nil];
  self.adsLoader.delegate = self;
}

- (void)requestAds {
  // Create an ad display container for ad rendering.
  self.adDisplayContainer =
      [[IMAAdDisplayContainer alloc] initWithAdContainer:self.videoView
                                          viewController:self
                                          companionSlots:nil];
  // Create an ad request with our ad tag, display container, and optional user context.
  IMAAdsRequest *request = [[IMAAdsRequest alloc] initWithAdTagUrl:kTestAppAdTagUrl
                                                adDisplayContainer:self.adDisplayContainer
                                                   contentPlayhead:self.contentPlayhead
                                                       userContext:nil];
  [self.adsLoader requestAdsWithRequest:request];
}

- (void)contentDidFinishPlaying:(NSNotification *)notification {
  // Make sure we don't call contentComplete as a result of an ad completing.
  if (notification.object == self.contentPlayer.currentItem) {
    [self.adsLoader contentComplete];
  }
}

// Attempt to update IMAAdDisplayContainer ViewController when we switch between fullscreen
- (void)updateIMADisplayContainerViewController:(UIViewController *)viewController {
    self.adDisplayContainer.adContainerViewController = viewController;
}

#pragma mark AdsLoader Delegates

- (void)adsLoader:(IMAAdsLoader *)loader adsLoadedWithData:(IMAAdsLoadedData *)adsLoadedData {
  // Grab the instance of the IMAAdsManager and set ourselves as the delegate.
  self.adsManager = adsLoadedData.adsManager;
  self.adsManager.delegate = self;
  // Create ads rendering settings to tell the SDK to use the in-app browser.
  IMAAdsRenderingSettings *adsRenderingSettings = [[IMAAdsRenderingSettings alloc] init];
    adsRenderingSettings.webOpenerPresentingController = self;
  // Initialize the ads manager.
  [self.adsManager initializeWithAdsRenderingSettings:adsRenderingSettings];
}

- (void)adsLoader:(IMAAdsLoader *)loader failedWithErrorData:(IMAAdLoadingErrorData *)adErrorData {
  // Something went wrong loading ads. Log the error and play the content.
  NSLog(@"Error loading ads: %@", adErrorData.adError.message);
  [self.contentPlayer play];
}

#pragma mark AdsManager Delegates

- (void)adsManager:(IMAAdsManager *)adsManager didReceiveAdEvent:(IMAAdEvent *)event {
  // When the SDK notified us that ads have been loaded, play them.
  if (event.type == kIMAAdEvent_LOADED) {
    [adsManager start];
  }
}

- (void)adsManager:(IMAAdsManager *)adsManager didReceiveAdError:(IMAAdError *)error {
  // Something went wrong with the ads manager after ads were loaded. Log the error and play the
  // content.
  NSLog(@"AdsManager error: %@", error.message);
  [self.contentPlayer play];
}

- (void)adsManagerDidRequestContentPause:(IMAAdsManager *)adsManager {
  // The SDK is going to play ads, so pause the content.
  [self.contentPlayer pause];
}

- (void)adsManagerDidRequestContentResume:(IMAAdsManager *)adsManager {
  // The SDK is done playing ads (at least for now), so resume the content.
  [self.contentPlayer play];
}

#pragma mark Full Screen Player

- (void)expandFullScreen {
    
    // Load fullscreen player from Nib
    if (!self.fullScreenControlsView) {
        NSBundle *bundle = [NSBundle bundleForClass:[NtvCustomVideoControlsView class]];
        NSArray *nibItems = [bundle loadNibNamed:@"NtvCustomVideoControlsView" owner:nil options:nil];
        self.fullScreenControlsView = nibItems[0];
    }
    
    if (self.contentPlayer.rate == 0) {
        [self.fullScreenControlsView willLoadNewPlayerItem];
    }

    [self.fullScreenControlsView.authorNameLabel setText:@"By Basic Example"];
    [self.fullScreenControlsView.titleLabel setText:@"Video Title"];
    [self.fullScreenControlsView.contentTextView setText:@"Full screen player demo"];
    
    // Add Player Layer to Full Screen Controls
    [self.videoView removeFromSuperview];
    [self.fullScreenControlsView.videoPlaceholderView insertSubview:self.videoView atIndex:0];
    self.videoView.frame = self.fullScreenControlsView.videoPlaceholderView.bounds;
    [self.fullScreenControlsView setPlayer:self.contentPlayer];
    if (!self.fullScreenControlsView.videoPlaceholderView.translatesAutoresizingMaskIntoConstraints) {
        [AppUtils removeViewConstraints:self.videoView];
        [AppUtils setViewAnchors:self.videoView equalToView:self.fullScreenControlsView.videoPlaceholderView];
    }
    
    // Load player item into full screen controls
    if (self.contentPlayer.currentItem) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.fullScreenControlsView didLoadNewPlayerItem:self.contentPlayer.currentItem];
        });
    }

    // Add Full Screen Controls to Root View
    UIView *rootView = nil;
    UIWindow *window = [[UIApplication sharedApplication].delegate window];
    if ([window rootViewController]) {
        rootView = window.rootViewController.view;
    }
    if (rootView) {
        [AppUtils removeViewConstraints:self.fullScreenControlsView];
        [rootView addSubview:self.fullScreenControlsView];
        [AppUtils setViewAnchors:self.fullScreenControlsView equalToView:rootView];
        
        [self.fullScreenControlsView setAlpha:0];
        [UIView animateWithDuration:0.33f animations:^{
            [self.fullScreenControlsView setAlpha:1];
        } completion:^(BOOL finished) {
            // start playing
            [self.contentPlayer play];
        }];
    }
    else {
        NSLog(@"Error - Could not find root view controller on window");
    }

    // Listen for full-screen collapse
    [[NSNotificationCenter defaultCenter] addObserverForName:@"ntvcollapse" object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        [self exitFullScreen];
    }];
}

- (void)exitFullScreen {
    // Remove same videoView from fullscreen player and re-insert into videoViewContainer
    [self.videoView removeFromSuperview];
    [self.videoViewContainer insertSubview:self.videoView atIndex:0];
    [AppUtils removeViewConstraints:self.videoView];
    [AppUtils setViewAnchors:self.videoView equalToView:self.videoViewContainer];
    [self.fullScreenControlsView removeFromSuperview];
    self.playerLayer.frame = self.videoViewContainer.bounds;
}

@end
