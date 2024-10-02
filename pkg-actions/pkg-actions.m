#include <CoreFoundation/CFUserNotification.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>
#include <rootless.h>

#include <spawn.h>
#include <sys/stat.h>
#include <version.h>

#ifdef DEBUG
    #define LOG(LogContents, ...) NSLog((@"[AppSync Unified] [pkg-actions] [%s] [L%d] " LogContents), __FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
    #define LOG(...)
#endif

#define DPKG_PATH ROOT_PATH("/var/lib/dpkg/info/ai.akemi.appsyncunified.list")

#define L_LAUNCHDAEMON_PATH "/Library/LaunchDaemons"
#define SL_LAUNCHDAEMON_PATH "/System" L_LAUNCHDAEMON_PATH

#define INSTALLD_PLIST_PATH_L ROOT_PATH(L_LAUNCHDAEMON_PATH "/com.apple.mobile.installd.plist")
#define INSTALLD_PLIST_PATH_SL SL_LAUNCHDAEMON_PATH "/com.apple.mobile.installd.plist"

#define ASU_INJECT_PLIST_PATH ROOT_PATH(L_LAUNCHDAEMON_PATH "/ai.akemi.asu_inject.plist")
#define ASU_INJECT_PLIST_PATH_OLD ROOT_PATH(L_LAUNCHDAEMON_PATH "/net.angelxwind.asu_inject.plist")

// Function prototypes for CFUserNotification
typedef struct __CFUserNotification *CFUserNotificationRef;
FOUNDATION_EXTERN CFUserNotificationRef CFUserNotificationCreate(CFAllocatorRef allocator, CFTimeInterval timeout, CFOptionFlags flags, SInt32 *error, CFDictionaryRef dictionary);
FOUNDATION_EXTERN SInt32 CFUserNotificationReceiveResponse(CFUserNotificationRef userNotification, CFTimeInterval timeout, CFOptionFlags *responseFlags);

// Helper function to spawn a POSIX process
static int run_posix_spawn(const char *args[]) {
    pid_t pid;
    int status;
    posix_spawn(&pid, args[0], NULL, NULL, (char* const*)args, NULL);
    waitpid(pid, &status, 0);
    return status;
}

// Helper function to determine the path of launchctl
static const char *determine_launchctl_path() {
    if (access(ROOT_PATH("/bin/launchctl"), X_OK) == -1) {
        return ROOT_PATH("/sbin/launchctl");
    }
    return ROOT_PATH("/bin/launchctl");
}

