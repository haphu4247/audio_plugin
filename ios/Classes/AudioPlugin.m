#import "AudioPlugin.h"
#if __has_include(<audio_plugin/audio_plugin-Swift.h>)
#import <audio_plugin/audio_plugin-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "audio_plugin-Swift.h"
#endif

@implementation AudioPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAudioPlugin registerWithRegistrar:registrar];
}
@end
