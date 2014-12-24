/*   Copyright 2014 APPNEXUS INC
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "ANMRAIDContainerView.h"
#import "UIView+ANCategory.h"
#import "ANGlobal.h"
#import "ANMRAIDResizeViewManager.h"
#import "ANAdViewInternalDelegate.h"
#import "ANMRAIDCalendarManager.h"
#import "ANMRAIDExpandViewController.h"
#import "ANMRAIDExpandProperties.h"
#import "ANMRAIDOrientationProperties.h"
#import "ANLogging.h"
#import "ANBrowserViewController.h"
#import "ANClickOverlayView.h"
#import "ANPBBuffer.h"
#import "ANANJAMImplementation.h"

typedef NS_OPTIONS(NSUInteger, ANMRAIDContainerViewAdInteraction) {
    ANMRAIDContainerViewAdInteractionExpandedOrResized = 1 << 0,
    ANMRAIDContainerViewAdInteractionVideo = 1 << 1,
    ANMRAIDContainerViewAdInteractionBrowser = 1 << 2,
    ANMRAIDContainerViewAdInteractionCalendar = 1 << 3,
    ANMRAIDContainerViewAdInteractionPicture = 1 << 4
};

@interface ANMRAIDContainerView () <ANAdWebViewControllerMRAIDDelegate, ANMRAIDResizeViewManagerDelegate,
ANMRAIDCalendarManagerDelegate, ANAdWebViewControllerBrowserDelegate, ANMRAIDExpandViewControllerDelegate,
ANBrowserViewControllerDelegate, ANAdWebViewControllerPitbullDelegate, ANAdWebViewControllerANJAMDelegate>

@property (nonatomic, readwrite, assign) CGSize size;
@property (nonatomic, readwrite, strong) NSURL *baseURL;

@property (nonatomic, readwrite, strong) ANAdWebViewController *webViewController;
@property (nonatomic, readwrite, strong) ANMRAIDResizeViewManager *resizeManager;
@property (nonatomic, readwrite, strong) ANMRAIDCalendarManager *calendarManager;
@property (nonatomic, readwrite, strong) ANBrowserViewController *browserViewController;
@property (nonatomic, readwrite, strong) ANMRAIDExpandViewController *expandController;
@property (nonatomic, readwrite, strong) ANMRAIDOrientationProperties *orientationProperties;
@property (nonatomic, readwrite, strong) ANClickOverlayView *clickOverlay;

@property (nonatomic, readwrite, strong) NSMutableArray *pitbullCaptureURLQueue;
@property (nonatomic, readwrite, assign) BOOL isRegisteredForPitbullScreenCaptureNotifications;

@property (nonatomic, readwrite, assign) BOOL adInteractionInProgress;
@property (nonatomic, readwrite, assign) NSUInteger adInteractionValue;

@property (nonatomic, readonly, assign, getter=isExpanded) BOOL expanded;
@property (nonatomic, readonly, assign, getter=isResized) BOOL resized;

@property (nonatomic, readwrite, assign) CGRect lastKnownDefaultPosition;
@property (nonatomic, readwrite, assign) CGRect lastKnownCurrentPosition;

@property (nonatomic, readwrite, strong) ANAdWebViewController *expandWebViewController;

@end

@implementation ANMRAIDContainerView

- (instancetype)initWithSize:(CGSize)size
                        HTML:(NSString *)html
              webViewBaseURL:(NSURL *)baseURL {
    if (self = [super initWithFrame:CGRectMake(0, 0, size.width, size.height)]) {
        _size = size;
        _baseURL = baseURL;
        
        _lastKnownCurrentPosition = CGRectMake(0, 0, size.width, size.height);
        _lastKnownDefaultPosition = CGRectMake(0, 0, size.width, size.height);
        
        self.webViewController = [[ANAdWebViewController alloc] initWithSize:size
                                                                        HTML:html
                                                              webViewBaseURL:baseURL];
        self.webViewController.mraidDelegate = self;
        self.webViewController.browserDelegate = self;
        self.webViewController.pitbullDelegate = self;
        self.webViewController.anjamDelegate = self;
        
        self.backgroundColor = [UIColor clearColor];
        
        UIView *contentView = self.webViewController.contentView;
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:contentView];
        [contentView constrainToSizeOfSuperview];
        [contentView alignToSuperviewWithXAttribute:NSLayoutAttributeLeft
                                         yAttribute:NSLayoutAttributeTop];
    }
    return self;
}

- (void)setAdViewDelegate:(id<ANAdViewInternalDelegate>)adViewDelegate {
    _adViewDelegate = adViewDelegate;
    self.webViewController.adViewDelegate = adViewDelegate;
    self.expandWebViewController.adViewDelegate = adViewDelegate;
}

- (UIViewController *)displayController {
    UIViewController *presentingVC = self.isExpanded ? self.expandController : [self.adViewDelegate displayController];
    if (ANCanPresentFromViewController(presentingVC)) {
        return presentingVC;
    }
    return nil;
}

- (void)adInteractionBeganWithInteraction:(ANMRAIDContainerViewAdInteraction)interaction {
    self.adInteractionValue = self.adInteractionValue | interaction;
    self.adInteractionInProgress = self.adInteractionValue != 0;
}

- (void)adInteractionEndedForInteraction:(ANMRAIDContainerViewAdInteraction)interaction {
    self.adInteractionValue = self.adInteractionValue & ~interaction;
    self.adInteractionInProgress = self.adInteractionValue != 0;
}

- (void)setAdInteractionInProgress:(BOOL)adInteractionInProgress {
    BOOL oldValue = _adInteractionInProgress;
    _adInteractionInProgress = adInteractionInProgress;
    BOOL newValue = _adInteractionInProgress;
    if (oldValue != newValue) {
        if (_adInteractionInProgress) {
            [self.adViewDelegate adInteractionDidBegin];
        } else {
            [self.adViewDelegate adInteractionDidEnd];
        }
    }
}

#pragma mark - ANNewAdWebViewControllerMRAIDDelegate

- (CGRect)defaultPosition {
    if (self.window) {
        CGRect absoluteContentViewFrame = [self convertRect:self.bounds toView:nil];
        CGRect position = adjustAbsoluteRectInWindowCoordinatesForOrientationGivenRect(absoluteContentViewFrame);
        position.origin.y -= ([ANMRAIDUtil screenSize].height - [ANMRAIDUtil maxSize].height);
        self.lastKnownDefaultPosition = position;
        return position;
    } else {
        return self.lastKnownDefaultPosition;
    }
}

- (CGRect)currentPosition {
    UIView *contentView = self.webViewController.contentView;
    if (self.expandWebViewController.contentView.window) {
        contentView = self.expandWebViewController.contentView;
    }
    
    if (contentView) {
        CGRect absoluteContentViewFrame = [contentView convertRect:contentView.bounds toView:nil];
        CGRect position = adjustAbsoluteRectInWindowCoordinatesForOrientationGivenRect(absoluteContentViewFrame);
        position.origin.y -= ([ANMRAIDUtil screenSize].height - [ANMRAIDUtil maxSize].height);
        self.lastKnownCurrentPosition = position;
        return position;
    } else {
        return self.lastKnownCurrentPosition;
    }
}

- (BOOL)isViewable {
    return self.expandWebViewController ? [self.expandWebViewController.contentView an_isViewable] : [self.webViewController.contentView an_isViewable];
}

- (void)adShouldExpandWithExpandProperties:(ANMRAIDExpandProperties *)expandProperties {
    UIViewController *presentingController = [self displayController];
    if (!presentingController) {
        ANLogDebug(@"Ignoring call to mraid.expand() - no root view controller to present from");
        return;
    }
    
    [self handleBrowserLoadingForMRAIDStateChange];
    [self adInteractionBeganWithInteraction:ANMRAIDContainerViewAdInteractionExpandedOrResized];
    
    ANLogDebug(@"Expanding with expand properties: %@", [expandProperties description]);
    [self.adViewDelegate adWillPresent];
    if (self.isResized) {
        [self.resizeManager detachResizeView];
        self.resizeManager = nil;
    }
    
    UIView *expandContentView = self.webViewController.contentView;

    BOOL presentWithAnimation = NO;
    
    if (expandProperties.URL.absoluteString.length) {
        ANAdWebViewControllerConfiguration *customConfig = [[ANAdWebViewControllerConfiguration alloc] init];
        customConfig.scrollingEnabled = YES;
        customConfig.navigationTriggersDefaultBrowser = NO;
        customConfig.initialMRAIDState = ANMRAIDStateExpanded;
        self.expandWebViewController = [[ANAdWebViewController alloc] initWithSize:[ANMRAIDUtil screenSize]
                                                                               URL:expandProperties.URL
                                                                    webViewBaseURL:self.baseURL
                                                                     configuration:customConfig];
        self.expandWebViewController.mraidDelegate = self;
        self.expandWebViewController.browserDelegate = self;
        self.expandWebViewController.pitbullDelegate = self;
        self.expandWebViewController.anjamDelegate = self;
        self.expandWebViewController.adViewDelegate = self.adViewDelegate;

        expandContentView = self.expandWebViewController.contentView;
        presentWithAnimation = YES;
    }
    
    self.expandController = [[ANMRAIDExpandViewController alloc] initWithContentView:expandContentView
                                                                    expandProperties:expandProperties];
    if (self.orientationProperties) {
        [self adShouldSetOrientationProperties:self.orientationProperties];
        self.orientationProperties = nil;
    }
    self.expandController.delegate = self;
    [presentingController presentViewController:self.expandController
                                       animated:presentWithAnimation
                                     completion:^{
                                         [self.adViewDelegate adDidPresent];
                                         [self.webViewController adDidFinishExpand];
                                     }];
}

- (void)adShouldSetOrientationProperties:(ANMRAIDOrientationProperties *)orientationProperties {
    if (self.expandController) {
        ANLogDebug(@"Setting orientation properties on expand controller: %@", [orientationProperties description]);
        self.expandController.orientationProperties = orientationProperties;
    } else {
        self.orientationProperties = orientationProperties;
    }
}

- (void)adShouldAttemptResizeWithResizeProperties:(ANMRAIDResizeProperties *)resizeProperties {
    ANLogDebug(@"Attempting resize with resize properties: %@", [resizeProperties description]);
    [self handleBrowserLoadingForMRAIDStateChange];
    [self adInteractionBeganWithInteraction:ANMRAIDContainerViewAdInteractionExpandedOrResized];
    
    if (!self.resizeManager) {
        self.resizeManager = [[ANMRAIDResizeViewManager alloc] initWithContentView:self.webViewController.contentView
                                                                        anchorView:self];
        self.resizeManager.delegate = self;
    }
    
    NSString *errorString;
    BOOL resizeHappened = [self.resizeManager attemptResizeWithResizeProperties:resizeProperties
                                                                    errorString:&errorString];
    [self.webViewController adDidFinishResize:resizeHappened
                                  errorString:errorString
                                    isResized:self.isResized];
    if (!self.isResized) {
        [self adInteractionEndedForInteraction:ANMRAIDContainerViewAdInteractionExpandedOrResized];
    }
}

- (void)adShouldClose {
    if (self.isResized || self.isExpanded) {
        [self adShouldResetToDefault];
    } else {
        [self adShouldHide];
    }
    
    [self adInteractionEndedForInteraction:ANMRAIDContainerViewAdInteractionExpandedOrResized];
}

- (void)adShouldResetToDefault {
    [self.resizeManager detachResizeView];
    self.resizeManager = nil;

    [self handleBrowserLoadingForMRAIDStateChange];
    
    if (self.isExpanded) {
        [self.adViewDelegate adWillClose];
        
        BOOL dismissWithAnimation = NO;
        UIView *detachedContentView = [self.expandController detachContentView];
        if (detachedContentView == self.expandWebViewController.contentView) {
            dismissWithAnimation = YES;
        }
        
        [self.expandController dismissViewControllerAnimated:dismissWithAnimation
                                                  completion:^{
                                                      [self.adViewDelegate adDidClose];
                                                  }];
        self.expandController = nil;
    }
    
    self.expandWebViewController = nil;

    UIView *contentView = self.webViewController.contentView;
    if (contentView.superview != self) {
        [self addSubview:contentView];
        [contentView removeConstraints:contentView.constraints];
        [contentView constrainToSizeOfSuperview];
        [contentView alignToSuperviewWithXAttribute:NSLayoutAttributeLeft
                                         yAttribute:NSLayoutAttributeTop];
    }

    [self.webViewController adDidResetToDefault];
    [self adInteractionEndedForInteraction:ANMRAIDContainerViewAdInteractionExpandedOrResized];
}

- (void)adShouldHide {
    [self handleBrowserLoadingForMRAIDStateChange];
    
    if (self.embeddedInModalView && [self.adViewDelegate conformsToProtocol:@protocol(ANInterstitialAdViewInternalDelegate)]) {
        id<ANInterstitialAdViewInternalDelegate> interstitialDelegate = (id<ANInterstitialAdViewInternalDelegate>)self.adViewDelegate;
        [interstitialDelegate adShouldClose];
    } else {
        [UIView animateWithDuration:kAppNexusAnimationDuration
                         animations:^{
                             self.webViewController.contentView.alpha = 0.0f;
                         } completion:^(BOOL finished) {
                             self.webViewController.contentView.hidden = YES;
                         }];
        [self.webViewController adDidHide];
    }
    [self adInteractionEndedForInteraction:ANMRAIDContainerViewAdInteractionExpandedOrResized];
}

- (void)adShouldOpenCalendarWithCalendarDict:(NSDictionary *)calendarDict {
    [self adInteractionBeganWithInteraction:ANMRAIDContainerViewAdInteractionCalendar];
    self.calendarManager = [[ANMRAIDCalendarManager alloc] initWithCalendarDictionary:calendarDict
                                                                        delegate:self];
}

- (void)adShouldSavePictureWithUri:(NSString *)uri {
    [self adInteractionBeganWithInteraction:ANMRAIDContainerViewAdInteractionPicture];
    [ANMRAIDUtil storePictureWithUri:uri
                withCompletionTarget:self
                  completionSelector:@selector(image:didFinishSavingWithError:contextInfo:)];
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    if (error) {
        [self.webViewController adDidFailPhotoSaveWithErrorString:error.localizedDescription];
        [self.expandWebViewController adDidFailPhotoSaveWithErrorString:error.localizedDescription];
    }
    [self adInteractionEndedForInteraction:ANMRAIDContainerViewAdInteractionPicture];
}

- (void)adShouldPlayVideoWithUri:(NSString *)uri {
    UIViewController *presentingViewController = [self displayController];
    if (!presentingViewController) {
        ANLogDebug(@"Ignoring call to mraid.playVideo() - no root view controller to present from");
        return;
    }
    [self adInteractionBeganWithInteraction:ANMRAIDContainerViewAdInteractionVideo];
    self.resizeManager.resizeView.hidden = YES;
    [ANMRAIDUtil playVideoWithUri:uri
           fromRootViewController:presentingViewController
             withCompletionTarget:self
               completionSelector:@selector(moviePlayerDidFinish:)];
}

- (void)moviePlayerDidFinish:(NSNotification *)notification {
    self.resizeManager.resizeView.hidden = NO;
    [self adInteractionEndedForInteraction:ANMRAIDContainerViewAdInteractionVideo];
}

- (void)didMoveToWindow {
    [self.resizeManager didMoveAnchorViewToWindow];
}

- (BOOL)isExpanded {
    return self.expandController.presentingViewController ? YES : NO;
}

- (BOOL)isResized {
    return self.resizeManager.isResized;
}

#pragma mark - ANCalendarManagerDelegate

- (UIViewController *)rootViewControllerForPresentationForCalendarManager:(ANMRAIDCalendarManager *)calendarManager {
    return [self displayController];
}

- (void)willDismissCalendarEditForCalendarManager:(ANMRAIDCalendarManager *)calendarManager {
    if (!self.embeddedInModalView && !self.isExpanded) {
        [self.adViewDelegate adWillClose];
    }
    self.resizeManager.resizeView.hidden = NO;
}

- (void)didDismissCalendarEditForCalendarManager:(ANMRAIDCalendarManager *)calendarManager {
    if (!self.embeddedInModalView && !self.isExpanded) {
        [self.adViewDelegate adDidClose];
    }
    [self adInteractionEndedForInteraction:ANMRAIDContainerViewAdInteractionCalendar];
}

- (void)willPresentCalendarEditForCalendarManager:(ANMRAIDCalendarManager *)calendarManager {
    if (!self.embeddedInModalView && !self.isExpanded) {
        [self.adViewDelegate adWillPresent];
    }
    self.resizeManager.resizeView.hidden = YES;
}

- (void)didPresentCalendarEditForCalendarManager:(ANMRAIDCalendarManager *)calendarManager {
    if (!self.embeddedInModalView && !self.isExpanded) {
        [self.adViewDelegate adDidPresent];
    }
}

- (void)calendarManager:(ANMRAIDCalendarManager *)calendarManager calendarEditFailedWithErrorString:(NSString *)errorString {
    [self.webViewController adDidFailCalendarEditWithErrorString:errorString];
    [self.expandWebViewController adDidFailPhotoSaveWithErrorString:errorString];
    [self adInteractionEndedForInteraction:ANMRAIDContainerViewAdInteractionCalendar];
}

#pragma mark - ANResizeViewManagerDelegate

- (void)resizeViewClosedByResizeViewManager:(ANMRAIDResizeViewManager *)manager {
    [self adShouldResetToDefault];
}

#pragma mark - ANMRAIDExpandViewControllerDelegate

- (void)closeButtonWasTappedOnExpandViewController:(ANMRAIDExpandViewController *)controller {
    [self adShouldResetToDefault];
}

#pragma mark - ANWebViewControllerBrowserDelegate

- (void)openDefaultBrowserWithURL:(NSURL *)URL {
    if (!self.adViewDelegate) {
        ANLogDebug(@"Ignoring attempt to trigger browser on ad while not attached to a view.");
        return;
    }
    
    [self.adViewDelegate adWasClicked];
    
    if (![self.adViewDelegate opensInNativeBrowser]) {
        [self openInAppBrowserWithURL:URL];
    }
    else if ([[UIApplication sharedApplication] canOpenURL:URL]) {
        [self.adViewDelegate adWillLeaveApplication];
        [[UIApplication sharedApplication] openURL:URL];
    } else {
        ANLogWarn(@"opening_url_failed %@", URL);
    }
}

- (void)openInAppBrowserWithURL:(NSURL *)URL {
    [self adInteractionBeganWithInteraction:ANMRAIDContainerViewAdInteractionBrowser];
    if (!self.browserViewController) {
        self.browserViewController = [[ANBrowserViewController alloc] initWithURL:URL
                                                                         delegate:self
                                                         delayPresentationForLoad:[self.adViewDelegate landingPageLoadsInBackground]];
        if (!self.browserViewController) {
            ANLogError(@"Browser controller did not instantiate correctly.");
            return;
        }
    } else {
        self.browserViewController.url = URL;
    }
}

#pragma mark - ANBrowserViewControllerDelegate

- (UIViewController *)rootViewControllerForDisplayingBrowserViewController:(ANBrowserViewController *)controller {
    return [self displayController];
}

- (void)browserViewController:(ANBrowserViewController *)controller browserIsLoading:(BOOL)isLoading {
    if ([self.adViewDelegate landingPageLoadsInBackground]) {
        if (!controller.completedInitialLoad) {
            isLoading ? [self showClickOverlay] : [self hideClickOverlay];
        } else {
            [self hideClickOverlay];
        }
    }
}

- (void)willDismissBrowserViewController:(ANBrowserViewController *)controller {
    if (!self.embeddedInModalView && !self.isExpanded) {
        [self.adViewDelegate adWillClose];
    }
    self.resizeManager.resizeView.hidden = NO;
}

- (void)didDismissBrowserViewController:(ANBrowserViewController *)controller {
    self.browserViewController = nil;
    if (!self.embeddedInModalView && !self.isExpanded) {
        [self.adViewDelegate adDidClose];
    }
    [self hideClickOverlay];
    [self adInteractionEndedForInteraction:ANMRAIDContainerViewAdInteractionBrowser];
}

- (void)willPresentBrowserViewController:(ANBrowserViewController *)controller {
    if (!self.embeddedInModalView && !self.isExpanded) {
        [self.adViewDelegate adWillPresent];
    }
    self.resizeManager.resizeView.hidden = YES;
    [self adInteractionBeganWithInteraction:ANMRAIDContainerViewAdInteractionBrowser];
}

- (void)didPresentBrowserViewController:(ANBrowserViewController *)controller {
    if (!self.embeddedInModalView && !self.isExpanded) {
        [self.adViewDelegate adDidPresent];
    }
}

- (void)willLeaveApplicationFromBrowserViewController:(ANBrowserViewController *)controller {
    [self.adViewDelegate adWillLeaveApplication];
}

- (void)handleBrowserLoadingForMRAIDStateChange {
    [self.browserViewController stopLoading];
    [self adInteractionEndedForInteraction:ANMRAIDContainerViewAdInteractionBrowser];
}

# pragma mark - Click overlay

- (UIView *)viewToDisplayClickOverlay {
    if (self.isExpanded) {
        return self.expandController.view;
    } else if (self.isResized) {
        return self.resizeManager.resizeView;
    } else {
        return self;
    }
}

- (void)showClickOverlay {
    if (!self.clickOverlay.superview) {
        self.clickOverlay = [ANClickOverlayView addOverlayToView:[self viewToDisplayClickOverlay]];
        self.clickOverlay.alpha = 0.0;
    }
    
    self.clickOverlay.hidden = NO;
    
    [UIView animateWithDuration:0.5
                     animations:^{
                         self.clickOverlay.alpha = 1.0;
                     }];
}

- (void)hideClickOverlay {
    if ([self.clickOverlay superview]) {
        [UIView animateWithDuration:0.5
                         animations:^{
                             self.clickOverlay.alpha = 0.0;
                         } completion:^(BOOL finished) {
                             self.clickOverlay.hidden = YES;
                         }];
    }
}

#pragma mark - ANWebViewControllerPitbullDelegate

- (void)handlePitbullURL:(NSURL *)URL {
    if ([URL.host isEqualToString:@"capture"]) {
        BOOL transitionInProgress = NO;
        if ([self.adViewDelegate conformsToProtocol:@protocol(ANBannerAdViewInternalDelegate)]) {
            id<ANBannerAdViewInternalDelegate> bannerDelegate = (id<ANBannerAdViewInternalDelegate>)self.adViewDelegate;
            transitionInProgress = [[bannerDelegate transitionInProgress] boolValue];
        }
        if (transitionInProgress) {
            if (![self.pitbullCaptureURLQueue count]) {
                [self registerForPitbullScreenCaptureNotifications];
            }
            [self.pitbullCaptureURLQueue addObject:URL];
            return;
        }
    } else if ([URL.host isEqualToString:@"web"]) {
        [self dispatchPitbullScreenCaptureCalls];
        [self unregisterFromPitbullScreenCaptureNotifications];
    }

    [ANPBBuffer handleUrl:URL forView:self.webViewController.contentView];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (object == self.adViewDelegate) {
        NSNumber *transitionInProgress = change[NSKeyValueChangeNewKey];
        if ([transitionInProgress boolValue] == NO) {
            [self unregisterFromPitbullScreenCaptureNotifications];
            [self dispatchPitbullScreenCaptureCalls];
        }
    }
}

- (void)registerForPitbullScreenCaptureNotifications {
    if (!self.isRegisteredForPitbullScreenCaptureNotifications) {
        if ([self.adViewDelegate conformsToProtocol:@protocol(ANBannerAdViewInternalDelegate)]) {
            NSObject *object = (id<ANBannerAdViewInternalDelegate>)self.adViewDelegate;
            [object addObserver:self
                     forKeyPath:@"transitionInProgress"
                        options:NSKeyValueObservingOptionNew
                        context:nil];
            self.isRegisteredForPitbullScreenCaptureNotifications = YES;
        } else {
            ANLogDebug(@"Attempt to register for pitbull screen capture notifications on an ad view which does not conform to ANBannerAdViewInternalDelegate");
        }
    }
}

- (void)unregisterFromPitbullScreenCaptureNotifications {
    NSObject *bannerObject = self.adViewDelegate;
    if (self.isRegisteredForPitbullScreenCaptureNotifications) {
        @try {
            [bannerObject removeObserver:self
                              forKeyPath:@"transitionInProgress"];
        }
        @catch (NSException * __unused exception) {}
        self.isRegisteredForPitbullScreenCaptureNotifications = NO;
    }
}

- (void)dispatchPitbullScreenCaptureCalls {
    for (NSURL *URL in self.pitbullCaptureURLQueue) {
        UIView *view = self.webViewController.contentView;
        [ANPBBuffer handleUrl:URL forView:view];
    }
    self.pitbullCaptureURLQueue = nil;
}

- (NSMutableArray *)pitbullCaptureURLQueue {
    if (!_pitbullCaptureURLQueue) _pitbullCaptureURLQueue = [[NSMutableArray alloc] initWithCapacity:5];
    return _pitbullCaptureURLQueue;
}

#pragma mark - ANWebViewControllerANJAMDelegate

- (void)handleANJAMURL:(NSURL *)URL {
    [ANANJAMImplementation handleURL:URL
               withWebViewController:self.webViewController];
}

@end