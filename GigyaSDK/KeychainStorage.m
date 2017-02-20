#import "KeychainStorage.h"

@implementation KeychainStorage

+ (void)addDataWithAuthenticationUI:(NSData * _Nonnull)data
                          dummyData:(NSData * _Nonnull)dummyData
                      attributeName:(NSString * _Nonnull)attributeName
                        serviceName:(NSString * _Nonnull)serviceName
                     passcodeOption:(KeychainPasscodeOptions)passcodeOption
               authenticationPrompt:(NSString * _Nonnull)prompt
                  completionHandler:(KeychainStorageActionHandler _Nullable)handler
{
    [KeychainStorage addData:dummyData
               attributeName:attributeName
                 serviceName:serviceName
              passcodeOption:passcodeOption
           completionHandler:^(NSError *dummyError) {
               if (dummyError) {
                   handler(dummyError);
               }
               else {
                   [KeychainStorage updateData:data
                                 attributeName:attributeName
                                   serviceName:serviceName
                                passcodeOption:passcodeOption
                          authenticationPrompt:prompt
                             completionHandler:handler];
               }
           }];
}

+ (void)addData:(NSData * _Nonnull)data
  attributeName:(NSString * _Nonnull)attributeName
    serviceName:(NSString * _Nonnull)serviceName
 passcodeOption:(KeychainPasscodeOptions)passcodeOption
completionHandler:(KeychainStorageActionHandler _Nullable)handler
{
    NSError *error;
    
    if (floor(NSFoundationVersionNumber) < NSFoundationVersionNumber_iOS_8_0 && passcodeOption == keychainRequirePasscode) {
        error = [NSError errorWithDomain:GSGigyaSDKDomain
                                    code:errSecUnimplemented
                                userInfo:@{ NSLocalizedDescriptionKey: @"Can not require passcode on current version of iOS" }];
        if (handler)
            handler(error);
        
        return;
    }
    
    // we want the operation to fail if there is an item which needs authentication so we will use
    // kSecUseNoAuthenticationUI
    NSMutableDictionary *attributes = [@{
                                         (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                         (__bridge id)kSecAttrService: serviceName,
                                         (__bridge id)kSecAttrAccount: attributeName,
                                         (__bridge id)kSecValueData: data
                                         } mutableCopy];
    
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_7_1)
    {
        [attributes setObject:@YES forKey:(__bridge id)kSecUseNoAuthenticationUI];
        
        if (passcodeOption != keychainIgnorePasscode) {
            CFErrorRef cfError = NULL;
            SecAccessControlRef sacObject = SecAccessControlCreateWithFlags(kCFAllocatorDefault,
                                                                            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, // iOS8+
                                                                            kSecAccessControlUserPresence, &cfError);
            
            if (sacObject == NULL || cfError != NULL) {
                error = (__bridge NSError *)cfError;
                
                if (!error) {
                    error = [NSError errorWithDomain:GSGigyaSDKDomain
                                                code:errSecUnimplemented
                                            userInfo:@{ NSLocalizedDescriptionKey: @"Can not create SecAccessControl object" }];
                }
                
                if (handler)
                    handler(error);
                
                return;
            }
            
            [attributes setObject:(__bridge_transfer id)sacObject forKey:(__bridge id)kSecAttrAccessControl];
        }
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OSStatus status = SecItemAdd((__bridge CFDictionaryRef)attributes, nil);
        
        NSError *error = nil;
        
        if (status != errSecSuccess) {
            if (passcodeOption == keychainPreferPasscode) {
                [KeychainStorage addData:data
                           attributeName:attributeName
                             serviceName:serviceName
                          passcodeOption:keychainIgnorePasscode
                       completionHandler:handler];
                
                return;
            }
            
            error = [NSError errorWithDomain:GSGigyaSDKDomain
                                        code:status
                                    userInfo:@{ NSLocalizedDescriptionKey: @"Failed to add data to keychain" }];
        }
        
        if (handler)
            handler(error);
    });
}

+ (void)updateData:(NSData * _Nonnull)data
     attributeName:(NSString * _Nonnull)attributeName
       serviceName:(NSString * _Nonnull)serviceName
    passcodeOption:(KeychainPasscodeOptions)passcodeOption
