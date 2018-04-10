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

@property (assign) BOOL forwardScreenViews;
@property (strong, nullable) Branch *branchInstance;
@property (nonatomic, unsafe_unretained, readwrite) BOOL started;
@end

#pragma mark - MPKitBranchMetrics

@implementation MPKitBranchMetrics

+ (void)initialize {
    NSLog(@"Yope"); //EBS
}

+ (NSNumber *)kitCode {
    return @80;
}

+ (void)load {
    MPKitRegister *kitRegister =
        [[MPKitRegister alloc] initWithName:@"BranchMetrics"
            className:@"MPKitBranchMetrics"];
    [MParticle registerExtension:kitRegister];
}

- (MPKitExecStatus*) execStatus:(MPKitReturnCode)returnCode {
    return [[MPKitExecStatus alloc] initWithSDKCode:self.class.kitCode returnCode:returnCode];
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
    BranchEvent *branchEvent = [self branchEventWithCommerceEvent:commerceEvent];
    [branchEvent logEvent];
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

- (NSString*) branchEventFromEventType:(MPEventType)eventType {
    NSArray *kBranchEvents = @[
@"UNKNOWN",                         // MPEventTypeNavigation = 1,
@"LOCATION",                        // MPEventTypeLocation = 2,
BranchStandardEventSearch,          // MPEventTypeSearch = 3,
// MPEventTypeTransaction = 4,
// MPEventTypeUserContent = 5,
// MPEventTypeUserPreference = 6,
// MPEventTypeSocial = 7,
// MPEventTypeOther = 8,
// 9 used to be MPEventTypeMedia. It has been discontinued
// MPEventTypeAddToCart = 10,
// MPEventTypeRemoveFromCart = 11,
// MPEventTypeCheckout = 12,
// MPEventTypeCheckoutOption = 13,
// MPEventTypeClick = 14,
// MPEventTypeViewDetail = 15,
// MPEventTypePurchase = 16,
// MPEventTypeRefund = 17,
// MPEventTypePromotionView = 18,
// MPEventTypePromotionClick = 19,
// MPEventTypeAddToWishlist = 20,
BranchStandardEventAddToWishlist,   // MPEventTypeRemoveFromWishlist = 21,
// MPEventTypeImpression = 22
    ];

    /*
    typedef NS_ENUM(NSUInteger, MPEventType) {
        MPEventTypeNavigation = 1,
        MPEventTypeLocation = 2,
        MPEventTypeSearch = 3,
        MPEventTypeTransaction = 4,
        MPEventTypeUserContent = 5,
        MPEventTypeUserPreference = 6,
        MPEventTypeSocial = 7,
        MPEventTypeOther = 8,
        // 9 used to be MPEventTypeMedia. It has been discontinued
        MPEventTypeAddToCart = 10,
        MPEventTypeRemoveFromCart = 11,
        MPEventTypeCheckout = 12,
        MPEventTypeCheckoutOption = 13,
        MPEventTypeClick = 14,
        MPEventTypeViewDetail = 15,
        MPEventTypePurchase = 16,
        MPEventTypeRefund = 17,
        MPEventTypePromotionView = 18,
        MPEventTypePromotionClick = 19,
        MPEventTypeAddToWishlist = 20,
        MPEventTypeRemoveFromWishlist = 21,
        MPEventTypeImpression = 22
    };
    */
    NSArray *kbranchEvents = @[
        @"UNKNOWN",
        @"NAVIGATION",                      //
        @"LOCATION",                        //
        BranchStandardEventViewItem,        //
BranchStandardEventPurchase,
BranchStandardEvent
    ];
    NSString *eventName = nil;
    switch (eventType) {
    case MPEventTypeSearch:         eventName = BranchStandardEventSearch;      break;
    case MPEventTypeUserContent:    eventName = BranchStandardEventViewItem;    break;
    case MPEventTypeAddToCart:      eventName = BranchStandardEventAddToCart;   break;
    case MPEventTypeCheckout:
    case MPEventTypeCheckoutOption: eventName = BranchStandardEventInitiatePurchase; break;
    case MPEventTypeClick:
    case MPEventTypeViewDetail:     eventName = BranchStandardEventViewItem;    break;
    case MPEventTypePurchase:       eventName = BranchStandardEventPurchase;    break;
    case MPEventTypeAddToWishlist:  eventName = BranchStandardEventAddToWishlist; break;
    case MPEventTypeRemoveFromWishlist: eventName = @"REMOVE_FROM_WISHLIST";
    case MPEventTypeAddToCart:      eventName = BranchStandardEventAddToCart;   break;
    /** Internal. Used when a product is removed from the cart */
    MPEventTypeRemoveFromCart = 11,
    /** Internal. Used when the cart goes to checkout */
    MPEventTypeCheckout = 12,
    /** Internal. Used when the cart goes to checkout with options */
    MPEventTypeCheckoutOption = 13,
    /** Internal. Used when a product is clicked */
    MPEventTypeClick = 14,
    /** Internal. Used when user views the details of a product */
    MPEventTypeViewDetail = 15,
    /** Internal. Used when a product is purchased */
    MPEventTypePurchase = 16,
    /** Internal. Used when a product refunded */
    MPEventTypeRefund = 17,
    /** Internal. Used when a promotion is displayed */
    MPEventTypePromotionView = 18,
    /** Internal. Used when a promotion is clicked */
    MPEventTypePromotionClick = 19,
    /** Internal. Used when a product is added to the wishlist */
    MPEventTypeAddToWishlist = 20,
    /** Internal. Used when a product is removed from the wishlist */
    MPEventTypeRemoveFromWishlist = 21,
    /** Internal. Used when a product is displayed in a promotion */
    MPEventTypeImpression = 22

    default: break;
    }
}

- (BranchEvent*) branchEventWithEvent:(MPEvent*)mpEvent {
    if (mpEvent.messageType == MPMessageTypeEvent)
        return [self branchEventWithStandardEvent:mpEvent];
    else
    if ([mpEvent.name hasPrefix:@"eCommerce"] && [mpEvent.info[@"an"] length] > 0)
        return [self branchEventWithPromotionEvent:mpEvent];
    else
        return [self branchEventWithOldCommerceEvent:mpEvent];
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

- (BranchEvent*) branchEventWithOldCommerceEvent:(MPEvent*)mpEvent {
    NSArray *actionNames = @[
        @"add_to_cart",
        @"remove_from_cart",
        @"add_to_wishlist",
        @"remove_from_wishlist",
        @"checkout",
        @"checkout_option",
        @"click",
        @"view_detail",
        @"purchase",
        @"refund"
    ];
    int i = 0;
    NSString *eventName = nil;
    for (NSString *action in actionNames) {
        if (i >= self.branchEvents.count)
            break;
        if ([mpEvent.name rangeOfString:action].location != NSNotFound) {
            eventName = self.branchEvents[i];
            break;
        }
        ++i;
    }

    if (!eventName) eventName = mpEvent.name;
    if (!eventName) eventName = @"other_event";
    BranchEvent *event = [BranchEvent customEventWithName:eventName];
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

- (BranchUniversalObject*) branchUniversalObjectFromProduct:(MPProduct*)product {
    BranchUniversalObject *buo = [BranchUniversalObject new];
    buo.contentMetadata.productBrand = product.brand;
    buo.contentMetadata.productCategory = product.category;
    buo.contentMetadata.customMetadata[@"coupon"] = product.couponCode;
    buo.title = product.name;
    buo.contentMetadata.price = [self decimal:product.price];
    buo.contentMetadata.sku = product.sku;
    buo.contentMetadata.productVariant = product.variant;
    buo.contentMetadata.customMetadata[@"position"] =
    [NSString stringWithFormat:@"%lu", (unsigned long) product.position];
    buo.contentMetadata.quantity = [product.quantity doubleValue];
    return buo;
}

- (NSDecimalNumber*) decimal:(NSNumber*)number {
    return [NSDecimalNumber decimalNumberWithDecimal:number.decimalValue];
}

- (
    MPEventTypeAddToCart = 10,
    /** Internal. Used when a product is removed from the cart */
    MPEventTypeRemoveFromCart = 11,
    /** Internal. Used when the cart goes to checkout */
    MPEventTypeCheckout = 12,
    /** Internal. Used when the cart goes to checkout with options */
    MPEventTypeCheckoutOption = 13,
    /** Internal. Used when a product is clicked */
    MPEventTypeClick = 14,
    /** Internal. Used when user views the details of a product */
    MPEventTypeViewDetail = 15,
    /** Internal. Used when a product is purchased */
    MPEventTypePurchase = 16,
    /** Internal. Used when a product refunded */
    MPEventTypeRefund = 17,
    /** Internal. Used when a promotion is displayed */
    MPEventTypePromotionView = 18,
    /** Internal. Used when a promotion is clicked */
    MPEventTypePromotionClick = 19,
    /** Internal. Used when a product is added to the wishlist */
    MPEventTypeAddToWishlist = 20,
    /** Internal. Used when a product is removed from the wishlist */
    MPEventTypeRemoveFromWishlist = 21,
    /** Internal. Used when a product is displayed in a promotion */
    MPEventTypeImpression = 22
)
- (NSArray<NSString*>*) branchEventsInActionOrder {
    /*
    typedef NS_ENUM(NSUInteger, MPCommerceEventAction) {
        MPCommerceEventActionAddToCart = 0,
        MPCommerceEventActionRemoveFromCart,
        MPCommerceEventActionAddToWishList,
        MPCommerceEventActionRemoveFromWishlist,
        MPCommerceEventActionCheckout,
        MPCommerceEventActionCheckoutOptions,
        MPCommerceEventActionClick,
        MPCommerceEventActionViewDetail,
        MPCommerceEventActionPurchase,
        MPCommerceEventActionRefund
    };
    */
    NSArray *kBranchEvents = @[
        BranchStandardEventAddToCart,
        @"REMOVE_FROM_CART",
        BranchStandardEventAddToWishlist,
        @"REMOVE_FROM_WISHLIST",
        BranchStandardEventInitiatePurchase,
        BranchStandardEventInitiatePurchase,
        BranchStandardEventViewItem,
        BranchStandardEventViewItem,
        BranchStandardEventPurchase,
        @"REFUND",
    ];
    return kBranchEvents;
}

- (NSArray<NSString*>*) branchEventInTypeOrder {
    NSArray *kBranchEvents = @[
    ];
}

- (BranchEvent*) branchEventWithCommerceEvent:(MPCommerceEvent*)mpEvent {
    NSString *eventName = nil;
    if (mpEvent.action < self.branchEvents.count)
        eventName = self.branchEvents[mpEvent.action];
    else
    if (mpEvent.type == MPEventTypeImpression
        eventName = [NSString stringWithFormat:@"mParticle commerce event %ld", mpEvent.action];
    BranchEvent *event = [BranchEvent customEventWithName:eventName];
    event.customData[@"checkout_options"] = mpEvent.checkoutOptions;
    event.currency = mpEvent.currency;
    for (NSString* impression in mpEvent.impressions.keyEnumerator) {
        NSSet *set = mpEvent.impressions[impression];
        for (MPProduct *product in set) {
            BranchUniversalObject *obj = [self branchUniversalObjectFromProduct:product];
            if (obj) {
                obj.contentMetadata.customMetadata[@"impression"] = impression;
                [event.contentItems addObject:obj];
            }
        }
    }
    for (MPProduct *product in mpEvent.products) {
        BranchUniversalObject *obj = [self branchUniversalObjectFromProduct:product];
        if (obj) [event.contentItems addObject:obj];
    }

    for (MPPromotion *promo in mpEvent.promotionContainer.promotions) {
        BranchUniversalObject *obj = [BranchUniversalObject new];
        obj.canonicalIdentifier = promo.promotionId;
        obj.title = promo.name;
        obj.contentMetadata.customMetadata[@"position"] = promo.position;
        obj.contentMetadata.customMetadata[@"creative"] = promo.creative;
        [event.contentItems addObject:obj];
    }

    event.customData[@"product_list_name"] = mpEvent.productListName;
    event.customData[@"product_list_source"] = mpEvent.productListSource;
    event.customData[@"screen_name"] = mpEvent.screenName;
    event.affiliation = mpEvent.transactionAttributes.affiliation;
    event.coupon = mpEvent.transactionAttributes.couponCode;
    event.shipping = [self decimal:mpEvent.transactionAttributes.shipping];
    event.tax = [self decimal:mpEvent.transactionAttributes.tax];
    event.revenue = [self decimal:mpEvent.transactionAttributes.revenue];
    event.transactionID = mpEvent.transactionAttributes.transactionId;
    event.customData[@"checkout_step"] = [NSString stringWithFormat:@"%ld", mpEvent.checkoutStep];
    event.customData[@"non_interactive"] = mpEvent.nonInteractive ? @"true" : @"false";

    return event;
}

@end
