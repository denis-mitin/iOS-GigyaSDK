#import <Foundation/Foundation.h>

#import "Gigya+Internal.h"

typedef void(^KeychainStorageActionHandler)(NSError * _Nullable error);
typedef void(^KeychainStorageGetDataHandler)(NSData * _Nullable data, NSError * _Nullable error);

typedef enum keychainPasscodeOptions
{
    keychainIgnorePasscode,
    keychainPreferPasscode,
    keychainRequirePasscode
} KeychainPasscodeOptions;

@interface KeychainStorage : NSObject

+ (void)addDataWithAuthenticationUI:(NSData * _Nonnull)data
                          dummyData:(NSData * _Nonnull)dummyData
                      attributeName:(NSString * _Nonnull)attributeName
                        serviceName:(NSString * _Nonnull)serviceName
                     passcodeOption:(KeychainPasscodeOptions)passcodeOption
               authenticationPrompt:(NSString * _Nonnull)prompt
                  completionHandler:(KeychainStorageActionHandler _Nullable)handler;

+ (void)addData:(NSData * _Nonnull)data
  attributeName:(NSString * _Nonnull)attributeName
    serviceName:(NSString * _Nonnull)serviceName
 passcodeOption:(KeychainPasscodeOptions)passcodeOption
completionHandler:(KeychainStorageActionHandler _Nullable)handler;

+ (void)updateData:(NSData * _Nonnull)data
     attributeName:(NSString * _Nonnull)attributeName
       serviceName:(NSString * _Nonnull)serviceName
    passcodeOption:(KeychainPasscodeOptions)passcodeOption
authenticationPrompt:(NSString * _Nonnull)prompt
 completionHandler:(KeychainStorageActionHandler _Nullable)handler;

+ (void)getDataForAttributeName:(NSString * _Nonnull)attributeName
                    serviceName:(NSString * _Nonnull)serviceName
           authenticationPrompt:(NSString * _Nonnull)prompt
              completionHandler:(KeychainStorageGetDataHandler _Nonnull)handler;

+ (void)removeDataForAttributeName:(NSString * _Nonnull)attributeName
                       serviceName:(NSString * _Nonnull)serviceName
                 completionHandler:(KeychainStorageActionHandler _Nullable)handler;

@end
