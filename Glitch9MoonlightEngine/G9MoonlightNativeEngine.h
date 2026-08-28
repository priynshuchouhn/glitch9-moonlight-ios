#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^G9MoonlightVoidHandler)(void);
typedef void (^G9MoonlightFailureHandler)(NSString *code, NSString *message);
typedef NSString * _Nullable (^G9MoonlightPairingReadyHandler)(void);
typedef void (^G9MoonlightRumbleHandler)(uint16_t controller, uint16_t lowFrequency, uint16_t highFrequency);

@interface G9MoonlightNativeEngine : NSObject

- (BOOL)isIdentityValid:(NSData *)identity;
- (BOOL)isIdentityValid:(NSData *)identity host:(NSString *)host port:(uint16_t)port;
- (nullable NSData *)pairHost:(NSString *)host
                         port:(uint16_t)port
                          pin:(NSString *)pin
                pairingReady:(G9MoonlightPairingReadyHandler)pairingReady
                        error:(NSError **)error;
- (BOOL)startHost:(NSString *)host
             port:(uint16_t)port
      application:(NSString *)application
         identity:(NSData *)identity
       renderView:(UIView *)renderView
      onStreaming:(G9MoonlightVoidHandler)onStreaming
        onFailure:(G9MoonlightFailureHandler)onFailure
            error:(NSError **)error;
- (void)stop;
- (void)sendMouseDeltaX:(int16_t)deltaX deltaY:(int16_t)deltaY;
- (void)sendMouseButton:(uint8_t)button pressed:(BOOL)pressed;
- (void)sendKeyboard:(uint16_t)virtualKey pressed:(BOOL)pressed modifiers:(uint8_t)modifiers;
- (void)sendText:(NSString *)text;
- (void)sendControllerButtons:(uint32_t)buttons
                  leftTrigger:(uint8_t)leftTrigger
                 rightTrigger:(uint8_t)rightTrigger
                    leftStickX:(int16_t)leftStickX
                    leftStickY:(int16_t)leftStickY
                   rightStickX:(int16_t)rightStickX
                   rightStickY:(int16_t)rightStickY;
- (void)setActiveGamepadMask:(uint16_t)activeGamepadMask;
- (void)sendController:(uint8_t)controller
            activeMask:(uint16_t)activeMask
               buttons:(uint32_t)buttons
           leftTrigger:(uint8_t)leftTrigger
          rightTrigger:(uint8_t)rightTrigger
             leftStickX:(int16_t)leftStickX
             leftStickY:(int16_t)leftStickY
            rightStickX:(int16_t)rightStickX
            rightStickY:(int16_t)rightStickY;
- (void)setRumbleHandler:(nullable G9MoonlightRumbleHandler)handler;

@end

NS_ASSUME_NONNULL_END
