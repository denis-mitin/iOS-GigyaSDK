#import "GSLogger.h"

@interface GSLogger ()

@property (nonatomic, strong) NSMutableDictionary *contextLogs;

@end

@implementation GSLogger

+ (GSLogger *)sharedInstance
{
    static dispatch_once_t onceToken;
    static GSLogger *instance;
    
    dispatch_once(&onceToken, ^{
        instance = [[GSLogger alloc] init];
    });
    
    return instance;
}

- (GSLogger *)init
{
    self = [super init];
    
    if (self)
    {
        self.contextLogs = [NSMutableDictionary dictionary];
        self.enabled = [[[NSBundle mainBundle] infoDictionary][@"GigyaLogEnabled"] boolValue];
        
//#ifdef DEBUG
//        self.enabled = YES;
//#endif
    }
    
    return self;
}

- (void)log:(NSString *)format, ...
{
    if (self.enabled) {
        va_list ap;
        va_start(ap, format);
        
        NSLog(@"%@", [self fullLogMessageFor:format arguments:ap]);
        
        va_end(ap);
    }
}

- (void)logInContext:(id<GSLoggerContext>)context format:(NSString *)format, ...
{
    NSString *contextID = [context contextID];
    va_list ap;
    va_start(ap, format);
    
    NSString *logMessage = [self fullLogMessageFor:format arguments:ap];
    
    // If no log for the context, creating one
    if (!(self.contextLogs)[contextID]) {
        [self.contextLogs setValue:[NSMutableArray array] forKey:contextID];
    }
    
    // Saving the log message for the context
    [(self.contextLogs)[contextID] addObject:logMessage];
    
    if (self.enabled)
        NSLog(@"%@", logMessage);
    
    va_end(ap);
}

- (NSString *)fullLogMessageFor:(NSString *)format arguments:(va_list)args
{
    // Caller data
    NSString *source = [NSThread callStackSymbols][2];
    NSCharacterSet *seperatorSet = [NSCharacterSet characterSetWithCharactersInString:@" -[]+?.,"];
    NSMutableArray *array = [NSMutableArray arrayWithArray:[source  componentsSeparatedByCharactersInSet:seperatorSet]];
    [array removeObject:@""];
    
    // Message received
    NSString *fullFormat = [NSString stringWithFormat:@"GigyaSDK: [%@ %@ %@] %@", array[2], array[3], array[4], format];
    NSString *message = [[NSString alloc] initWithFormat:fullFormat arguments:args];
    
    return message;
}

+ (void)clear:(id<GSLoggerContext>)context
{
    [[[GSLogger sharedInstance] contextLogs] removeObjectForKey:[context contextID]];
}

+ (NSString *)logForContext:(id<GSLoggerContext>)context
{
    NSArray *messages = [[GSLogger sharedInstance] contextLogs][[context contextID]];
    
    if ([messages count] > 0)
        return [messages componentsJoinedByString:@"\n"];
    
    return nil;
}

@end
