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

NSString *const ekBMAppKey = @"branchKey";
NSString *const ekBMAForwardScreenViews = @"forwardScreenViews";

@interface MPKitBranchMetrics()
@property (strong) Branch *branchInstance;
@property (assign) BOOL forwardScreenViews;
@end

@implementation MPKitBranchMetrics

@synthesize kitApi = _kitApi;

+ (NSNumber *)kitCode {
    return @80;
}

+ (void)load {
    MPKitRegister *kitRegister = [[MPKitRegister alloc] initWithName:@"BranchMetrics" className:@"MPKitBranchMetrics"];
    [MParticle registerExtension:kitRegister];
}

- (MPKitExecStatus*) execStatus:(MPKitReturnCode)returnCode {
    return [[MPKitExecStatus alloc]
        initWithSDKCode:[[self class] kitCode]
        returnCode:MPKitReturnCodeSuccess];
}

#pragma mark - MPKitInstanceProtocol Methods

- (MPKitExecStatus *)didFinishLaunchingWithConfiguration:(NSDictionary *)configuration {
    NSString *branchKey = configuration[ekBMAppKey];
    if (!branchKey) {
        return [self execStatus:MPKitReturnCodeRequirementsNotMet];
    }

    self.branchInstance = nil;
    self.forwardScreenViews = [configuration[ekBMAForwardScreenViews] boolValue];
    _configuration = configuration;
    _started = NO;

    return [self execStatus:MPKitReturnCodeSuccess];
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
            if (error) {
                [self->_kitApi onAttributionCompleteWithResult:nil error:error];
                return;
            }
            
            MPAttributionResult *attributionResult = [[MPAttributionResult alloc] init];
            attributionResult.linkInfo = params;

            [self->_kitApi onAttributionCompleteWithResult:attributionResult error:nil];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.branchInstance) {
                self->_started = YES;
            }

            NSMutableDictionary *userInfo = [@{
                mParticleKitInstanceKey: [[self class] kitCode],
                @"branchKey": branchKey
            } mutableCopy];

            [[NSNotificationCenter defaultCenter]
                postNotificationName:mParticleKitDidBecomeActiveNotification
                object:nil
                userInfo:userInfo];
        });
    });
}

- (nonnull MPKitExecStatus *)continueUserActivity:(nonnull NSUserActivity *)userActivity restorationHandler:(void(^ _Nonnull)(NSArray * _Nullable restorableObjects))restorationHandler {
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

- (nonnull MPKitExecStatus *)openURL:(nonnull NSURL *)url options:(nullable NSDictionary<NSString *, id> *)options {
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

@end
