#ifndef MOUNTFS_SYSTEM_TOOLS_H
#define MOUNTFS_SYSTEM_TOOLS_H
#include <stddef.h>
#include <stdint.h>
int32_t mountfs_run_tool(const char *path, char *const argv[], uint32_t timeout_ms,
                        char *output, size_t capacity, size_t *length);
int32_t mountfs_run_tool_environment(const char *path, char *const argv[], char *const envp[], int merge_errors, uint32_t timeout_ms, char *output, size_t capacity, size_t *length);
int mountfs_process_live(int32_t pid);
int mountfs_self_cdhash(unsigned char hash[20]);
uint64_t mountfs_process_birth(int32_t pid);
int mountfs_auth_peer(int fd, int32_t expected_pid, int32_t ancestor, uint64_t birth);
int mountfs_auth_listen(const char *path);
int mountfs_auth_connect(const char *path);
int mountfs_auth_accept(int listener);
int mountfs_auth_read(int fd, char *buffer, size_t capacity, size_t *length, uint32_t timeout_ms);
int mountfs_auth_write(int fd, const char *buffer, size_t length, uint32_t timeout_ms);
#endif
