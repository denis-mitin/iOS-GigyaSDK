#import "NSURL+GSURL.h"
#import "NSDictionary+GSDictionary.h"
#import "Gigya+Internal.h"

@implementation NSURL (GSURL)

+ (NSURL *)URLForGigyaProviderSelection:(NSDictionary *)params
                                session:(GSSession *)session
{
    NSString *http = ([Gigya useHTTPS] ? @"https" : @"http");
    
    NSMutableDictionary *startParams = [@{ @"apiKey": [Gigya APIKey],
                                           @"redirect_uri": [NSString stringWithFormat:@"%@://%@", GSRedirectURLScheme, GSRedirectURLNetworkSelected],
                                           @"sdk": GSGigyaSDKVersion,
                                           @"iosVersion": [[UIDevice currentDevice] systemVersion] } mutableCopy];
    
    if (session && session.token)
        startParams[@"oauth_token"] = session.token;
    
    [startParams addEntriesFromDictionary:params];
    
    NSString *url = [NSString stringWithFormat:@"%@://socialize.%@/gs/mobile/LoginUI.aspx?%@", http, [Gigya APIDomain], [startParams GSURLQueryString]];
    
    return [NSURL URLWithString:url];
}

+ (NSURL *)URLForGigyaLoginMethod:(NSString *)method
                       parameters:(NSDictionary *)params
                redirectURLScheme:(NSString *)urlScheme
                          session:(GSSession *)session
{
    NSDictionary *loginParameters = [NSURL DictionaryForGigyaLoginMethod:method parameters:params redirectURLScheme:urlScheme session:session];
    return [NSURL URLForGigyaLoginMethodParameters:loginParameters method:method redirectURLScheme:urlScheme];
}

+ (NSDictionary *)DictionaryForGigyaLoginMethod:(NSString *)method
                                     parameters:(NSDictionary *)params
                              redirectURLScheme:(NSString *)urlScheme
                                        session:(GSSession *)session
{
    NSString *provider = params[@"provider"];
    NSString *source = params[@"loginRequestSource"];
    NSMutableDictionary *mutableParams = [params mutableCopy];
    
    NSMutableDictionary *loginParameters = [@{ @"client_id": [Gigya APIKey],
                                                @"response_type": @"token",
                                                @"sdk": GSGigyaSDKVersion,
                                                @"redirect_uri": [NSString stringWithFormat:@"%@://%@", urlScheme, GSRedirectURLLoginResult],
                                                @"x_provider": provider,
                                                @"x_secret_type": @"oauth1" } mutableCopy];
    
    if ([Gigya sharedInstance].ucid)
        loginParameters[@"ucid"] = [Gigya sharedInstance].ucid;

    if (mutableParams[@"gmidTicket"])
        loginParameters[@"gmidTicket"] = mutableParams[@"gmidTicket"];
    else if ([Gigya sharedInstance].gmid)
        loginParameters[@"gmid"] = [Gigya sharedInstance].gmid;
    
    [mutableParams removeObjectsForKeys:@[@"ucid", @"gmid", @"gmidTicket"]];
    
    if (session.token)
        loginParameters[@"oauth_token"] = session.token;
    
    if ([source rangeOfString:@"js_"].location == 0) {
        [mutableParams removeObjectForKey:@"loginRequestSource"];
        [mutableParams removeObjectForKey:@"provider"];
        [mutableParams removeObjectForKey:@"captionText"];
        [mutableParams removeObjectForKey:@"forceModal"];
        
        [loginParameters addEntriesFromDictionary:mutableParams];
    }
    else {
        // Only if this isn't native login (meaning we don't have a provider token yet)
        if (!mutableParams[@"x_providerToken"]) {
            if (mutableParams[@"googleExtraPermissions"] && [provider rangeOfString:@"google"].location != NSNotFound) {
                loginParameters[@"x_extraPermissions"] = mutableParams[@"googleExtraPermissions"];
                [mutableParams removeObjectForKey:@"googleExtraPermissions"];
            }
            
            if (mutableParams[@"facebookExtraPermissions"] && [provider isEqualToString:@"facebook"]) {
                loginParameters[@"x_extraPermissions"] = mutableParams[@"facebookExtraPermissions"];
                [mutableParams removeObjectForKey:@"facebookExtraPermissions"];
            }
        }
        
        // Params who don't follow the x_paramName convention
        if (mutableParams[@"pendingRegistration"]) {
            loginParameters[@"x_pending_registration"] = mutableParams[@"pendingRegistration"];
            [mutableParams removeObjectForKey:@"pendingRegistration"];
        }
        
        if (mutableParams[@"temporaryAccount"]) {
            loginParameters[@"x_temporary_account"] = mutableParams[@"temporaryAccount"];
            [mutableParams removeObjectForKey:@"temporaryAccount"];
        }
        
        // Merging other params with x_paramName convention
        for (NSString *key in mutableParams) {
            NSString *newKey = key;
            if (![key hasPrefix:@"x_"])
                newKey = [NSString stringWithFormat:@"x_%@", key];
            
            loginParameters[newKey] = mutableParams[key];
        }
    }
    
    
    return loginParameters;
}

+ (NSURL *)URLForGigyaLoginMethodParameters:(NSDictionary *)params
                                     method:(NSString *)method
                          redirectURLScheme:(NSString *)urlScheme
{
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://socialize.%@/%@?%@", [Gigya APIDomain], method, [params GSURLQueryString]]];
}

+ (NSURL *)URLForGigyaReferralReportForURL:(NSURL *)url provider:(NSString *)provider
{
    NSMutableDictionary *params = [@{ @"f": @"re",
                                      @"e": @"linkback",
                                      @"url": url,
                                      @"sn": provider,
                                      @"sdk": GSGigyaSDKVersion,
                                      @"ak": [[Gigya sharedInstance] APIKey] } mutableCopy];
    
    if ([[Gigya sharedInstance] ucid])
        params[@"ucid"] = [[Gigya sharedInstance] ucid];
    
    NSString *counterURL = [NSString stringWithFormat:@"http://gscounters.%@/gs/api.ashx?%@", [Gigya APIDomain], [params GSURLQueryString]];

    return [NSURL URLWithString:counterURL];
}

@end
