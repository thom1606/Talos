#include <archive.h>
#include <archive_entry.h>
#include <CoreFoundation/CoreFoundation.h>
#include <locale.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool checked(struct archive *archive, int status) {
    if (status == ARCHIVE_OK) return true;
    const char *message = archive_error_string(archive);
    fprintf(stderr, "%s\n", message ? message : "Cannot convert archive entry");
    return false; // Warnings can mean omitted entries; never publish a partial copy.
}

// macOS libarchive reads Unicode paths as NFD. Normalize paths AND link targets
// consistently so links remain valid when the output is opened on other platforms.
static bool normalize(struct archive_entry *entry, const char *value,
                      void (*copy)(struct archive_entry *, const char *)) {
    if (!value) return true;
    CFMutableStringRef string = CFStringCreateMutable(kCFAllocatorDefault, 0);
    CFStringRef original = CFStringCreateWithCString(kCFAllocatorDefault, value, kCFStringEncodingUTF8);
    if (!string || !original) {
        if (string) CFRelease(string);
        if (original) CFRelease(original);
        return false;
    }
    CFStringAppend(string, original);
    CFRelease(original);
    CFStringNormalize(string, kCFStringNormalizationFormC);
    CFIndex capacity = CFStringGetMaximumSizeForEncoding(CFStringGetLength(string), kCFStringEncodingUTF8) + 1;
    char *bytes = malloc((size_t)capacity);
    bool ok = bytes && CFStringGetCString(string, bytes, capacity, kCFStringEncodingUTF8);
    if (ok) copy(entry, bytes);
    free(bytes);
    CFRelease(string);
    return ok;
}

int main(int argc, char **argv) {
    if (argc != 4 || (strcmp(argv[3], "zip") && strcmp(argv[3], "tar") && strcmp(argv[3], "gzip"))) {
        fputs("Invalid archive conversion request\n", stderr);
        return 1;
    }
    // A separate SDK process owns this locale, lifetime and cancellation.
    if (!setlocale(LC_CTYPE, "en_US.UTF-8")) return 1;
    struct archive *reader = archive_read_new(), *writer = archive_write_new();
    bool ok = reader && writer;
    if (ok) ok = checked(reader, archive_read_support_format_zip(reader)) &&
                 checked(reader, archive_read_support_format_tar(reader)) &&
                 checked(reader, archive_read_support_filter_none(reader)) &&
                 checked(reader, archive_read_support_filter_gzip(reader)) &&
                 // Preserve AppleDouble entries instead of consuming them as macOS metadata.
                 checked(reader, archive_read_set_options(reader, "!mac-ext")) &&
                 checked(reader, archive_read_open_filename(reader, argv[1], 65536));
    if (ok) ok = checked(writer, !strcmp(argv[3], "zip") ? archive_write_set_format_zip(writer)
                                                      : archive_write_set_format_pax(writer));
    if (ok && !strcmp(argv[3], "gzip")) ok = checked(writer, archive_write_add_filter_gzip(writer));
    if (ok) ok = checked(writer, archive_write_open_filename(writer, argv[2]));
    struct archive_entry *entry;
    char buffer[65536]; // Stream payloads; no extraction or archive-sized allocation.
    while (ok) {
        int status = archive_read_next_header(reader, &entry);
        if (status == ARCHIVE_EOF) break;
        if (!checked(reader, status)) { ok = false; break; }
        if (!normalize(entry, archive_entry_pathname(entry), archive_entry_copy_pathname) ||
            !normalize(entry, archive_entry_symlink(entry), archive_entry_copy_symlink) ||
            !normalize(entry, archive_entry_hardlink(entry), archive_entry_copy_hardlink)) {
            fputs("Cannot preserve archive path encoding\n", stderr);
            ok = false; break;
        }
        if (!checked(writer, archive_write_header(writer, entry))) { ok = false; break; }
        la_ssize_t count;
        while ((count = archive_read_data(reader, buffer, sizeof(buffer))) > 0) {
            la_ssize_t offset = 0;
            while (offset < count) {
                la_ssize_t written = archive_write_data(writer, buffer + offset, (size_t)(count - offset));
                if (written <= 0) { checked(writer, ARCHIVE_FATAL); ok = false; break; }
                offset += written;
            }
            if (!ok) break;
        }
        if (count < 0) { checked(reader, ARCHIVE_FATAL); ok = false; }
        if (ok) ok = checked(writer, archive_write_finish_entry(writer));
    }
    if (reader) {
        if (!checked(reader, archive_read_close(reader))) ok = false;
        if (archive_read_free(reader) != ARCHIVE_OK) ok = false;
    }
    if (writer) {
        if (!checked(writer, archive_write_close(writer))) ok = false;
        if (archive_write_free(writer) != ARCHIVE_OK) ok = false;
    }
    return ok ? 0 : 1;
}
