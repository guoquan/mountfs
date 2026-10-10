#define _POSIX_C_SOURCE 200809L
#include "MountFSSystemTools.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>
#include <stdlib.h>

static double seconds(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}
int main(void) {
    char output[65536]; size_t length;
    char *success[] = {"/bin/sh", "-c", "printf stdout; printf stderr >&2; exit 7", NULL};
    assert(mountfs_run_tool(success[0], success, 2000, output, sizeof(output), &length) == 7);
    assert(length == 12 && memcmp(output, "stdoutstderr", 12) == 0);
    char *custom_env[] = {"MOUNTFS_RUNNER_TEST=preserved", "PATH=/usr/bin:/bin", NULL};
    char *metadata[] = {"/bin/sh", "-c", "printf '%s' \"$MOUNTFS_RUNNER_TEST\"; printf noisy-diagnostic >&2", NULL};
    assert(mountfs_run_tool_environment(metadata[0], metadata, custom_env, 0, 2000, output, sizeof(output), &length) == 0);
    assert(length == 9 && memcmp(output, "preserved", 9) == 0);
    puts("PASS custom app environment is preserved and stderr cannot corrupt structured stdout");
    char *spam[] = {"/bin/sh", "-c", "yes x | head -c 200000", NULL};
    assert(mountfs_run_tool(spam[0], spam, 3000, output, sizeof(output), &length) == 0);
    assert(length == sizeof(output));
    char *hung[] = {"/bin/sh", "-c", "echo $$; trap '' TERM; sleep 30 & wait", NULL};
    double start = seconds();
    int result = mountfs_run_tool(hung[0], hung, 150, output, sizeof(output), &length);
    assert(result == 124 || result == 125);
    output[length] = 0;
    pid_t group = (pid_t)strtol(output, NULL, 10); assert(group > 1);
    if (result == 124) { assert(kill(-group, 0) < 0 && errno == ESRCH); }
    assert(seconds() - start < 3);
    /* Leader exits successfully, but its child holds the output pipe open. */
    char *pipeheld[] = {"/bin/sh", "-c", "echo $$; sleep 30 & exit 0", NULL};
    start = seconds();
    result = mountfs_run_tool(pipeheld[0], pipeheld, 150, output, sizeof(output), &length);
    assert(result == 124 || result == 125);
    output[length] = 0;
    group = (pid_t)strtol(output, NULL, 10); assert(group > 1);
    if (result == 124) { assert(kill(-group, 0) < 0 && errno == ESRCH); }
    assert(seconds() - start < 3);
    char *missing[] = {"/nonexistent/mountfs-tool", NULL};
    assert(mountfs_run_tool(missing[0], missing, 150, output, sizeof(output), &length) != 0);
#ifdef __APPLE__
    pid_t zombie = fork();
    assert(zombie >= 0);
    if (zombie == 0) _exit(0);
    struct timespec pause = {0, 100000000}; nanosleep(&pause, NULL);
    assert(!mountfs_process_live(zombie));
    int status; assert(waitpid(zombie, &status, 0) == zombie);
    puts("PASS macOS liveness rejects an exited, unreaped authorization host");
#endif
    puts("PASS tool exit status, capped output, hung process group and inherited-pipe deadlines");
}
