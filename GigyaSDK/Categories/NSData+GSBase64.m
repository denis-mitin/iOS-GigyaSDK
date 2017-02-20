#import "NSData+GSBase64.h"

// 'Base64Transcoder' external library is being used for supporting iOS 6. From iOS 7 we can use NSData's Base64 built-in capabilities
#import "Base64Transcoder.h"

@implementation NSData (GSBase64)

+ (NSData *)GSDataFromBase64String:(NSString *)base64String
{
    size_t length = base64String.length;
    unsigned char *input = (unsigned char *)[base64String UTF8String];
    unsigned char *output = malloc(length);
    
    Base64DecodeData(input, length, output, &length);
    NSData *result = [NSData dataWithBytesNoCopy:output length:length freeWhenDone:YES];
    
    return result;
}


- (NSString *)GSBase64SEncodedString
{
    size_t inputLength = self.length;
    size_t resultLength = EstimateBas64EncodedDataSize(inputLength);
    
    char *result = malloc(resultLength);
    Base64EncodeData([self bytes], inputLength, result, &resultLength);
    NSString *base64String = [[NSString alloc] initWithBytes:result length:resultLength encoding:NSASCIIStringEncoding];
    free(result);
    
    return base64String;
}

@end
