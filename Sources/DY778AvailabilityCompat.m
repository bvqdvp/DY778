/* Older Linux iOS toolchains may omit compiler-rt's OS availability helper.
 * Opt in only for that build. Modern Apple/Theos builds use their own runtime.
 * NSProcessInfo's version comparison is available since iOS 8 (target is 14+).
 */
#if defined(DY778_LEGACY_TOOLCHAIN_VERSION_CHECK)
#import <Foundation/Foundation.h>
int __isOSVersionAtLeast(int major, int minor, int patch) {
    return [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){major, minor, patch}] ? 1 : 0;
}
#endif
