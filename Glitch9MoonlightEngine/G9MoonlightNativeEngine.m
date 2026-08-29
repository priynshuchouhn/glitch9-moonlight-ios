#import "G9MoonlightNativeEngine.h"

#import "ConnectionCallbacks.h"
#import "AppListResponse.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "HttpRequest.h"
#import "PairManager.h"
#import "ServerInfoResponse.h"
#import "StreamConfiguration.h"
#import "StreamManager.h"
#import "TemporaryApp.h"

#include <Limelight.h>

static NSString *const G9MoonlightErrorDomain = @"com.glitch9.MoonlightEngine";

struct G9KeyEvent { uint16_t keycode; uint16_t modifierKeycode; uint8_t modifier; };

static struct G9KeyEvent G9TranslateCharacter(unichar character) {
    struct G9KeyEvent event = {0, 0, 0};
    if (character >= 'a' && character <= 'z') event.keycode = character - 'a' + 0x41;
    else if (character >= 'A' && character <= 'Z') {
        event.keycode = character; event.modifier = MODIFIER_SHIFT; event.modifierKeycode = 0x10;
    } else if (character >= '0' && character <= '9') event.keycode = character;
    else {
        NSString *plain = @" `-=[]\\;',./\t";
        const uint16_t plainCodes[] = {0x20, 0xC0, 0xBD, 0xBB, 0xDB, 0xDD, 0xDC, 0xBA, 0xDE, 0xBC, 0xBE, 0xBF, 0x09};
        NSRange range = [plain rangeOfString:[NSString stringWithCharacters:&character length:1]];
        if (range.location != NSNotFound) event.keycode = plainCodes[range.location];
        else {
            NSString *shifted = @"~!@#$%^&*()_+{}|:\"<>?";
            const uint16_t shiftedCodes[] = {0xC0, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0xBD, 0xBB, 0xDB, 0xDD, 0xDC, 0xBA, 0xDE, 0xBC, 0xBE, 0xBF};
            range = [shifted rangeOfString:[NSString stringWithCharacters:&character length:1]];
            if (range.location != NSNotFound) {
                event.keycode = shiftedCodes[range.location];
                event.modifier = MODIFIER_SHIFT; event.modifierKeycode = 0x10;
            }
        }
    }
    return event;
}

@interface G9MoonlightNativeEngine () <PairCallback, ConnectionCallbacks>
@property(nonatomic) StreamManager *streamManager;
@property(nonatomic, copy) G9MoonlightVoidHandler streamingHandler;
@property(nonatomic, copy) G9MoonlightFailureHandler failureHandler;
@property(nonatomic, copy) G9MoonlightPairingReadyHandler pairingReadyHandler;
@property(nonatomic) NSData *pairedCertificate;
@property(nonatomic) NSString *pairingFailure;
@property(nonatomic) uint16_t activeGamepadMask;
@property(nonatomic, copy) G9MoonlightRumbleHandler rumbleHandler;
@end

@implementation G9MoonlightNativeEngine

- (instancetype)init {
    self = [super init];
    if (self) _activeGamepadMask = 1;
    return self;
}

- (NSString *)endpointForHost:(NSString *)host port:(uint16_t)port {
    if ([host containsString:@":"] && ![host hasPrefix:@"["]) {
        return [NSString stringWithFormat:@"[%@]:%u", host, port];
    }
    return [NSString stringWithFormat:@"%@:%u", host, port];
}

- (BOOL)isIdentityValid:(NSData *)identity { return identity.length > 0; }