authenticationPrompt:(NSString * _Nonnull)prompt
 completionHandler:(KeychainStorageActionHandler _Nullable)handler
{
    NSMutableDictionary *query = [@{
                                    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                    (__bridge id)kSecAttrService: serviceName,
                                    (__bridge id)kSecAttrAccount: attributeName
                                    } mutableCopy];
    
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_7_1)
    {
        [query setObject:prompt forKey:(__bridge id)kSecUseOperationPrompt];
    }
    
    NSDictionary *changes = @{
                              (__bridge id)kSecValueData: data
                              };
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)changes);
        
        // iOS 8: Touch ID protected keychain items do not allow SecItemUpdate. SecItemUpdate always returns errSecInteractionNotAllowed.
        // Workaround: Instead of updating, the items have to be deleted and added again.
        // https://developer.apple.com/library/ios/releasenotes/General/RN-iOSSDK-8.0/
        if (status == errSecInteractionNotAllowed) {
            [self getDataForAttributeName:attributeName
                              serviceName:serviceName
                     authenticationPrompt:prompt
                        completionHandler:^(NSData * _Nullable dummyData, NSError * _Nullable error) {
                            if (error) {
                                if (handler)
                                    handler(error);
                                
                                return;
                            }
                            
                            [self removeDataForAttributeName:attributeName
                                                 serviceName:serviceName
                                           completionHandler:^(NSError * _Nullable error) {
                                               if (error) {
                                                   if (handler)
                                                       handler(error);
                                                   
                                                   return;
                                               }
                                               
                                               [self addData:data
                                               attributeName:attributeName
                                                 serviceName:serviceName
                                              passcodeOption:passcodeOption
                                           completionHandler:handler];
                                           }];
                        }];
            
            return;
        }
        
        NSError *error = nil;
        
        if (status != errSecSuccess) {
            error = [NSError errorWithDomain:GSGigyaSDKDomain
                                        code:status
                                    userInfo:@{ NSLocalizedDescriptionKey: @"Failed to update data in keychain" }];
        }
        
        if (handler)
            handler(error);
    });
}

+ (void)getDataForAttributeName:(NSString * _Nonnull)attributeName
                    serviceName:(NSString * _Nonnull)serviceName
           authenticationPrompt:(NSString * _Nonnull)prompt
              completionHandler:(KeychainStorageGetDataHandler _Nonnull)handler
{
    NSMutableDictionary *query = [@{
                                    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                    (__bridge id)kSecAttrService: serviceName,
                                    (__bridge id)kSecAttrAccount: attributeName,
                                    (__bridge id)kSecReturnData: @YES
                                    } mutableCopy];
    
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_7_1)
    {
        [query setObject:prompt forKey:(__bridge id)kSecUseOperationPrompt];
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CFTypeRef dataTypeRef = NULL;
        
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)(query), &dataTypeRef);
        if (status == errSecSuccess) {
            NSData *resultData = (__bridge_transfer NSData *)dataTypeRef;
            
            handler(resultData, nil);
        }
        else {
            NSError *error = [NSError errorWithDomain:GSGigyaSDKDomain
                                                 code:status
                                             userInfo:@{ NSLocalizedDescriptionKey: @"Failed to get attribute data from keychain" }];
            handler(nil, error);
        }
    });
}

+ (void)removeDataForAttributeName:(NSString * _Nonnull)attributeName
                       serviceName:(NSString * _Nonnull)serviceName
                 completionHandler:(KeychainStorageActionHandler _Nullable)handler
{
    NSDictionary *query = @{
                            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService: serviceName,
                            (__bridge id)kSecAttrAccount: attributeName
                            };
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        
        NSError *error = nil;
        
        if (status != errSecSuccess) {
            error = [NSError errorWithDomain:GSGigyaSDKDomain
                                        code:status
                                    userInfo:@{ NSLocalizedDescriptionKey: @"Failed to remove attribute data from keychain" }];
        }
        
        if (handler) // support nil handlers
            handler(error);
    });
}

@end
