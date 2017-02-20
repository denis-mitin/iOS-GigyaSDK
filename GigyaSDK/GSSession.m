#import "GSSession.h"
#import "Gigya.h"

@implementation GSSession

- (GSSession *)initWithSessionToken:(NSString *)token
                             secret:(NSString *)secret
{
    return [self initWithSessionToken:token secret:secret expiration:nil];
}

- (GSSession *)initWithSessionToken:(NSString *)token
                             secret:(NSString *)secret
                          expiresIn:(NSString *)expiresIn
{
    NSDate *expiration = nil;
    
    if (expiresIn && ![expiresIn isEqualToString:@"0"])
        expiration = [NSDate dateWithTimeIntervalSinceNow:[expiresIn floatValue]];
    
    return [self initWithSessionToken:token secret:secret expiration:expiration];
}

- (GSSession *)initWithSessionToken:(NSString *)token
                             secret:(NSString *)secret
                         expiration:(NSDate *)expiration
{
    self = [super init];
    
    if (self) {
        self.token = token;
        self.secret = secret;
        self.info = [[GSSessionInfo alloc] initWithAPIKey:[Gigya APIKey] expiration:expiration];
    }
    
    return self;
}

#pragma mark - NSCoding methods
- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:self.token forKey:@"authToken"];
    [encoder encodeObject:self.secret forKey:@"secret"];
    [encoder encodeObject:self.lastLoginProvider forKey:@"lastLoginProvider"];

    [encoder encodeObject:self.info forKey:@"info"];
}

- (GSSession *)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    
    if (self) {
        self.token = [decoder decodeObjectForKey:@"authToken"];
        self.secret = [decoder decodeObjectForKey:@"secret"];
        self.lastLoginProvider = [decoder decodeObjectForKey:@"lastLoginProvider"];

        if ([decoder containsValueForKey:@"info"])
            self.info = [decoder decodeObjectForKey:@"info"];
        else // for backwards compatibility
            self.info = [[GSSessionInfo alloc] initWithAPIKey:[Gigya APIKey] expiration:[decoder decodeObjectForKey:@"expiration"]];
    }
    
    return self;
}

#pragma mark - Other methods
- (BOOL)isValid
{
    if (self.token && self.secret && [self.info isValid]) {
        return YES;
    }
    
    return NO;
}

#pragma mark - Overrides
- (NSString *)description {
    return self.token;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[GSSession class]])
        return NO;
    
    return ([self.token isEqualToString:[object token]] &&
            [self.secret isEqualToString:[object secret]]);
}

@end
