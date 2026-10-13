#ifndef DONY_SYSTEM_BRIDGE_H
#define DONY_SYSTEM_BRIDGE_H
#include <stdint.h>
typedef struct {
    uint64_t cpu_user, cpu_system, cpu_idle, cpu_nice;
    uint64_t memory_total, memory_used, memory_cached, memory_compressed, swap_used;
    int cpu_available, memory_available, swap_available, pressure;
} DCSystem;
typedef struct {
    int32_t pid;
    int32_t parent_pid;
    uint32_t uid;
    uint64_t start_seconds, start_microseconds, cpu_ticks, memory_bytes;
    int counters_available;
    char name[256];
    char path[4096];
} DCProcess;
typedef struct { uint64_t received, sent, generation; int available; } DCNetwork;
int dc_read_network(DCNetwork *output);
int dc_read_system(DCSystem *output);
int dc_read_processes(DCProcess *output, int capacity);
int dc_process_matches(int32_t pid, uint32_t uid, uint64_t start_seconds, uint64_t start_microseconds);
int dc_process_cwd(int32_t pid, char *output, int capacity);
int dc_process_arguments(int32_t pid, char *output, int capacity);
#endif
