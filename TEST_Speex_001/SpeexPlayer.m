//
//  SpeexPlayer.m
//  TEST_Speex_001
//
//  Created by cxjwin on 13-6-28.
//  Copyright (c) 2013年 caixuejun. All rights reserved.
//

#import "SpeexPlayer.h"
#define kPcmFrameSize 160 // 8000(8khz) * (1000msec / 20msec)hz = 160

@implementation SpeexPlayer

#pragma mark - static functions

static int frameCountHalfSecond = 0;

static void HandleOutputBuffer(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) 
{
    SpeexPlayer *player = (__bridge SpeexPlayer *)inUserData;
    
    if (player->fp == NULL) {
        return;
    }
    
    if (player->fp) {// 文件打开
        
        size_t size = sizeof(short) * kPcmFrameSize * frameCountHalfSecond;
        AudioSampleType *pcmBuf = malloc(size);
        memset(pcmBuf, 0, size);
        
        float output[kPcmFrameSize];
        
        SpeexBits bits;
        speex_bits_init(&bits);
        
        size_t nbytes = 0;
        int readFrame = 0;
        for (int frame = 0; frame < frameCountHalfSecond; frame++) {
            if (fread(&nbytes, sizeof(int), 1, player->fp) < 1) {                
                break;
            }
            
            char analysis[nbytes];
            if (fread(analysis, sizeof(char), nbytes, player->fp) < nbytes) {
                break;
            }
            
            speex_bits_read_from(&bits, analysis, nbytes);
            speex_decode(player->decoder, &bits, output);
            
            for (int i = 0; i < kPcmFrameSize; i++) {
                pcmBuf[kPcmFrameSize * frame + i] = output[i];
            }
            
            readFrame = frame;
        }
        speex_bits_destroy(&bits);
        
        if (readFrame > 0) {
            inBuffer->mAudioDataByteSize = readFrame * sizeof(AudioSampleType) * kPcmFrameSize;
            inBuffer->mPacketDescriptionCount = readFrame * kPcmFrameSize;
            memcpy(inBuffer->mAudioData, pcmBuf, readFrame * sizeof(AudioSampleType) * kPcmFrameSize);
            AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
        } else {
            AudioQueueStop(inAQ, FALSE);
            if (player->fp) {
                fclose(player->fp), player->fp = NULL;
            }
        }
        
        free(pcmBuf), pcmBuf = NULL;
    }
}

static void PlayerIsRunningProc(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    SpeexPlayer *player = (__bridge SpeexPlayer *)inUserData;
    UInt32 isPlaying;
    UInt32 size = sizeof(isPlaying);
    OSStatus result = AudioQueueGetProperty(inAQ, kAudioQueueProperty_IsRunning, &isPlaying, &size);
    if (result == noErr) {
        player.isPlaying = isPlaying;
        if (isPlaying) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kOutputAudioQueueStarted object:nil];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:kOutputAudioQueueStopped object:nil];
        }
    }
}

- (id)init {
    self = [super init];
    if (self) {
        int tmp = 1;
        decoder = speex_decoder_init(&speex_nb_mode);
        speex_decoder_ctl(decoder, SPEEX_SET_ENH, &tmp);
    }
    return self;
}

- (void)dealloc {
    for (int i = 0; i < kNumberBuffers; i++) {
        AudioQueueFreeBuffer(queue, buffers[i]);
    }
    AudioQueueDispose(queue, true), queue = NULL;
    speex_decoder_destroy(decoder), decoder = NULL;
    if (fp) {
        fclose(fp), fp = NULL;
    }
}

