#import "GSSessionInfo.h"
#import "Gigya.h"

@implementation GSSessionInfo

- (GSSessionInfo *)initWithAPIKey:(NSString *)APIKey
                       expiration:(NSDate *)expiration
{
    self = [super init];
    
    if (self) {
        self.APIKey = APIKey;
        self.expiration = expiration;
    }
    
    return self;
}

- (BOOL)isValid
{
    if ([self.APIKey isEqual:[Gigya APIKey]] &&
        [self.expiration timeIntervalSinceNow] >= 0) {
        return YES;
    }
    
    return NO;
}

#pragma mark - NSCoding methods

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:self.APIKey forKey:@"APIKey"];
    [encoder encodeObject:self.expiration forKey:@"expiration"];
}

- (GSSessionInfo *)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    
    if (self) {
        self.APIKey = [decoder decodeObjectForKey:@"APIKey"];
        self.expiration = [decoder decodeObjectForKey:@"expiration"];
    }
    
    return self;
}

@end