// Function to run launchctl commands
static int run_launchctl(const char *path, const char *cmd, bool is_installd) {
    LOG("run_launchctl() %s %s\n", cmd, path);
    const char *args[] = { determine_launchctl_path(), cmd, path, NULL };
    return run_posix_spawn(args);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        #ifdef POSTINST
            LOG("Running postinst…\n");
        #else
            LOG("Running prerm…\n");
        #endif
        printf("AppSync Unified\n");
        printf("Copyright (C) 2014-2023 Karen/あけみ\n");
        printf("** PLEASE DO NOT USE APPSYNC UNIFIED FOR PIRACY **\n");

        if (access(DPKG_PATH, F_OK) == -1) {
            printf("You seem to have installed AppSync Unified from an APT repository that is not cydia.akemi.ai.\n");
            printf("Please make sure that you download AppSync Unified from the official repository to ensure proper operation.\n");
        }

        if (geteuid() != 0) {
            printf("FATAL: This binary must be run as root. (… Actually, how are you even using dpkg without being root?)\n");
            return 1;
        }

        if ((kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) && (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_10_0)) {
            #ifdef POSTINST
                if (access(INSTALLD_PLIST_PATH_L, F_OK) == -1) {
                    printf("This device appears to be running iOS 8 or 9. Creating a symbolic link to the installd LaunchDaemon…\n");
                    symlink(INSTALLD_PLIST_PATH_SL, INSTALLD_PLIST_PATH_L);
                }
            #endif
            printf("Unloading and stopping the symlinked installd LaunchDaemon…\n");
            run_launchctl(INSTALLD_PLIST_PATH_L, "unload", true);
            printf("Reloading and starting the symlinked installd LaunchDaemon…\n");
            run_launchctl(INSTALLD_PLIST_PATH_L, "load", true);
        }

        printf("Unloading and stopping the installd LaunchDaemon…\n");
        run_launchctl(INSTALLD_PLIST_PATH_SL, "unload", true);
        printf("Reloading and starting the installd LaunchDaemon…\n");
        run_launchctl(INSTALLD_PLIST_PATH_SL, "load", true);

        if (access(ASU_INJECT_PLIST_PATH_OLD, F_OK) != -1) {
            printf("Found an old version of the asu_inject LaunchDaemon, unloading and removing it…\n");
            run_launchctl(ASU_INJECT_PLIST_PATH_OLD, "unload", false);
            unlink(ASU_INJECT_PLIST_PATH_OLD);
        }

        #ifdef __LP64__
            printf("Removing the asu_inject LaunchDaemon, as it's not required on this system.\n");
            unlink(ASU_INJECT_PLIST_PATH);
        #else
            if ((kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_9_3) && (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_10_0)) {
                printf("This device is /probably/ running the Phœnix jailbreak (detected iOS 9.3.x and a 32-bit CPU architecture).\n");
                if (access(ROOT_PATH("/usr/bin/cynject"), X_OK) != -1) {
                    printf("Found an executable copy of cynject on this device!\n");
                    chown(ASU_INJECT_PLIST_PATH, 0, 0);
                    chmod(ASU_INJECT_PLIST_PATH, 0644);
                    printf("Unloading and stopping the asu_inject LaunchDaemon…\n");
                    run_launchctl(ASU_INJECT_PLIST_PATH, "unload", false);
                    #ifdef POSTINST
                        printf("Reloading and starting the asu_inject LaunchDaemon…\n");
                        run_launchctl(ASU_INJECT_PLIST_PATH, "load", false);
                    #endif
                } else {
                    printf("Unable to find an executable copy of cynject on this device.\n");
                    printf("Removing the asu_inject LaunchDaemon…\n");
                    unlink(ASU_INJECT_PLIST_PATH);
                }
            }
        #endif

        printf("****** AppSync Unified installation complete! ******\n");

        #ifdef POSTINST
            if (getenv("CYDIA") != NULL && access(ROOT_PATH("/ai.akemi.appsyncunified.no-postinst-notification"), F_OK) == -1) {
                CFUserNotificationRef postinstNotification = CFUserNotificationCreate(kCFAllocatorDefault, 0, 0, NULL, (__bridge CFDictionaryRef)[[NSDictionary alloc] initWithObjectsAndKeys:
                    [NSString stringWithFormat:@"%@ %@", (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_6_0) ? @"⚠️" : @"⚠", @"IMPORTANT NOTE 🍍"], @"AlertHeader",
                    @"If AppSync Unified is not working after installation, please reboot your device or perform a userspace reboot...", @"AlertMessage",
                    @"Okay, I understand! (🍍•̀ω•́)୨✨", @"DefaultButtonTitle", nil]);

                CFRunLoopSourceRef rls = CFUserNotificationCreateRunLoopSource(kCFAllocatorDefault, postinstNotification, NULL, 0);
                CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopCommonModes);
            }
            printf("※ IMPORTANT NOTE: If AppSync Unified is not working after installation, please reboot your device or perform a userspace reboot to activate it. You will only need to do this ONCE.\n");
        #endif
    }
    return 0;
}
#include <CoreFoundation/CFUserNotification.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>
#include <rootless.h>

#include <spawn.h>
#include <sys/stat.h>
#include <version.h>

#ifdef DEBUG
    #define LOG(LogContents, ...) NSLog((@"[AppSync Unified] [pkg-actions] [%s] [L%d] " LogContents), __FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
    #define LOG(...)
#endif

#define DPKG_PATH ROOT_PATH("/var/lib/dpkg/info/ai.akemi.appsyncunified.list")

#define L_LAUNCHDAEMON_PATH "/Library/LaunchDaemons"
#define SL_LAUNCHDAEMON_PATH "/System" L_LAUNCHDAEMON_PATH

#define INSTALLD_PLIST_PATH_L ROOT_PATH(L_LAUNCHDAEMON_PATH "/com.apple.mobile.installd.plist")
#define INSTALLD_PLIST_PATH_SL SL_LAUNCHDAEMON_PATH "/com.apple.mobile.installd.plist"

#define ASU_INJECT_PLIST_PATH ROOT_PATH(L_LAUNCHDAEMON_PATH "/ai.akemi.asu_inject.plist")
#define ASU_INJECT_PLIST_PATH_OLD ROOT_PATH(L_LAUNCHDAEMON_PATH "/net.angelxwind.asu_inject.plist")

// Function prototypes for CFUserNotification
typedef struct __CFUserNotification *CFUserNotificationRef;
FOUNDATION_EXTERN CFUserNotificationRef CFUserNotificationCreate(CFAllocatorRef allocator, CFTimeInterval timeout, CFOptionFlags flags, SInt32 *error, CFDictionaryRef dictionary);
FOUNDATION_EXTERN SInt32 CFUserNotificationReceiveResponse(CFUserNotificationRef userNotification, CFTimeInterval timeout, CFOptionFlags *responseFlags);

// Helper function to spawn a POSIX process
static int run_posix_spawn(const char *args[]) {
    pid_t pid;
    int status;
    posix_spawn(&pid, args[0], NULL, NULL, (char* const*)args, NULL);
    waitpid(pid, &status, 0);
    return status;
}

// Helper function to determine the path of launchctl
static const char *determine_launchctl_path() {
    if (access(ROOT_PATH("/bin/launchctl"), X_OK) == -1) {
        return ROOT_PATH("/sbin/launchctl");
    }
    return ROOT_PATH("/bin/launchctl");
}

