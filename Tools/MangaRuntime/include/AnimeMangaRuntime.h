#ifndef ANIME_MANGA_RUNTIME_H
#define ANIME_MANGA_RUNTIME_H
#include <stddef.h>
#include <stdint.h>

// Calls are synchronous. Run off the main thread. Each call owns a fresh VM.
// The host owns callback responses and releases them using its own allocator.
typedef char *(*ACMangaHTTP)(void *context, const char *request_json);
typedef void (*ACMangaReleaseHTTP)(char *response_json);
char *ac_manga_execute(const uint8_t *apk, size_t apk_length, const char *command_json,
                      ACMangaHTTP http, ACMangaReleaseHTTP release_http, void *context);
void ac_manga_free_string(char *string);
#endif
