#pragma once

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#import "libretro.h"
#import "AudioRingBuffer.hpp"

#ifndef RETRO_DEVICE_WIIMOTE_CC
#define RETRO_DEVICE_WIIMOTE_CC 513
#endif

typedef void (^VideoFrameCallback)(const void *data, int width, int height, int pitch, int format);

@interface LibretroBridgeImpl : NSObject {
@public
  void *_dlHandle;
  fn_retro_set_controller_port_device _retro_set_controller_port_device;
  fn_retro_init _retro_init;
  fn_retro_deinit _retro_deinit;
  fn_retro_set_environment _retro_set_environment;
  fn_retro_set_video_refresh _retro_set_video_refresh;
  fn_retro_set_audio_sample _retro_set_audio_sample;
  fn_retro_set_audio_sample_batch _retro_set_audio_sample_batch;
  fn_retro_set_input_poll _retro_set_input_poll;
  fn_retro_set_input_state _retro_set_input_state;
  fn_retro_get_system_info _retro_get_system_info;
  fn_retro_load_game _retro_load_game;
  fn_retro_unload_game _retro_unload_game;
  fn_retro_run _retro_run;
  fn_retro_get_system_av_info _retro_get_system_av_info;
  fn_retro_serialize_size _retro_serialize_size;
  fn_retro_serialize _retro_serialize;
  fn_retro_unserialize _retro_unserialize;
  fn_retro_cheat_set _retro_cheat_set;
  fn_retro_cheat_reset _retro_cheat_reset;
  fn_retro_get_memory_data _retro_get_memory_data;
  fn_retro_get_memory_size _retro_get_memory_size;
  
  BOOL _running;
  VideoFrameCallback _videoCallback;
  AVAudioEngine *_audioEngine;
  AVAudioSourceNode *_audioSourceNode;
  AudioRingBuffer *_audioBuffer;

  int16_t *_audioRenderScratch;
  size_t _audioRenderScratchCapacity;

  CGLContextObj _glContext;
  struct retro_hw_render_callback _hw_callback;
  struct retro_system_av_info _avInfo;

  int _pixelFormat;
  BOOL _isMameLaunch; 
  NSString *_saveStatePath;

  NSData *_retainedRomData;
  NSString *_retainedRomPath;

  void *_hwReadbackBuffer;
  size_t _hwReadbackBufferSize;
  BOOL _hwRenderEnabled;
  GLuint _hwFBO;     
  GLuint _hwColorRB; 
  GLuint _hwDepthRB; 
  int _fboWidth;
  int _fboHeight;

  NSLock *_coreLock;
  size_t _cachedSerializeSize;
}

- (BOOL)loadDylib:(NSString *)path;
- (BOOL)launchROM:(NSString *)romPath videoCallback:(VideoFrameCallback)cb;
- (void)stop;
- (void)saveState;
- (NSData *)serializeState;
- (BOOL)unserializeState:(NSData *)data;
- (void)handleVideoData:(const void *)data width:(int)w height:(int)h pitch:(int)pitch format:(int)format;
- (void)handleAudioSamples:(const int16_t *)data count:(size_t)count;
- (void)setKeyState:(int)retroID pressed:(BOOL)pressed;
- (void)setTurboState:(int)idx active:(BOOL)active targetButton:(int)targetIdx;
- (void)setAnalogState:(int)idx id:(int)id value:(int)v;
- (void)setPixelFormat:(int)format;
- (int)pixelFormat;
- (void)setupHWRender:(struct retro_hw_render_callback *)cb;
- (const void *)readHWRenderedPixels:(int)w height:(int)h;
- (void)setControllerPortDevice:(unsigned)port device:(unsigned)device;

@end