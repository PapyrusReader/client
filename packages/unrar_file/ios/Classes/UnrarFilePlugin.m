#import "UnrarFilePlugin.h"
@import UnrarKit;

static inline NSString* NSStringFromBOOL(BOOL aBool) {
    return aBool? @"SUCCESS" : @"FAILURE";
}

@implementation UnrarFilePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"unrar_file"
            binaryMessenger:[registrar messenger]];
  UnrarFilePlugin* instance = [[UnrarFilePlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"extractRAR" isEqualToString:call.method]) {
    NSString* file_path = call.arguments[@"file_path"];
    NSString* destination_path = call.arguments[@"destination_path"];
    NSString* password = call.arguments[@"password"];
    NSError *archiveError = nil;
    URKArchive *archive = [[URKArchive alloc] initWithPath:file_path
                                                 error:&archiveError];
    NSError *error = nil;
      BOOL extractFilesSuccessful;
    if (archive.isPasswordProtected && password.length!=0) {
        archive.password = password;
    }
    extractFilesSuccessful = [archive extractFilesTo:destination_path overwrite:NO
        error:&error];

    result(NSStringFromBOOL(extractFilesSuccessful));
  } else {
    result(FlutterMethodNotImplemented);
  }
}

@end
