#ifdef __APPLE__
#define _DARWIN_C_SOURCE
#else
#define _POSIX_C_SOURCE 200809L
#endif
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
#include <sys/socket.h>
#include <arpa/inet.h>
#include <sys/un.h>
#include <sys/stat.h>
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
    if (timedout) {
        /* Reaping the leader does not establish that its descendants stopped.
         * Include zombies/kernel-stuck members conservatively; ESRCH is the
         * only proof of group disappearance. Never wait indefinitely here. */
        double group_deadline = now() + 1;
        do {
            if (kill(-pid, 0) < 0 && errno == ESRCH) return 124;
            struct timespec pause = {0, 10000000}; nanosleep(&pause, NULL);
        } while (now() < group_deadline);
        return 125;
    }
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

/* Apple's bsd/sys/codesign.h: CS_OPS_CDHASH=5. Ask the kernel for the
 * running image, never re-read an app bundle that its owner can replace. */
int mountfs_self_cdhash(unsigned char hash[20]) {
#ifdef __APPLE__
    extern int csops(pid_t, unsigned int, void *, size_t);
    return csops(getpid(), 5, hash, 20) == 0;
#else
    (void)hash; return 0;
#endif
}

uint64_t mountfs_process_birth(int32_t pid) {
#ifdef __APPLE__
    struct proc_bsdinfo info;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != (int)sizeof(info) || info.pbi_status == SZOMB) return 0;
    return info.pbi_start_tvsec * 1000000 + info.pbi_start_tvusec;
#else
    (void)pid; return 0;
#endif
}

/* The PID comes from the kernel socket credential, never the request packet.
 * Only children/descendants of the original, still-live shell may send requests.
 * Birth time pins that shell across PID reuse. No same-UID sibling is accepted. */
int mountfs_auth_peer(int fd, int32_t expected_pid, int32_t ancestor, uint64_t birth) {
#ifdef __APPLE__
    pid_t peer = 0; socklen_t size = sizeof(peer);
    uid_t uid; gid_t gid;
    if (getpeereid(fd, &uid, &gid) || uid != geteuid() ||
        getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peer, &size) || size != sizeof(peer) || peer <= 1) return 0;
    if (expected_pid > 0) return peer == expected_pid;
    if (!birth || mountfs_process_birth(ancestor) != birth) return 0;
    uint64_t peer_birth = mountfs_process_birth(peer);
    if (!peer_birth) return 0;
    pid_t current = peer;
    for (int depth = 0; depth < 16; depth++) {
        struct proc_bsdinfo info;
        if (proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != (int)sizeof(info) ||
            info.pbi_status == SZOMB || info.pbi_uid != geteuid()) return 0;
        current = (pid_t)info.pbi_ppid;
        if (current == ancestor) return mountfs_process_birth(ancestor) == birth && mountfs_process_birth(peer) == peer_birth;
        if (current <= 1 || current == peer) return 0;
    }
    return 0;
#else
    (void)fd; (void)expected_pid; (void)ancestor; (void)birth; return 0;
#endif
}

#ifdef __APPLE__
static int auth_socket(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int one = 1;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) || fcntl(fd, F_SETFL, O_NONBLOCK) ||
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one))) { close(fd); return -1; }
    return fd;
}
static int auth_address(const char *path, struct sockaddr_un *address) {
    memset(address, 0, sizeof(*address));
    if (strlen(path) >= sizeof(address->sun_path)) return 0;
    address->sun_family = AF_UNIX; address->sun_len = sizeof(*address);
    strcpy(address->sun_path, path); return 1;
}
static int auth_transfer(int fd, char *buffer, size_t length, int writing, double deadline) {
    size_t offset = 0;
    while (offset < length) {
        double remaining = deadline - now();
        if (remaining <= 0) return 0;
        struct pollfd pfd = {fd, writing ? POLLOUT : POLLIN, 0};
        int ready = poll(&pfd, 1, (int)(remaining * 1000) + 1);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0) return 0;
        ssize_t count = writing ? send(fd, buffer + offset, length - offset, 0) : recv(fd, buffer + offset, length - offset, 0);
        if (count < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (count <= 0) return 0;
        offset += (size_t)count;
    }
    return 1;
}
#endif
int mountfs_auth_listen(const char *path) {
#ifdef __APPLE__
    struct sockaddr_un address;
    if (!auth_address(path, &address)) return -1;
    int fd = auth_socket();
    if (fd < 0) return -1;
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) || chmod(path, 0600) || listen(fd, 8)) { close(fd); return -1; }
    return fd;
#else
    (void)path; return -1;
#endif
}
int mountfs_auth_connect(const char *path) {
#ifdef __APPLE__
    struct sockaddr_un address;
    if (!auth_address(path, &address)) return -1;
    int fd = auth_socket();
    if (fd < 0) return -1;
    if (connect(fd, (struct sockaddr *)&address, sizeof(address))) { close(fd); return -1; }
    return fd;
#else
    (void)path; return -1;
#endif
}
int mountfs_auth_accept(int listener) {
#ifdef __APPLE__
    int fd = accept(listener, NULL, NULL);
    if (fd < 0) return -1;
    int one = 1;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) || fcntl(fd, F_SETFL, O_NONBLOCK) ||
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one))) { close(fd); return -1; }
    return fd;
#else
    (void)listener; return -1;
#endif
}
int mountfs_auth_read(int fd, char *buffer, size_t capacity, size_t *length, uint32_t timeout_ms) {
#ifdef __APPLE__
    double deadline = now() + timeout_ms / 1000.0;
    uint32_t header;
    if (!auth_transfer(fd, (char *)&header, sizeof(header), 0, deadline)) return 0;
    size_t count = ntohl(header);
    if (!count || count > capacity || !auth_transfer(fd, buffer, count, 0, deadline)) return 0;
    *length = count; return 1;
#else
    (void)fd; (void)buffer; (void)capacity; (void)length; (void)timeout_ms; return 0;
#endif
}
int mountfs_auth_write(int fd, const char *buffer, size_t length, uint32_t timeout_ms) {
#ifdef __APPLE__
    if (!length || length > 262144) return 0;
    double deadline = now() + timeout_ms / 1000.0;
    uint32_t header = htonl((uint32_t)length);
    return auth_transfer(fd, (char *)&header, sizeof(header), 1, deadline) &&
        auth_transfer(fd, (char *)buffer, length, 1, deadline);
#else
    (void)fd; (void)buffer; (void)length; (void)timeout_ms; return 0;
#endif
}
