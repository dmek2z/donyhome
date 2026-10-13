#include "DonySystemBridge.h"
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <libproc.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <stdlib.h>
#include <string.h>

int dc_read_system(DCSystem *out) {
    memset(out, 0, sizeof(*out));
    host_t host = mach_host_self();
    host_cpu_load_info_data_t cpu;
    mach_msg_type_number_t cpu_count = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&cpu, &cpu_count) == KERN_SUCCESS) {
        out->cpu_user = cpu.cpu_ticks[CPU_STATE_USER]; out->cpu_system = cpu.cpu_ticks[CPU_STATE_SYSTEM];
        out->cpu_idle = cpu.cpu_ticks[CPU_STATE_IDLE]; out->cpu_nice = cpu.cpu_ticks[CPU_STATE_NICE]; out->cpu_available = 1;
    }
    vm_statistics64_data_t vm;
    mach_msg_type_number_t vm_count = HOST_VM_INFO64_COUNT;
    vm_size_t page = 0; size_t size = sizeof(out->memory_total);
    if (sysctlbyname("hw.memsize", &out->memory_total, &size, NULL, 0) == 0 && host_page_size(host, &page) == KERN_SUCCESS &&
        host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &vm_count) == KERN_SUCCESS) {
        out->memory_used = ((uint64_t)vm.internal_page_count + vm.wire_count + vm.compressor_page_count) * page;
        if (out->memory_used > out->memory_total) out->memory_used = out->memory_total;
        out->memory_cached = ((uint64_t)vm.external_page_count + vm.purgeable_count) * page;
        out->memory_compressed = (uint64_t)vm.compressor_page_count * page; out->memory_available = 1;
    }
    mach_port_deallocate(mach_task_self(), host);
    struct xsw_usage swap; size = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0) { out->swap_used = swap.xsu_used; out->swap_available = 1; }
    int pressure = 0; size = sizeof(pressure);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, NULL, 0) == 0) out->pressure = pressure;
    return out->cpu_available || out->memory_available;
}

int dc_read_processes(DCProcess *output, int capacity) {
    int count = proc_listallpids(NULL, 0); if (count <= 0) return 0;
    int length = count + 128; int *pids = calloc((size_t)length, sizeof(int)); if (!pids) return 0;
    count = proc_listallpids(pids, length * (int)sizeof(int)); if (count > length) count = length;
    int filled = 0;
    for (int i = 0; i < count && filled < capacity; i++) {
        struct proc_bsdinfo bsd;
        if (pids[i] <= 0 || proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) continue;
        DCProcess *row = &output[filled++]; memset(row, 0, sizeof(*row));
        row->pid = pids[i]; row->uid = bsd.pbi_uid; row->start_seconds = bsd.pbi_start_tvsec; row->start_microseconds = bsd.pbi_start_tvusec;
        proc_pidpath(pids[i], row->path, sizeof(row->path)); proc_name(pids[i], row->name, sizeof(row->name));
        if (!row->name[0]) strlcpy(row->name, bsd.pbi_comm, sizeof(row->name));
        struct rusage_info_v2 usage;
        if (proc_pid_rusage(pids[i], RUSAGE_INFO_V2, (rusage_info_t *)&usage) == 0) {
            // proc_pid_rusage CPU counters use Mach absolute-time units.
            // Convert using mach_timebase_info in SystemSampler before CPU deltas.
            row->cpu_ticks = usage.ri_user_time + usage.ri_system_time; row->memory_bytes = usage.ri_phys_footprint; row->counters_available = 1;
        }
    }
    free(pids); return filled;
}

int dc_process_matches(int32_t pid, uint32_t uid, uint64_t seconds, uint64_t micros) {
    struct proc_bsdinfo bsd;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) return 0;
    return bsd.pbi_uid == uid && bsd.pbi_start_tvsec == seconds && bsd.pbi_start_tvusec == micros;
}
