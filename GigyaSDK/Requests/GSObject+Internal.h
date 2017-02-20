#import "GSObject.h"

@interface GSObject (Internal)

@property (nonatomic, strong) NSMutableDictionary *dictionary;
- (void)addJSONData:(NSData *)data;

@end
