#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^G9MoonlightVoidHandler)(void);
typedef void (^G9MoonlightFailureHandler)(NSString *code, NSString *message);
typedef NSString * _Nullable (^G9MoonlightPairingReadyHandler)(void);

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

@end

NS_ASSUME_NONNULL_END
