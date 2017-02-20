#import <Foundation/Foundation.h>
#import "Gigya.h"

@interface NSURL (GSURL)

+ (NSURL *)URLForGigyaProviderSelection:(NSDictionary *)params
                                session:(GSSession *)session;
+ (NSURL *)URLForGigyaLoginMethod:(NSString *)method
                       parameters:(NSDictionary *)params
                redirectURLScheme:(NSString *)urlScheme
                          session:(GSSession *)session;
+ (NSURL *)URLForGigyaReferralReportForURL:(NSURL *)url provider:(NSString *)provider;


@end
