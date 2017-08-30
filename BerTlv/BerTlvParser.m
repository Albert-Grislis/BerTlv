//
// Created by Evgeniy Sinev on 05/08/14.
// Copyright (c) 2014 Evgeniy Sinev. All rights reserved.
//

#import "BerTlvParser.h"
#import "BerTlv.h"
#import "HexUtil.h"
#import "BerTag.h"
#import "BerTlvs.h"
#import "BerTlvErrors.h"


static int IS_DEBUG_ENABLED = 0;

@implementation BerTlvParser

- (BerTlv *)parseConstructed:(NSData *)aData error:(NSError **)error {
    uint result=0;
    BerTlv * ret = [self parseWithResult:&result data:aData offset:0 len:(uint)aData.length level:0 error: error];
    return ret;
}

- (BerTlvs *)parseTlvs:(NSData *)aData error:(NSError **)error {
    return [self parseTlvs:aData numberOfTags:100 error:error];
}

- (BerTlvs *)parseTlvs:(NSData *)aData numberOfTags:(NSUInteger) numberOfTags error:(NSError **)error {
    if(aData.length==0) {
        return [[BerTlvs alloc] init:[[NSArray alloc] init]];
    }

    NSMutableArray *list = [[NSMutableArray alloc] init];
    int offset = 0;
    for(uint i=0; i<numberOfTags; i++) {
        uint result=0;
        BerTlv * ret = [self parseWithResult:&result data:aData offset:offset len:(uint)aData.length-offset level:0 error:error];
        [list addObject:ret];

        if (result >= aData.length) {
            break;
        }

        offset = result;
    }

    return [[BerTlvs alloc] init:list];
}

- (BerTlv *)parseWithResult:(uint*)aOutResult
                       data:(NSData *)aBuf
                     offset:(uint)aOffset
                        len:(uint)aLen
                      level:(uint)aLevel
                      error:(NSError **)error
{
    if(aOffset+aLen > aBuf.length) {
        if (error) {
            *error = [BerTlvErrors outOfRangeAtOffset:aOffset length:aLen bufferLength:(unsigned long) aBuf.length level:aLevel];
        }
    }

    NSString *levelPadding = IS_DEBUG_ENABLED ? [self createLevelPadding:aLevel] : @"";
    if(IS_DEBUG_ENABLED) {
        NSLog(@"%@parseWithResult( level=%d, offset=%d, len=%d, buf=%@)"
                , levelPadding, aLevel, aOffset, aLen, [HexUtil format:aBuf]
        );
    }

    // TAG
    uint tagBytesCount = [self calcTagBytesCount:aBuf offset:aOffset];
    BerTag *tag = [self createTag:aBuf offset:aOffset len:tagBytesCount pad:levelPadding];

    // LENGTH
    uint lengthBytesCount = [self calcLengthBytesCount:aBuf offset:aOffset + tagBytesCount];
    NSError *lengthErr;
    uint valueLength = [self calcDataLength:aBuf offset:aOffset + tagBytesCount error:&lengthErr];
    if (lengthErr && error) {
        *error = lengthErr;
    }

    if(IS_DEBUG_ENABLED) {
        NSLog(@"%@lenBytesCount = %d, len = %d, lenBuf = %@"
                , levelPadding, lengthBytesCount, valueLength, [HexUtil format:aBuf offset:aOffset + tagBytesCount len:lengthBytesCount]);
    }

    // VALUE
    if(tag.isConstructed) {
        NSMutableArray *array = [[NSMutableArray alloc] init];
        [self addChildren:aBuf
                   offset:aOffset
                    level:aLevel
             levelPadding:levelPadding
            tagBytesCount:tagBytesCount
           dataBytesCount:lengthBytesCount
              valueLength:valueLength
                    array:array
        ];
        uint resultOffset = aOffset + tagBytesCount + lengthBytesCount + valueLength;
        if(IS_DEBUG_ENABLED) {
            NSLog(@"%@Returning constructed offset = %d", levelPadding, resultOffset );
        }
        *aOutResult = resultOffset;
        return [[BerTlv alloc] init:tag array:array];

    } else {
        NSRange range = {aOffset+tagBytesCount+lengthBytesCount, valueLength};
        NSData *value = [aBuf subdataWithRange:range];
        uint resultOffset = aOffset + tagBytesCount + lengthBytesCount + valueLength;

        if(IS_DEBUG_ENABLED) {
            NSLog(@"%@Primitive value = %@", levelPadding, [HexUtil format:value]);
            NSLog(@"%@Returning primitive offset = %d", levelPadding, resultOffset );
        }
        *aOutResult = resultOffset;
        return [[BerTlv alloc] init:tag value:value];
    }
}

