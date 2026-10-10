#include <sandbox.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>

/* Open before entering the sandbox to isolate file-map-executable from open/read. */
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    int fd = open(argv[1], O_RDONLY);
    struct stat info;
    if (fd < 0 || fstat(fd, &info) != 0 || info.st_size <= 0) return 2;
    char *error = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (strcmp(argv[2], "-") != 0 && sandbox_init(argv[2], 0, &error) != 0) {
        if (error) { fprintf(stderr, "%s\n", error); sandbox_free_error(error); }
        return 2;
    }
#pragma clang diagnostic pop
    void *mapped = mmap(NULL, (size_t)info.st_size, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
    close(fd);
    if (mapped == MAP_FAILED) return 1;
    munmap(mapped, (size_t)info.st_size);
    return 0;
}