- (BOOL)startPlayingWithSpeexFilePath:(NSString *)amrFilePath error:(NSError **)error {
    if ([self stopPlaying:error] == NO) {
        return NO;
    }
    
    frameCountHalfSecond = 0;
    const char *filePath = [amrFilePath UTF8String];
    if ([self checkFile:filePath]) {
        
        OSStatus status;
        status = 
        AudioQueueNewOutput(&dataFormat, HandleOutputBuffer, (__bridge void *)(self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &queue);
        
        status = AudioQueueAddPropertyListener(queue, kAudioQueueProperty_IsRunning, PlayerIsRunningProc, (__bridge void *)(self));
        
        UInt32 bufferByteSize =
        (UInt32)dataFormat.mSampleRate * dataFormat.mBytesPerPacket * kBufferDurationSeconds;
        for (int i = 0; i < kNumberBuffers; i++) {
            status = AudioQueueAllocateBuffer(queue, bufferByteSize, &buffers[i]);
        }
        
        status = AudioQueueSetParameter (queue, kAudioQueueParam_Volume, 1.0);
        
        status = [self startQueue];
        if (status) {
            if (error) {
                NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"couldn't start audio queue"
                                                                     forKey:NSLocalizedDescriptionKey];
                *error = [NSError errorWithDomain:kSpeexErrorDomain
                                             code:status
                                         userInfo:userInfo];
            }
            return NO;
        }
    } else {
        if (error) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"couldn't check speex file"
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:kSpeexErrorDomain
                                         code:0
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)checkFile:(const char *)speexFileName {
    char magic[SPEEX_HEADER_STRING_LENGTH] = "Speex   ";
    fp = fopen(speexFileName, "rb");
    if (ferror(fp)) {
#ifdef DEBUG
        NSLog(@"打开Speex文件失败.");
#endif
        clearerr(fp);
        return NO;
    }
    
    SpeexHeader speexHeader;
    fread(&speexHeader, sizeof(SpeexHeader), 1, fp);
    if (ferror(fp)) {
#ifdef DEBUG
        NSLog(@"Speex文件头读取失败.");
#endif
        clearerr(fp);
        fclose(fp);
        return NO;
    }
    
    if (strncmp(speexHeader.speex_string, magic, SPEEX_HEADER_STRING_LENGTH)) {
#ifdef DEBUG
        NSLog(@"Speex文件头不匹配.");
#endif
        fclose(fp);
        return NO;
    }
    
    frameCountHalfSecond = speexHeader.rate / speexHeader.frame_size * kBufferDurationSeconds;
    
    memset(&dataFormat, 0, sizeof(AudioStreamBasicDescription));
    dataFormat.mSampleRate = speexHeader.rate;
    dataFormat.mFormatID = kAudioFormatLinearPCM;
    dataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    dataFormat.mChannelsPerFrame = speexHeader.nb_channels; // mono
    dataFormat.mBitsPerChannel = 8 * sizeof(AudioSampleType);
    dataFormat.mFramesPerPacket = 1;
    dataFormat.mBytesPerFrame = sizeof(AudioSampleType) * dataFormat.mChannelsPerFrame;
    dataFormat.mBytesPerPacket = dataFormat.mBytesPerFrame * dataFormat.mFramesPerPacket;
    
    return YES;
}

- (int)readPacketsIntoBuffer:(AudioQueueBufferRef)buffer {
    
    size_t size = sizeof(short) * frameCountHalfSecond * kPcmFrameSize;
    short *pcmBuf = (short *)malloc(size);
    memset(pcmBuf, 0, size);
    float output[kPcmFrameSize];
    
    SpeexBits bits;
    speex_bits_init(&bits);
    
    int nbytes = 0;
    int readFrame = 0;
    for (int frame = 0; frame < frameCountHalfSecond; frame++) {
        fread(&nbytes, sizeof(int), 1, fp);
        if (ferror(fp)) {
            clearerr(fp);
            break;
        }
        
        char analysis[nbytes];
        fread(analysis, sizeof(char), nbytes, fp);
        if (ferror(fp)) {
            clearerr(fp);
            break;
        }
        
        speex_bits_read_from(&bits, analysis, nbytes);
        speex_decode(decoder, &bits, output);
        
        for (int i = 0; i < kPcmFrameSize; i++) {
            pcmBuf[kPcmFrameSize * frame + i] = output[i];
        }
        
        readFrame = frame;
    }
    speex_bits_destroy(&bits);
    
    if (readFrame > 0) {
        buffer->mAudioDataByteSize = readFrame * 2 * kPcmFrameSize;
        buffer->mPacketDescriptionCount = readFrame * kPcmFrameSize;
        memcpy(buffer->mAudioData, pcmBuf, readFrame * 2 * kPcmFrameSize);
        AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    }
    
    free(pcmBuf), pcmBuf = NULL;
    
    return readFrame;
}

- (OSStatus)startQueue {
    for (int i = 0; i < kNumberBuffers; ++i) {        
        HandleOutputBuffer((__bridge void *)(self), queue, buffers[i]);
    }
    return AudioQueueStart(queue, NULL);
}

- (BOOL)stopPlaying:(NSError **)error {
    OSStatus status = noErr;
    if (self.isPlaying) {
        status = AudioQueueStop(queue, TRUE);
        if (status && error) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"couldn't stop audio queue"
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:kSpeexErrorDomain
                                         code:status
                                     userInfo:userInfo];
        }
        
        if (fp) {
            fclose(fp), fp = NULL;
        }
    }
    self.isPlaying = NO;
    return (status == noErr);
}

@end