- (uint)calcTagBytesCount:(NSData *)aBuf offset:(uint)aOffset {
    uint8_t const *bytes = aBuf.bytes;
    if((bytes[aOffset] & 0x1F) == 0x1F) { // see subsequent bytes
        uint len = 2;
        for(int i=aOffset+1; i<aOffset+10; i++) {
            if( (bytes[i] & 0x80) != 0x80) {
                break;
            }
            len++;
        }
        return len;
    } else {
        return 1;
    }
}

- (BerTag *) createTag:(NSData *)aBuf offset:(uint)aOffset len:(uint)aLen pad:(NSString *)aLevelPadding {
    BerTag *tag = [[BerTag alloc] init:aBuf offset:aOffset length:aLen];
    if(IS_DEBUG_ENABLED) {
        NSLog(@"%@Created tag %@ from buffer %@", aLevelPadding, tag, [HexUtil format:aBuf offset:aOffset len:aLen]);
    }
    return tag;
}

- (NSString *)createLevelPadding:(NSUInteger)aLevel {
    NSMutableString *sb = [NSMutableString stringWithCapacity:aLevel];
    for(int i=0; i<aLevel*4; i++) {
        [sb appendString:@" "];
    }
    return sb;
}

- (uint) calcLengthBytesCount:(NSData *)aBuf offset:(uint)aOffset {
    uint8_t const *bytes = aBuf.bytes;
    uint len = (uint) bytes[aOffset];
    if( (len & 0x80) == 0x80) {
        return (uint) (1 + (len & 0x7f));
    } else {
        return 1;
    }
}

-(uint) calcDataLength:(NSData *)aBuf offset:(uint) aOffset error:(NSError **)error {
    uint8_t const *bytes = aBuf.bytes;
    uint length = bytes[aOffset];

    if((length & 0x80) == 0x80) {
        int numberOfBytes = length & 0x7f;
        if(numberOfBytes>3) {
            if (error) {
                *error = [BerTlvErrors badLengthAtOffset:aOffset numberOfBytes:numberOfBytes];
            }
        }

        length = 0;
        for(int i=aOffset+1; i<aOffset+1+numberOfBytes; i++) {
            length = length * 0x100 + bytes[i];
        }

    }
    return length;
}

- (void) addChildren:(NSData *)aBuf
              offset:(uint)aOffset
               level:(uint)aLevel
        levelPadding:(NSString *)aLevelPadding
       tagBytesCount:(uint)aTagBytesCount
      dataBytesCount:(uint)aDataBytesCount
         valueLength:(uint)aValueLength
               array:(NSMutableArray *)aList
{

    uint startPosition = aOffset + aTagBytesCount + aDataBytesCount;
    uint len = aValueLength;

    while (startPosition < aOffset + aValueLength) {
        uint result = 0;
        BerTlv *tlv = [self parseWithResult:&result data:aBuf offset:startPosition len:len level:aLevel+1 error:nil];
        [aList addObject:tlv];

        startPosition = result;
        len           = aValueLength - startPosition;

        if(IS_DEBUG_ENABLED) {
            NSLog(@"%@level %d: adding %@ with offset %d, startPosition=%d, aDataBytesCount=%d, valueLength=%d"
                    , aLevelPadding, aLevel, tlv.tag, result, startPosition,  aDataBytesCount, aValueLength
            );
        }
    }

}

@end
