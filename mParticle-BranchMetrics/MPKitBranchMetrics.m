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

@interface MPEvent (Branch)
- (MPMessageType) messageType;
@end

__attribute__((constructor))
void MPKitBranchMetricsLoadClass(void) {
    // Empty function to force class to load.
}

#if TARGET_OS_IOS == 1 && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
    #import <UserNotifications/UserNotifications.h>
    #import <UserNotifications/UNUserNotificationCenter.h>
#endif

NSString *const ekBMAppKey = @"branchKey";
NSString *const ekBMAForwardScreenViews = @"forwardScreenViews";

#pragma mark - MPKitBranchMetrics

@interface MPKitBranchMetrics()
+ (nonnull NSNumber *)kitCode;

- (nonnull MPKitExecStatus *)didFinishLaunchingWithConfiguration:(nonnull NSDictionary *)configuration;

- (void)start;

- (nonnull MPKitExecStatus *)continueUserActivity:(nonnull NSUserActivity *)userActivity
    restorationHandler:(void(^ _Nonnull)(NSArray * _Nullable restorableObjects))restorationHandler;

- (nonnull MPKitExecStatus *)openURL:(nonnull NSURL *)url options:(nullable NSDictionary<NSString *, id> *)options;

- (nonnull MPKitExecStatus *)openURL:(nonnull NSURL *)url
                   sourceApplication:(nullable NSString *)sourceApplication
                          annotation:(nullable id)annotation;

- (nonnull MPKitExecStatus *)receivedUserNotification:(nonnull NSDictionary *)userInfo;
- (nonnull MPKitExecStatus *)logCommerceEvent:(nonnull MPCommerceEvent *)commerceEvent;
- (nonnull MPKitExecStatus *)logEvent:(nonnull MPEvent *)event;
- (nonnull MPKitExecStatus *)setKitAttribute:(nonnull NSString *)key value:(nullable id)value;
- (nonnull MPKitExecStatus *)setOptOut:(BOOL)optOut;

@property (strong, nullable) Branch *branchInstance;
@property (assign) BOOL forwardScreenViews;
@property (nonatomic, unsafe_unretained, readwrite) BOOL started;
@end

#pragma mark - MPKitBranchMetrics

@implementation MPKitBranchMetrics

@synthesize kitApi = _kitApi;

+ (void)initialize {
    NSLog(@"Yope"); //EBS
}

+ (NSNumber *)kitCode {
    return @80;
}

+ (void)load {
    MPKitRegister *kitRegister =
        [[MPKitRegister alloc]
            initWithName:@"BranchMetrics"
            className:@"MPKitBranchMetrics"];
    [MParticle registerExtension:kitRegister];
}

- (MPKitExecStatus*) execStatus:(MPKitReturnCode)returnCode {
    return [[MPKitExecStatus alloc]
        initWithSDKCode:self.class.kitCode
        returnCode:MPKitReturnCodeSuccess];
}

#pragma mark - MPKitInstanceProtocol Methods

