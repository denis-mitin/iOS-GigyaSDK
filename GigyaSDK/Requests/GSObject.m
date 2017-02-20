#import "GSObject.h"
#import "Gigya+Internal.h"

@interface GSObject ()

@property (nonatomic, strong) NSMutableDictionary *dictionary;

@end

@implementation GSObject

- (GSObject *)init
{
    self = [super init];
    
    if (self) {
        self.dictionary = [NSMutableDictionary dictionary];
    }
    
    return self;
}

#pragma mark - Dictionary & subscript methods
- (id)objectForKeyedSubscript:(NSString *)key
{
    return (self.dictionary)[key];
}

- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key
{
    (self.dictionary)[key] = obj;
}

- (id)objectForKey:(NSString *)key
{
    return (self.dictionary)[key];
}

- (void)setObject:(id)obj forKey:(NSString *)key
{
    (self.dictionary)[key] = obj;
}

- (void)removeObjectForKey:(NSString *)key
{
    [self.dictionary removeObjectForKey:key];
}

- (NSArray *)allKeys
{
    return [self.dictionary allKeys];
}

#pragma mark - JSON handling
- (void)addJSONData:(NSData *)data
{
    NSError *jsonError;
    
    // Parsing the received JSON data
    id serializedJson = [NSJSONSerialization JSONObjectWithData:data
                                                        options:(NSJSONReadingAllowFragments | NSJSONReadingMutableContainers)
                                                          error:&jsonError];
    // If serialization was successful
    if (serializedJson) {
        if ([serializedJson isKindOfClass:[NSDictionary class]]) {
            self.dictionary = nil;
            self.dictionary = serializedJson;
        }
        else if ([serializedJson isKindOfClass:[NSArray class]]) {
            [self.dictionary removeAllObjects];
            (self.dictionary)[@"data"] = serializedJson;
        }
    }
    else {
        GSLog(@"Error parsing JSON data: %@", jsonError);
    }
}

- (NSString *)JSONString
{
    NSError *error = nil;
    @try {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.dictionary
                                                           options:0
                                                             error:&error];
        NSString *jsonString = [[NSString alloc] initWithData:jsonData
                                                      encoding:NSUTF8StringEncoding];
        
        return jsonString;
    }
    @catch (NSException *exception) {
    }

    return @"";
}

#pragma mark - Overrides
- (NSString *)description
{
    return [self.dictionary description];
}



@end
