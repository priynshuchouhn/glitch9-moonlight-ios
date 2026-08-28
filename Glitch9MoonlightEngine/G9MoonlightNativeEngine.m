#import "G9MoonlightNativeEngine.h"

#import "ConnectionCallbacks.h"
#import "AppListResponse.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "HttpRequest.h"
#import "PairManager.h"
#import "StreamConfiguration.h"
#import "StreamManager.h"
#import "TemporaryApp.h"

#include <Limelight.h>

static NSString *const G9MoonlightErrorDomain = @"com.glitch9.MoonlightEngine";

@interface G9MoonlightNativeEngine () <PairCallback, ConnectionCallbacks>
@property(nonatomic) StreamManager *streamManager;
@property(nonatomic, copy) G9MoonlightVoidHandler streamingHandler;
@property(nonatomic, copy) G9MoonlightFailureHandler failureHandler;
@property(nonatomic, copy) G9MoonlightPairingReadyHandler pairingReadyHandler;
@property(nonatomic) NSData *pairedCertificate;
@property(nonatomic) NSString *pairingFailure;
@end

@implementation G9MoonlightNativeEngine

- (BOOL)isIdentityValid:(NSData *)identity { return identity.length > 0; }

- (NSData *)pairHost:(NSString *)host port:(uint16_t)port pin:(NSString *)pin
        pairingReady:(G9MoonlightPairingReadyHandler)pairingReady error:(NSError **)error {
    [CryptoManager generateKeyPairUsingSSL];
    NSData *clientCertificate = [CryptoManager readCertFromFile];
    if (clientCertificate.length == 0) {
        if (error) *error = [NSError errorWithDomain:G9MoonlightErrorDomain code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Unable to create the Moonlight client identity."}];
        return nil;
    }
    self.pairingReadyHandler = pairingReady;
    self.pairedCertificate = nil;
    self.pairingFailure = nil;
    HttpManager *http = [[HttpManager alloc] initWithAddress:host httpsPort:port serverCert:nil];
    PairManager *pair = [[PairManager alloc] initWithManager:http clientCert:clientCertificate pin:pin callback:self];
    [pair main];
    self.pairingReadyHandler = nil;
    if (self.pairedCertificate.length > 0) return self.pairedCertificate;
    if (error) *error = [NSError errorWithDomain:G9MoonlightErrorDomain code:2
        userInfo:@{NSLocalizedDescriptionKey: self.pairingFailure ?: @"The host rejected pairing."}];
    return nil;
}

- (BOOL)startHost:(NSString *)host port:(uint16_t)port application:(NSString *)application
         identity:(NSData *)identity renderView:(UIView *)renderView
      onStreaming:(G9MoonlightVoidHandler)onStreaming onFailure:(G9MoonlightFailureHandler)onFailure
            error:(NSError **)error {
    if (self.streamManager) {
        if (error) *error = [NSError errorWithDomain:G9MoonlightErrorDomain code:3
            userInfo:@{NSLocalizedDescriptionKey: @"A Moonlight stream is already running."}];
        return NO;
    }
    if (host.length == 0 || application.length == 0 || identity.length == 0 || !renderView) {
        if (error) *error = [NSError errorWithDomain:G9MoonlightErrorDomain code:4
            userInfo:@{NSLocalizedDescriptionKey: @"The Moonlight stream configuration is incomplete."}];
        return NO;
    }
    HttpManager *http = [[HttpManager alloc] initWithAddress:host httpsPort:port serverCert:identity];
    AppListResponse *apps = [[AppListResponse alloc] init];
    [http executeRequestSynchronously:[HttpRequest requestForResponse:apps withUrlRequest:[http newAppListRequest]]];
    if (![apps isStatusOk]) {
        if (error) *error = [NSError errorWithDomain:G9MoonlightErrorDomain code:5
            userInfo:@{NSLocalizedDescriptionKey: @"Unable to read the Sunshine application list."}];
        return NO;
    }
    TemporaryApp *selectedApp = nil;
    for (TemporaryApp *candidate in [apps getAppList]) {
        if ([candidate.name caseInsensitiveCompare:application] == NSOrderedSame) {
            selectedApp = candidate;
            break;
        }
    }
    if (!selectedApp.id) {
        if (error) *error = [NSError errorWithDomain:G9MoonlightErrorDomain code:6
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Sunshine has no application named '%@'.", application]}];
        return NO;
    }
    StreamConfiguration *config = [[StreamConfiguration alloc] init];
    config.host = host;
    config.httpsPort = port;
    config.appID = selectedApp.id;
    config.appName = selectedApp.name;
    config.serverCert = identity;
    config.width = 1920;
    config.height = 1080;
    config.frameRate = 60;
    config.bitRate = 15000;
    config.optimizeGameSettings = YES;
    config.playAudioOnPC = NO;
    config.useFramePacing = YES;
    config.resumeOnly = YES;
    config.multiController = NO;
    config.gamepadMask = 0;
    config.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    config.supportedVideoFormats = VIDEO_FORMAT_H264;
    self.streamingHandler = onStreaming;
    self.failureHandler = onFailure;
    self.streamManager = [[StreamManager alloc] initWithConfig:config renderView:renderView connectionCallbacks:self];
    [[[NSOperationQueue alloc] init] addOperation:self.streamManager];
    return YES;
}

- (void)stop {
    [self.streamManager stopStream];
    self.streamManager = nil;
    self.streamingHandler = nil;
    self.failureHandler = nil;
}

- (void)startPairing:(NSString *)PIN { if (self.pairingReadyHandler) self.pairingReadyHandler(); }
- (void)pairSuccessful:(NSData *)serverCert { self.pairedCertificate = serverCert; }
- (void)pairFailed:(NSString *)message { self.pairingFailure = message; }
- (void)alreadyPaired { self.pairingFailure = @"The host is already paired with another stored identity."; }

- (void)connectionStarted { if (self.streamingHandler) self.streamingHandler(); }
- (void)connectionTerminated:(int)errorCode {
    if (self.failureHandler) self.failureHandler(@"stream_interrupted", [NSString stringWithFormat:@"Moonlight connection ended (%d).", errorCode]);
}
- (void)stageStarting:(const char *)stageName {}
- (void)stageComplete:(const char *)stageName {}
- (void)stageFailed:(const char *)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    if (self.failureHandler) self.failureHandler(@"stream_interrupted", [NSString stringWithFormat:@"Moonlight stage %s failed (%d).", stageName, errorCode]);
}
- (void)launchFailed:(NSString *)message { if (self.failureHandler) self.failureHandler(@"desktop_unavailable", message); }
- (void)rumble:(unsigned short)c lowFreqMotor:(unsigned short)l highFreqMotor:(unsigned short)h {}
- (void)connectionStatusUpdate:(int)status {}
- (void)setHdrMode:(bool)enabled {}
- (void)rumbleTriggers:(uint16_t)c leftTrigger:(uint16_t)l rightTrigger:(uint16_t)r {}
- (void)setMotionEventState:(uint16_t)c motionType:(uint8_t)t reportRateHz:(uint16_t)r {}
- (void)setControllerLed:(uint16_t)c r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {}
- (void)videoContentShown {}

@end