// Function to run launchctl commands
static int run_launchctl(const char *path, const char *cmd, bool is_installd) {
    LOG("run_launchctl() %s %s\n", cmd, path);
    const char *args[] = { determine_launchctl_path(), cmd, path, NULL };
    return run_posix_spawn(args);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        #ifdef POSTINST
            LOG("Running postinst…\n");
        #else
            LOG("Running prerm…\n");
        #endif
        printf("AppSync Unified\n");
        printf("Copyright (C) 2014-2023 Karen/あけみ\n");
        printf("** PLEASE DO NOT USE APPSYNC UNIFIED FOR PIRACY **\n");

        if (access(DPKG_PATH, F_OK) == -1) {
            printf("You seem to have installed AppSync Unified from an APT repository that is not cydia.akemi.ai.\n");
            printf("Please make sure that you download AppSync Unified from the official repository to ensure proper operation.\n");
        }

        if (geteuid() != 0) {
            printf("FATAL: This binary must be run as root. (… Actually, how are you even using dpkg without being root?)\n");
            return 1;
        }

        if ((kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) && (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_10_0)) {
            #ifdef POSTINST
                if (access(INSTALLD_PLIST_PATH_L, F_OK) == -1) {
                    printf("This device appears to be running iOS 8 or 9. Creating a symbolic link to the installd LaunchDaemon…\n");
                    symlink(INSTALLD_PLIST_PATH_SL, INSTALLD_PLIST_PATH_L);
                }
            #endif
            printf("Unloading and stopping the symlinked installd LaunchDaemon…\n");
            run_launchctl(INSTALLD_PLIST_PATH_L, "unload", true);
            printf("Reloading and starting the symlinked installd LaunchDaemon…\n");
            run_launchctl(INSTALLD_PLIST_PATH_L, "load", true);
        }

        printf("Unloading and stopping the installd LaunchDaemon…\n");
        run_launchctl(INSTALLD_PLIST_PATH_SL, "unload", true);
        printf("Reloading and starting the installd LaunchDaemon…\n");
        run_launchctl(INSTALLD_PLIST_PATH_SL, "load", true);

        if (access(ASU_INJECT_PLIST_PATH_OLD, F_OK) != -1) {
            printf("Found an old version of the asu_inject LaunchDaemon, unloading and removing it…\n");
            run_launchctl(ASU_INJECT_PLIST_PATH_OLD, "unload", false);
            unlink(ASU_INJECT_PLIST_PATH_OLD);
        }

        #ifdef __LP64__
            printf("Removing the asu_inject LaunchDaemon, as it's not required on this system.\n");
            unlink(ASU_INJECT_PLIST_PATH);
        #else
            if ((kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_9_3) && (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_10_0)) {
                printf("This device is /probably/ running the Phœnix jailbreak (detected iOS 9.3.x and a 32-bit CPU architecture).\n");
                if (access(ROOT_PATH("/usr/bin/cynject"), X_OK) != -1) {
                    printf("Found an executable copy of cynject on this device!\n");
                    chown(ASU_INJECT_PLIST_PATH, 0, 0);
                    chmod(ASU_INJECT_PLIST_PATH, 0644);
                    printf("Unloading and stopping the asu_inject LaunchDaemon…\n");
                    run_launchctl(ASU_INJECT_PLIST_PATH, "unload", false);
                    #ifdef POSTINST
                        printf("Reloading and starting the asu_inject LaunchDaemon…\n");
                        run_launchctl(ASU_INJECT_PLIST_PATH, "load", false);
                    #endif
                } else {
                    printf("Unable to find an executable copy of cynject on this device.\n");
                    printf("Removing the asu_inject LaunchDaemon…\n");
                    unlink(ASU_INJECT_PLIST_PATH);
                }
            }
        #endif

        printf("****** AppSync Unified installation complete! ******\n");

        #ifdef POSTINST
            if (getenv("CYDIA") != NULL && access(ROOT_PATH("/ai.akemi.appsyncunified.no-postinst-notification"), F_OK) == -1) {
                CFUserNotificationRef postinstNotification = CFUserNotificationCreate(kCFAllocatorDefault, 0, 0, NULL, (__bridge CFDictionaryRef)[[NSDictionary alloc] initWithObjectsAndKeys:
                    [NSString stringWithFormat:@"%@ %@", (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_6_0) ? @"⚠️" : @"⚠", @"IMPORTANT NOTE 🍍"], @"AlertHeader",
                    @"If AppSync Unified is not working after installation, please reboot your device or perform a userspace reboot...", @"AlertMessage",
                    @"Okay, I understand! (🍍•̀ω•́)୨✨", @"DefaultButtonTitle", nil]);

                CFRunLoopSourceRef rls = CFUserNotificationCreateRunLoopSource(kCFAllocatorDefault, postinstNotification, NULL, 0);
                CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopCommonModes);
            }
            printf("※ IMPORTANT NOTE: If AppSync Unified is not working after installation, please reboot your device or perform a userspace reboot to activate it. You will only need to do this ONCE.\n");
        #endif
    }
    return 0;
}
