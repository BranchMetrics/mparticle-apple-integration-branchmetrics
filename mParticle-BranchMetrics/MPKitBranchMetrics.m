//
//  MPKitBranchMetrics.m
//
//  Copyright 2016 mParticle, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "MPKitBranchMetrics.h"
#import <Branch/Branch.h>

#if TARGET_OS_IOS == 1 && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
    #import <UserNotifications/UserNotifications.h>
    #import <UserNotifications/UNUserNotificationCenter.h>
#endif

@interface MPKitRegister (Branch)
// Declare this dummy init method so that this interface works with older versions of mParticle.
- (instancetype) initWithName:(NSString*)name
                    className:(NSString*)className
             startImmediately:(BOOL)startImmediately;
@end

NSString *const ekBMAppKey = @"branchKey";
NSString *const ekBMAForwardScreenViews = @"forwardScreenViews";

@interface MPKitBranchMetrics()
@property (strong) Branch *branchInstance;
@property (assign) BOOL forwardScreenViews;
@property (strong) NSDictionary *temporaryParams;
@property (strong) NSError *temporaryError;
@property (copy) void (^completionHandlerCopy)(NSDictionary *, NSError *);
@end

#pragma mark - MPKitBranchMetrics

@implementation MPKitBranchMetrics

+ (NSNumber *)kitCode {
    return @80;
}

+ (void)load {
    MPKitRegister *kitRegister = [MPKitRegister alloc];
    if ([kitRegister respondsToSelector:@selector(initWithName:className:startImmediately:)]) {
        kitRegister = [kitRegister initWithName:@"BranchMetrics"
            className:@"MPKitBranchMetrics" startImmediately:NO];
    } else {
        kitRegister = [kitRegister initWithName:@"BranchMetrics" className:@"MPKitBranchMetrics"];
    }
    [MParticle registerExtension:kitRegister];
}

#pragma mark - MPKitInstanceProtocol Methods

- (instancetype)initWithConfiguration:(NSDictionary *)configuration
                     startImmediately:(BOOL)startImmediately {
    self = [super init];
    NSString *branchKey = configuration[ekBMAppKey];
    if (!self || !branchKey) {
        return nil;
    }

    self.branchInstance = nil;
    self.forwardScreenViews = [configuration[ekBMAForwardScreenViews] boolValue];
    self.configuration = configuration;
    self.temporaryParams = nil;
    self.temporaryError = nil;

    if (startImmediately) {
        [self start];
    }

    return self;
}

- (id const)providerKitInstance {
    return [self started] ? self.branchInstance : nil;
}

- (void)start {
    static dispatch_once_t branchMetricsPredicate = 0;
    dispatch_once(&branchMetricsPredicate, ^{
        NSString *branchKey = [self.configuration[ekBMAppKey] copy];
        self.branchInstance = [Branch getInstance:branchKey];

        [self.branchInstance initSessionWithLaunchOptions:self.launchOptions
            isReferrable:YES
            andRegisterDeepLinkHandler:^(NSDictionary *params, NSError *error) {
            self.temporaryParams = [params copy];
            self.temporaryError = [error copy];

            if (self.completionHandlerCopy) {
                self.completionHandlerCopy(params, error);
                self.temporaryParams = nil;
                self.temporaryError = nil;
            }
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.branchInstance) {
                self->_started = YES;
            }

            NSMutableDictionary *userInfo = [@{mParticleKitInstanceKey:[[self class] kitCode],
                                               @"branchKey":branchKey} mutableCopy];

            if (self.temporaryParams && self.temporaryParams.count > 0) {
                userInfo[@"params"] = self.temporaryParams;
            }

            if (self.temporaryError) {
                userInfo[@"error"] = self.temporaryError;
            }

            [[NSNotificationCenter defaultCenter]
                postNotificationName:mParticleKitDidBecomeActiveNotification
                object:nil
                userInfo:userInfo];
        });
    });
}

- (MPKitExecStatus*_Nonnull) execStatus:(MPKitReturnCode)returnCode {
    return [[MPKitExecStatus alloc]
        initWithSDKCode:@(MPKitInstanceBranchMetrics)
        returnCode:returnCode];
}

