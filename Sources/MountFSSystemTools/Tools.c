#define _POSIX_C_SOURCE 200809L
#include "MountFSSystemTools.h"
#include <spawn.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <poll.h>
#include <sys/wait.h>
#include <time.h>
#include <errno.h>
#include <string.h>
#ifdef __APPLE__
#include <libproc.h>
#include <sys/proc.h>
#endif

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

/* A new process group is established by spawn, before any child code runs.
 * Draining, process exit and timeout are monitored together; descendants holding
 * stdout open cannot block the serialized transaction queue indefinitely. */
int32_t mountfs_run_tool(const char *path, char *const argv[], uint32_t timeout_ms,
                        char *output, size_t capacity, size_t *length) {
    *length = 0;
    if (!timeout_ms) return 124;
    int fd[2];
    if (pipe(fd)) return 1;
    fcntl(fd[0], F_SETFD, FD_CLOEXEC);
    fcntl(fd[1], F_SETFD, FD_CLOEXEC);
    fcntl(fd[0], F_SETFL, O_NONBLOCK);
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attr;
    int error = posix_spawn_file_actions_init(&actions);
    if (error) { close(fd[0]); close(fd[1]); return 1; }
    error = posix_spawnattr_init(&attr);
    if (error) { posix_spawn_file_actions_destroy(&actions); close(fd[0]); close(fd[1]); return 1; }
    error = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    if (!error) error = posix_spawn_file_actions_adddup2(&actions, fd[1], STDOUT_FILENO);
    if (!error) error = posix_spawn_file_actions_adddup2(&actions, fd[1], STDERR_FILENO);
    if (!error) error = posix_spawn_file_actions_addclose(&actions, fd[0]);
    if (!error) error = posix_spawn_file_actions_addclose(&actions, fd[1]);
    if (!error) error = posix_spawnattr_setpgroup(&attr, 0);
    if (!error) error = posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    char *env[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LANG=C", "HOME=/var/root", NULL};
    pid_t pid = 0;
    if (!error) error = posix_spawn(&pid, path, &actions, &attr, argv, env);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&actions);
    close(fd[1]);
    if (error) {
        size_t n = strlen(strerror(error));
        if (n > capacity) n = capacity;
        memcpy(output, strerror(error), n); *length = n;
        close(fd[0]); return 1;
    }
    double deadline = now() + timeout_ms / 1000.0;
    int exited = 0, eof = 0, status = 0, timedout = 0;
    while (!exited || !eof) {
        if (now() >= deadline) { timedout = 1; break; }
        /* Bound each drain pass, including a child emitting output forever. */
        for (int pass = 0; pass < 16 && !eof; pass++) {
            char chunk[4096];
            ssize_t n = read(fd[0], chunk, sizeof(chunk));
            if (n == 0) { eof = 1; break; }
            if (n < 0) { if (errno == EINTR) continue; if (errno != EAGAIN) eof = 1; break; }
            size_t keep = (size_t)n;
            if (keep > capacity - *length) keep = capacity - *length;
            memcpy(output + *length, chunk, keep); *length += keep;
        }
        if (!exited) {
            pid_t result = waitpid(pid, &status, WNOHANG);
            if (result == pid) exited = 1;
            else if (result < 0 && errno != EINTR) { timedout = 1; break; }
        }
        if (!exited || !eof) {
            struct pollfd p = {fd[0], POLLIN | POLLHUP, 0};
            if (eof) { struct timespec pause = {0, 10000000}; nanosleep(&pause, NULL); }
            else poll(&p, 1, 10);
        }
    }
    if (timedout) {
        kill(-pid, SIGTERM);
        /* Always escalate the group, even if its leader exits first. */
        struct timespec grace = {0, 200000000}; nanosleep(&grace, NULL);
        kill(-pid, SIGKILL);
    }
    close(fd[0]);
    if (!exited) {
        double reap_deadline = now() + 1;
        do {
            pid_t result = waitpid(pid, &status, WNOHANG);
            if (result == pid || (result < 0 && errno == ECHILD)) { exited = 1; break; }
            struct timespec pause = {0, 10000000}; nanosleep(&pause, NULL);
        } while (now() < reap_deadline);
        /* A kernel-stuck process must not hold this queue indefinitely. The
         * caller retains the device lock when termination cannot be confirmed. */
        if (!exited) return 125;
    }
    if (timedout) return 124;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}

int mountfs_process_live(int32_t pid) {
#ifdef __APPLE__
    struct proc_bsdinfo info;
    memset(&info, 0, sizeof(info));
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == (int)sizeof(info)
        && info.pbi_status != SZOMB;
#else
    /* This branch is used only by portable runner tests, not the macOS app. */
    return kill(pid, 0) == 0;
#endif
}
