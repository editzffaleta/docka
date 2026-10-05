#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include "DockaTocando.h"

typedef void (*GetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetPID)(dispatch_queue_t, void (^)(int));
typedef void (*GetIsPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*Register)(dispatch_queue_t);
typedef Boolean (*SendCommand)(int, CFDictionaryRef);
typedef void (*SetElapsed)(double);

static void *mr(void) {
    static void *h;
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    return h;
}

static NSString *ultimaCapa;

/// Lê tudo e escreve uma linha. A capa só vai quando muda — ela é grande, e o
/// resto muda a cada pausa.
static void emitir(void) {
    GetInfo info = (GetInfo)dlsym(mr(), "MRMediaRemoteGetNowPlayingInfo");
    GetPID pid = (GetPID)dlsym(mr(), "MRMediaRemoteGetNowPlayingApplicationPID");
    GetIsPlaying tocando = (GetIsPlaying)dlsym(mr(), "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    if (!info || !pid || !tocando) return;
    dispatch_queue_t q = dispatch_get_main_queue();
    pid(q, ^(int p) {
        tocando(q, ^(Boolean t) {
            info(q, ^(CFDictionaryRef d) {
                NSDictionary *i = (__bridge NSDictionary *)d;
                NSMutableDictionary *o = [NSMutableDictionary dictionary];
                o[@"pid"] = @(p);
                o[@"tocando"] = @(t);
                if (i[@"kMRMediaRemoteNowPlayingInfoTitle"]) o[@"titulo"] = [i[@"kMRMediaRemoteNowPlayingInfoTitle"] description];
                if (i[@"kMRMediaRemoteNowPlayingInfoArtist"]) o[@"artista"] = [i[@"kMRMediaRemoteNowPlayingInfoArtist"] description];
                if (i[@"kMRMediaRemoteNowPlayingInfoAlbum"]) o[@"album"] = [i[@"kMRMediaRemoteNowPlayingInfoAlbum"] description];
                if ([i[@"kMRMediaRemoteNowPlayingInfoDuration"] isKindOfClass:NSNumber.class]) o[@"duracao"] = i[@"kMRMediaRemoteNowPlayingInfoDuration"];
                if ([i[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] isKindOfClass:NSNumber.class]) o[@"decorrido"] = i[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
                if ([i[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] isKindOfClass:NSNumber.class]) o[@"taxa"] = i[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
                if ([i[@"kMRMediaRemoteNowPlayingInfoTimestamp"] isKindOfClass:NSDate.class])
                    o[@"carimbo"] = @([(NSDate *)i[@"kMRMediaRemoteNowPlayingInfoTimestamp"] timeIntervalSince1970]);
                NSData *capa = i[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if ([capa isKindOfClass:NSData.class] && capa.length > 0) {
                    NSString *id = [NSString stringWithFormat:@"%lu-%@-%@", (unsigned long)capa.length, o[@"titulo"], o[@"album"]];
                    if (![id isEqualToString:ultimaCapa]) {
                        ultimaCapa = id;
                        o[@"capa"] = [capa base64EncodedStringWithOptions:0];
                    }
                    o[@"capaId"] = id;
                }
                NSData *json = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil];
                if (json) {
                    fwrite(json.bytes, 1, json.length, stdout);
                    fputc('\n', stdout);
                    fflush(stdout);
                }
            });
        });
    });
}

void docka_ouvir(void *interpretador, void *cv) {
    @autoreleasepool {
        Register reg = (Register)dlsym(mr(), "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (!reg) { fprintf(stderr, "sem MediaRemote\n"); exit(2); }
        reg(dispatch_get_main_queue());
        for (NSString *nome in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
            [[NSNotificationCenter defaultCenter] addObserverForName:nome object:nil
                                                               queue:NSOperationQueue.mainQueue
                                                          usingBlock:^(NSNotification *n) { emitir(); }];
        }
        // o Docka fechou a entrada: hora de sair (sem isto, o perl ficaria
        // rodando sozinho depois de o Docka encerrar)
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char b[64];
            while (fread(b, 1, sizeof b, stdin) > 0) {}
            exit(0);
        });
        emitir();
        CFRunLoopRun();
    }
    exit(0);
}

void docka_comando(void *interpretador, void *cv) {
    const char *pos = getenv("DOCKA_POSICAO");
    if (pos) {
        SetElapsed set = (SetElapsed)dlsym(mr(), "MRMediaRemoteSetElapsedTime");
        if (set) set(atof(pos));
    } else {
        SendCommand send = (SendCommand)dlsym(mr(), "MRMediaRemoteSendCommand");
        const char *c = getenv("DOCKA_COMANDO");
        if (send && c) send(atoi(c), NULL);
    }
    // dá tempo de a mensagem sair antes de o processo terminar
    usleep(150000);
    exit(0);
}