- (MPKitExecStatus *)didFinishLaunchingWithConfiguration:(NSDictionary *)configuration {
    NSString *branchKey = configuration[ekBMAppKey];
    if (!branchKey) {
        return [self execStatus:MPKitReturnCodeRequirementsNotMet];
    }

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

- (nonnull MPKitExecStatus *)setOptOut:(BOOL)optOut {
    [Branch setTrackingDisabled:optOut];
    return [self execStatus:MPKitReturnCodeSuccess];
}

- (nonnull MPKitExecStatus *)setKitAttribute:(nonnull NSString *)key value:(nullable id)value {
    [self.kitApi logError:@"Unrecognized key attibute '%@'.", key];
    return [self execStatus:MPKitReturnCodeUnavailable];
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
    BranchEvent *branchEvent = [self branchEventWithEvent:event];
    [branchEvent logEvent];
    return [self execStatus:MPKitReturnCodeSuccess];
}

- (nonnull MPKitExecStatus *)logCommerceEvent:(nonnull MPCommerceEvent *)commerceEvent {
//    BranchEvent *branchEvent = [self branchEventWithCommerceEvent:commerceEvent];
//    [branchEvent logEvent];
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

#pragma mark - Event Transformation

#define addStringField(field, name) { \
    NSString *value = dictionary[@#name]; \
    if (value) { \
        if ([value isKindOfClass:NSString.class]) \
            field = value; \
        else \
            field = [value description]; \
        dictionary[@#name] = nil; \
    } \
}

#define addDecimalField(field, name) { \
    NSString *value = dictionary[@#name]; \
    if (value) { \
        if (![value isKindOfClass:NSString.class]) \
            value = [value description]; \
        field = [NSDecimalNumber decimalNumberWithString:value]; \
        dictionary[@#name] = nil; \
    } \
}

#define addDoubleField(field, name) { \
    NSNumber *value = dictionary[@#name]; \
    if ([value respondsToSelector:@selector(doubleValue)]) { \
        field = [value doubleValue]; \
        dictionary[@#name] = nil; \
    } \
}

- (BranchUniversalObject*) branchUniversalObjectFromDictionary:(NSMutableDictionary*)dictionary {
    NSInteger startCount = dictionary.count;
    BranchUniversalObject *object = [[BranchUniversalObject alloc] init];
    
    addStringField(object.canonicalIdentifier, Id);
    addStringField(object.title, Name);
    addStringField(object.contentMetadata.productBrand, Brand);
    addStringField(object.contentMetadata.productVariant, Variant);
    addStringField(object.contentMetadata.productCategory, Category);
    addDecimalField(object.contentMetadata.price, Item Price);
    addDoubleField(object.contentMetadata.quantity, Quantity);

    return (dictionary.count == startCount) ? nil : object;
}

- (NSString*) stringFromObject:(id<NSObject>)object {
    if (object == nil) return nil;
    if ([object isKindOfClass:NSString.class]) {
        return (NSString*) object;
    } else
    if ([object respondsToSelector:@selector(stringValue)]) {
        return [(id)object stringValue];
    }
    return [object description];
}

- (NSMutableDictionary*) stringDictionaryFromDictionary:(NSDictionary*)dictionary_ {
    if (dictionary_ == nil) return nil;
    NSMutableDictionary *dictionary = [NSMutableDictionary new];
    for(id<NSObject> key in dictionary_.keyEnumerator) {
        NSString* stringValue = [self stringFromObject:dictionary_[key]];
        NSString* stringKey = [self stringFromObject:key];
        if (stringKey) dictionary[stringKey] = stringValue;
    }
    return dictionary;
}

- (BranchEvent*) branchEventWithEvent:(MPEvent*)mpEvent {
    if (mpEvent.messageType == MPMessageTypeEvent)
        return [self branchEventWithStandardEvent:mpEvent];
    else
    if ([mpEvent.name hasPrefix:@"eCommerce"] && [mpEvent.info[@"an"] length] > 0)
        return [self branchEventWithPromotionEvent:mpEvent];
    else
        return [self branchEventWithCommerceEvent:mpEvent];
}

- (BranchEvent*) branchEventWithStandardEvent:(MPEvent*)mpEvent {
    NSString *eventName = nil;
    switch (mpEvent.type) {
    case MPEventTypeSearch:         eventName = BranchStandardEventSearch;      break;
    case MPEventTypeUserContent:    eventName = BranchStandardEventViewItem;    break;
    case MPEventTypeAddToCart:      eventName = BranchStandardEventAddToCart;   break;
    case MPEventTypeCheckout:
    case MPEventTypeCheckoutOption: eventName = BranchStandardEventInitiatePurchase; break;
    case MPEventTypeClick:
    case MPEventTypeViewDetail:     eventName = BranchStandardEventViewItem;    break;
    case MPEventTypePurchase:       eventName = BranchStandardEventPurchase;    break;
    case MPEventTypeAddToWishlist:  eventName = BranchStandardEventAddToWishlist; break;
    default: break;
    }
    if (!eventName.length) eventName = mpEvent.typeName;
    if (!eventName.length) eventName = [NSString stringWithFormat:@"mParticle event type %ld", (long)mpEvent.type];

    BranchEvent *event = [BranchEvent customEventWithName:eventName];
    event.eventDescription = mpEvent.name;
    [event.customData addEntriesFromDictionary:[self stringDictionaryFromDictionary:mpEvent.customFlags]];
    [event.customData addEntriesFromDictionary:[self stringDictionaryFromDictionary:mpEvent.info]];
    if (mpEvent.category.length) event.customData[@"category"] = mpEvent.category;
    return event;
}

- (BranchEvent*) branchEventWithPromotionEvent:(MPEvent*)mpEvent {
    NSString *eventName = nil;
    NSString *actionName = mpEvent.info[@"an"];
    if ([actionName isEqualToString:@"view"])
        eventName = @"VIEW_PROMOTION";
    else
    if ([actionName isEqualToString:@"click"])
        eventName = @"CLICK_PROMOTION";
    else
    if (actionName.length > 0)
        eventName = actionName;
    else
        eventName = @"PROMOTION";
    NSArray *productList = mpEvent.info[@"pl"];
    NSDictionary *product = nil;
    if ([productList isKindOfClass:NSArray.class] && productList.count > 0)
        product = productList[0];

    BranchEvent *event = [BranchEvent customEventWithName:eventName];
    event.eventDescription = mpEvent.name;
    event.customData = [self stringDictionaryFromDictionary:product];
    [event.customData addEntriesFromDictionary:[self stringDictionaryFromDictionary:mpEvent.customFlags]];

    return event;
}

- (BranchEvent*) branchEventWithCommerceEvent:(MPEvent*)mpEvent {
    NSDictionary *branchEventNames = @{
        @"eCommerce - add_to_cart - Item":  BranchStandardEventAddToCart,
        @"eCommerce - view - Item":         BranchStandardEventViewItem,
    };

    NSString *name = nil;
    if (mpEvent.name) name = branchEventNames[mpEvent.name];
    if (!name) name = mpEvent.name;
    if (!name) name = @"Other Event";

    BranchEvent *event = [BranchEvent customEventWithName:name];
    event.eventDescription = mpEvent.name;
    NSMutableDictionary *dictionary = [mpEvent.info mutableCopy];
    BranchUniversalObject *object = [self branchUniversalObjectFromDictionary:dictionary];
    if (object) [event.contentItems addObject:object];

    addStringField(event.transactionID, Transaction Id);
    addStringField(event.currency, Currency);
    addDecimalField(event.revenue, Total Product Amount);
    addDecimalField(event.shipping, Shipping Amount);
    addDecimalField(event.tax, Tax Amount);
    addStringField(event.coupon, Coupon Code);
    addStringField(event.affiliation, Affiliation);
    addStringField(event.searchQuery, Search);
    addStringField(event.eventDescription, mpEvent.name);
    [event.customData addEntriesFromDictionary:[self stringDictionaryFromDictionary:mpEvent.customFlags]];
    [event.customData addEntriesFromDictionary:[self stringDictionaryFromDictionary:dictionary]];

    return event;
}

@end
