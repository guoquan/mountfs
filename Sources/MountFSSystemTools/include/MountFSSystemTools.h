#ifndef MOUNTFS_SYSTEM_TOOLS_H
#define MOUNTFS_SYSTEM_TOOLS_H
#include <stddef.h>
#include <stdint.h>
int32_t mountfs_run_tool(const char *path, char *const argv[], uint32_t timeout_ms,
                        char *output, size_t capacity, size_t *length);
int mountfs_process_live(int32_t pid);
#endif
