#import "GSAccount.h"
#import "GSObject+Internal.h"

@implementation GSAccount

- (NSString *)UID {
    return self[@"UID"];
}

- (NSDictionary *)profile {
    return self[@"profile"];
}

- (NSDictionary *)data {
    return self[@"data"];
}

- (NSString *)nickname {
    return (self.profile)[@"nickname"];
}

- (NSString *)firstName {
    return (self.profile)[@"firstName"];
}

- (NSString *)lastName {
    return (self.profile)[@"lastName"];
}

- (NSString *)email {
    return (self.profile)[@"email"];
}

- (NSURL *)photoURL {
    return [self URLForKey:@"photoURL"];
}

- (NSURL *)thumbnailURL {
    return [self URLForKey:@"thumbnailURL"];
}

- (NSString *)description
{
    NSDictionary *dictForPrint = @{ @"method": self.method,
                                    @"response": self.dictionary };
    return [NSString stringWithFormat:@"GSUser = %@", dictForPrint];
}

#pragma mark - Utility methods
- (NSURL *)URLForKey:(NSString *)key {
    NSString *urlString = (self.profile)[key];
    
    if ([urlString length] > 0)
        return [NSURL URLWithString:urlString];
    
    return nil;
}

#pragma mark - GSObject's wrapper methods
- (id)objectForKeyedSubscript:(NSString *)key
{
    return [super objectForKeyedSubscript:key];
}

- (id)objectForKey:(NSString *)key
{
    return [super objectForKey:key];
}

- (NSArray *)allKeys
{
    return [super allKeys];
}

- (NSString *)JSONString
{
    return [super JSONString];
}

@end