- (BOOL)isIdentityValid:(NSData *)identity host:(NSString *)host port:(uint16_t)port {
    if (identity.length == 0 || host.length == 0 || port == 0) return NO;
    NSString *endpoint = [self endpointForHost:host port:port];
    HttpManager *http = [[HttpManager alloc] initWithAddress:endpoint httpsPort:0 serverCert:identity];
    ServerInfoResponse *serverInfo = [[ServerInfoResponse alloc] init];
    [http executeRequestSynchronously:[HttpRequest requestForResponse:serverInfo
        withUrlRequest:[http newServerInfoRequest:false]]];
    NSInteger pairStatus = 0;
    return [serverInfo isStatusOk] &&
        [serverInfo getIntTag:@"PairStatus" value:&pairStatus] && pairStatus == 1;
}

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
    NSString *endpoint = [self endpointForHost:host port:port];
    HttpManager *http = [[HttpManager alloc] initWithAddress:endpoint httpsPort:0 serverCert:nil];
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
    NSString *endpoint = [self endpointForHost:host port:port];
    HttpManager *http = [[HttpManager alloc] initWithAddress:endpoint httpsPort:0 serverCert:identity];
    AppListResponse *apps = [[AppListResponse alloc] init];
    [http executeRequestSynchronously:[HttpRequest requestForResponse:apps withUrlRequest:[http newAppListRequest]]];
    if (![apps isStatusOk]) {
        NSString *reason = apps.statusMessage.length > 0 ? apps.statusMessage : @"No response from Sunshine.";
        if (error) *error = [NSError errorWithDomain:G9MoonlightErrorDomain code:5
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to read the Sunshine application list: %@ (status %ld).", reason, (long)apps.statusCode]}];
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
    config.host = endpoint;
    config.httpsPort = 0;
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
    // The Glitch9 platform session is created by the website. Sunshine still
    // requires the connected Moonlight client to issue launch/resume within
    // that pre-authorized, allocated session.
    config.resumeOnly = NO;
    config.multiController = YES;
    config.gamepadMask = self.activeGamepadMask;
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

- (void)sendMouseDeltaX:(int16_t)deltaX deltaY:(int16_t)deltaY {
    LiSendMouseMoveEvent(deltaX, deltaY);
}

- (void)sendMouseButton:(uint8_t)button pressed:(BOOL)pressed {
    LiSendMouseButtonEvent(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, button);
}

- (void)sendKeyboard:(uint16_t)virtualKey pressed:(BOOL)pressed modifiers:(uint8_t)modifiers {
    LiSendKeyboardEvent(0x8000 | virtualKey, pressed ? KEY_ACTION_DOWN : KEY_ACTION_UP, modifiers);
}

- (void)sendText:(NSString *)text {
    if (text.length == 0) return;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        // Match Moonlight's software-keyboard path: normal characters are sent
        // as low-level key events for immediate delivery. UTF-8 text injection
        // is reserved for characters that cannot be represented as key events.
        for (NSUInteger index = 0; index < text.length; index++) {
            struct G9KeyEvent event = G9TranslateCharacter([text characterAtIndex:index]);
            if (event.keycode == 0) {
                NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
                if (utf8.length > 0) {
                    LiSendUtf8TextEvent(utf8.bytes, (unsigned int)utf8.length);
                }
                return;
            }
        }

        for (NSUInteger index = 0; index < text.length; index++) {
            struct G9KeyEvent event = G9TranslateCharacter([text characterAtIndex:index]);
            if (event.modifier != 0) {
                LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_DOWN, event.modifier);
            }
            LiSendKeyboardEvent2(event.keycode, KEY_ACTION_DOWN, event.modifier,
                                 SS_KBE_FLAG_NON_NORMALIZED);
            usleep(50 * 1000);
            LiSendKeyboardEvent2(event.keycode, KEY_ACTION_UP, event.modifier,
                                 SS_KBE_FLAG_NON_NORMALIZED);
            if (event.modifier != 0) {
                LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_UP, event.modifier);
            }
        }
    });
}

- (void)sendControllerButtons:(uint32_t)buttons
                  leftTrigger:(uint8_t)leftTrigger
                 rightTrigger:(uint8_t)rightTrigger
                    leftStickX:(int16_t)leftStickX
                    leftStickY:(int16_t)leftStickY
                   rightStickX:(int16_t)rightStickX
                   rightStickY:(int16_t)rightStickY {
    LiSendControllerEvent((int)buttons, leftTrigger, rightTrigger,
                          leftStickX, leftStickY, rightStickX, rightStickY);
}

- (void)setActiveGamepadMask:(uint16_t)activeGamepadMask {
    _activeGamepadMask = activeGamepadMask ?: 1;
}

- (void)sendController:(uint8_t)controller
            activeMask:(uint16_t)activeMask
               buttons:(uint32_t)buttons
           leftTrigger:(uint8_t)leftTrigger
          rightTrigger:(uint8_t)rightTrigger
             leftStickX:(int16_t)leftStickX
             leftStickY:(int16_t)leftStickY
            rightStickX:(int16_t)rightStickX
            rightStickY:(int16_t)rightStickY {
    LiSendMultiControllerEvent(controller, activeMask, (int)buttons, leftTrigger, rightTrigger,
                               leftStickX, leftStickY, rightStickX, rightStickY);
}

- (void)setRumbleHandler:(G9MoonlightRumbleHandler)handler { _rumbleHandler = [handler copy]; }

- (void)startPairing:(NSString *)PIN {
    if (self.pairingReadyHandler) {
        NSString *relayFailure = self.pairingReadyHandler();
        if (relayFailure.length > 0) self.pairingFailure = relayFailure;
    }
}
- (BOOL)pairingShouldAbort { return self.pairingFailure.length > 0; }
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
- (void)rumble:(unsigned short)c lowFreqMotor:(unsigned short)l highFreqMotor:(unsigned short)h {
    if (self.rumbleHandler) self.rumbleHandler(c, l, h);
}
- (void)connectionStatusUpdate:(int)status {}
- (void)setHdrMode:(bool)enabled {}

- (void)rumbleTriggers:(uint16_t)c leftTrigger:(uint16_t)l rightTrigger:(uint16_t)r {}
- (void)setMotionEventState:(uint16_t)c motionType:(uint8_t)t reportRateHz:(uint16_t)r {}
- (void)setControllerLed:(uint16_t)c r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {}
- (void)videoContentShown {}

@end
