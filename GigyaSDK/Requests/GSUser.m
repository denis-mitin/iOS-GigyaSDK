#import "GSUser.h"
#import "GSObject+Internal.h"

@implementation GSUser

- (NSString *)UID {
    return self[@"UID"];
}

- (NSString *)nickname {
    return self[@"nickname"];
}

- (NSString *)loginProvider {
    return self[@"loginProvider"];
}

- (NSString *)firstName {
    return self[@"firstName"];
}

- (NSString *)lastName {
    return self[@"lastName"];
}

- (NSString *)email {
    return self[@"email"];
}

- (NSArray *)identities {
    return self[@"identities"];
}

- (NSURL *)photoURL {
    NSString *urlString = self[@"photoURL"];
    
    if ([urlString length] > 0)
        return [NSURL URLWithString:urlString];
    
    return nil;
}

- (NSURL *)thumbnailURL {
    NSString *urlString = self[@"thumbnailURL"];
    
    if ([urlString length] > 0)
        return [NSURL URLWithString:urlString];
    
    return nil;
}

- (NSString *)description
{
    NSMutableDictionary *dictForPrint = [[NSMutableDictionary alloc] init];
    
    if (self.dictionary)
        dictForPrint[@"response"] = self.dictionary;
    if (self.method)
        dictForPrint[@"method"] = self.method;
    
    return [NSString stringWithFormat:@"GSUser = %@", dictForPrint];
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