- (nonnull MPKitExecStatus *)continueUserActivity:(nonnull NSUserActivity *)userActivity
restorationHandler:(void(^ _Nonnull)(NSArray * _Nullable restorableObjects))restorationHandler {
    [self.branchInstance continueUserActivity:userActivity];
    return [self execStatus:MPKitReturnCodeSuccess];
}

- (MPKitExecStatus *)logout {
    [self.branchInstance logout];
    return [self execStatus:MPKitReturnCodeSuccess];
}

- (MPKitExecStatus *)logEvent:(MPEvent *)event {
    if (event.info.count > 0) {
        [self.branchInstance userCompletedAction:event.name withState:event.info];
    } else {
        [self.branchInstance userCompletedAction:event.name];
    }
    return [self execStatus:MPKitReturnCodeSuccess];
}

- (MPKitExecStatus *)logScreen:(MPEvent *)event {
    if (!self.forwardScreenViews) {
        return [self execStatus:MPKitReturnCodeUnavailable];
    }
    NSString *actionName = [NSString stringWithFormat:@"Viewed %@", event.name];
    if (event.info.count > 0) {
        [self.branchInstance userCompletedAction:actionName withState:event.info];
    } else {
        [self.branchInstance userCompletedAction:actionName];
    }
    return [self execStatus:MPKitReturnCodeSuccess];
}

- (nonnull MPKitExecStatus *)openURL:(nonnull NSURL *)url
                             options:(nullable NSDictionary<NSString *, id> *)options {
    [self.branchInstance handleDeepLink:url];
    return [self execStatus:MPKitReturnCodeSuccess];
}

- (nonnull MPKitExecStatus *)openURL:(nonnull NSURL *)url
                   sourceApplication:(nullable NSString *)sourceApplication
                          annotation:(nullable id)annotation {
    [self.branchInstance handleDeepLink:url];
    return [self execStatus:MPKitReturnCodeSuccess];
}

- (MPKitExecStatus *)receivedUserNotification:(NSDictionary *)userInfo {
    [self.branchInstance handlePushNotification:userInfo];
    return [self execStatus:MPKitReturnCodeSuccess];
}

#if TARGET_OS_IOS == 1 && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
- (nonnull MPKitExecStatus *)userNotificationCenter:(nonnull UNUserNotificationCenter *)center
                            willPresentNotification:(nonnull UNNotification *)notification {
    [self.branchInstance handlePushNotification:notification.request.content.userInfo];
    return [self execStatus:MPKitReturnCodeSuccess];
}

- (nonnull MPKitExecStatus *)userNotificationCenter:(nonnull UNUserNotificationCenter *)center
                     didReceiveNotificationResponse:(nonnull UNNotificationResponse *)response {
    [self.branchInstance handlePushNotification:response.notification.request.content.userInfo];
    return [self execStatus:MPKitReturnCodeSuccess];
}
#endif

- (MPKitExecStatus *)setUserIdentity:(NSString *)identityString
                        identityType:(MPUserIdentity)identityType {

    if (identityType != MPUserIdentityCustomerId || identityString.length == 0) {
        return [self execStatus:MPKitReturnCodeRequirementsNotMet];
    }

    [self.branchInstance setIdentity:identityString];
    return [self execStatus:MPKitReturnCodeSuccess];
}

- (nonnull MPKitExecStatus *)didFinishLaunchingWithConfiguration:(nonnull NSDictionary *)configuration {
    _started = YES;
    return [self execStatus:MPKitReturnCodeSuccess];
}

- (MPKitExecStatus *)checkForDeferredDeepLinkWithCompletionHandler:
        (void(^)(NSDictionary *linkInfo, NSError *error))completionHandler {
    if (_started && (self.temporaryParams || self.temporaryError)) {
        completionHandler(self.temporaryParams, self.temporaryError);
        self.temporaryParams = nil;
        self.temporaryError = nil;
    } else {
        self.completionHandlerCopy = [completionHandler copy];
    }
    return [self execStatus:MPKitReturnCodeSuccess];
}

@end
