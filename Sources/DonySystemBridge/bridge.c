#include <errno.h>
#include "DonySystemBridge.h"
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <libproc.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>

int dc_process_open_files(int32_t pid, char *output, int capacity) {
    struct proc_bsdinfo before, after;
    if (!output || capacity < 1 || proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &before, sizeof(before)) != sizeof(before) || before.pbi_uid != getuid()) return -1;
    int required = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (required <= 0 || required > 65536 * (int)sizeof(struct proc_fdinfo)) return -1;
    int allocated = required + 64 * (int)sizeof(struct proc_fdinfo);
    struct proc_fdinfo *fds = malloc((size_t)allocated);
    if (!fds) return -1;
    int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, allocated);
    if (bytes <= 0 || bytes >= allocated || bytes % (int)sizeof(struct proc_fdinfo)) { free(fds); return -1; }
    int used = 0;
    for (int i = 0; i < bytes / (int)sizeof(struct proc_fdinfo); i++) {
        if (fds[i].proc_fdtype != PROX_FDTYPE_VNODE) continue;
        struct vnode_fdinfowithpath info;
        if (proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDVNODEPATHINFO, &info, sizeof(info)) != sizeof(info)) { free(fds); return -1; }
        size_t length = strnlen(info.pvip.vip_path, sizeof(info.pvip.vip_path));
        if (length == sizeof(info.pvip.vip_path)) { free(fds); return -1; }
        if (length && info.pvip.vip_path[0] == '/') {
            if ((size_t)(capacity - used) < length + 2) { free(fds); return -1; }
            output[used++] = 'p'; memcpy(output + used, info.pvip.vip_path, length + 1); used += (int)length + 1;
        }
        char identity[64];
        int n = snprintf(identity, sizeof(identity), "i%llu:%llu", (unsigned long long)info.pvip.vip_vi.vi_stat.vst_dev, (unsigned long long)info.pvip.vip_vi.vi_stat.vst_ino);
        if (n < 1 || n >= (int)sizeof(identity) || capacity - used < n + 1) { free(fds); return -1; }
        memcpy(output + used, identity, (size_t)n + 1); used += n + 1;
    }
    free(fds);
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &after, sizeof(after)) != sizeof(after) ||
        before.pbi_uid != after.pbi_uid || before.pbi_start_tvsec != after.pbi_start_tvsec || before.pbi_start_tvusec != after.pbi_start_tvusec) return -1;
    return used;
}

int dc_process_cwd(int32_t pid, char *output, int capacity) {
    struct proc_vnodepathinfo info;
    memset(&info, 0, sizeof(info));
    if (capacity <= 0 || proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, sizeof(info)) != sizeof(info)) return 0;
    strlcpy(output, info.pvi_cdir.vip_path, (size_t)capacity);
    return output[0] != '\0';
}

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
        row->pid = pids[i]; row->parent_pid = bsd.pbi_ppid; row->uid = bsd.pbi_uid; row->start_seconds = bsd.pbi_start_tvsec; row->start_microseconds = bsd.pbi_start_tvusec;
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

int dc_owned_process_capacity(void) {
    int bytes = proc_listpids(PROC_UID_ONLY, getuid(), NULL, 0);
    if (bytes <= 0 || bytes > 65536 * (int)sizeof(int)) return 0;
    int count = bytes / (int)sizeof(int) + 128;
    return count > 16384 ? 16384 : count;
}

int dc_read_owned_processes(DCProcess *output, int capacity, int *complete) {
    *complete = 0;
    if (!output || capacity < 1) return 0;
    int needed = proc_listpids(PROC_UID_ONLY, getuid(), NULL, 0);
    if (needed <= 0 || needed > 65536 * (int)sizeof(int)) return 0;
    int allocated = needed + 128 * (int)sizeof(int);
    int *pids = calloc(1, (size_t)allocated);
    if (!pids) return 0;
    int bytes = proc_listpids(PROC_UID_ONLY, getuid(), pids, allocated);
    if (bytes <= 0 || bytes >= allocated || bytes % (int)sizeof(int)) { free(pids); return 0; }
    int filled = 0, valid = 1;
    for (int i = 0; i < bytes / (int)sizeof(int); i++) {
        if (pids[i] <= 0) continue;
        struct proc_bsdinfo bsd;
        if (filled >= capacity) { valid = 0; continue; }
        errno = 0;
        int info = proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd));
        // 목록을 읽는 사이 정상 종료된 프로세스는 파일을 잡을 수 없으므로 건너뛴다. 권한 오류나 이상한 응답만 불완전으로 본다.
        if (info <= 0) { if (errno == EPERM || errno == EACCES) valid = 0; continue; }
        if (info != (int)sizeof(bsd)) { valid = 0; continue; }
        if (bsd.pbi_uid != getuid()) continue; // 목록을 읽은 뒤 PID가 다른 사용자 프로세스로 재사용됨
        DCProcess *row = &output[filled++]; memset(row, 0, sizeof(*row));
        row->pid = pids[i]; row->parent_pid = bsd.pbi_ppid; row->uid = bsd.pbi_uid;
        row->start_seconds = bsd.pbi_start_tvsec; row->start_microseconds = bsd.pbi_start_tvusec;
        proc_pidpath(pids[i], row->path, sizeof(row->path));
        strlcpy(row->name, bsd.pbi_comm, sizeof(row->name));
    }
    free(pids); *complete = valid && filled > 0; return filled;
}

int dc_process_matches(int32_t pid, uint32_t uid, uint64_t seconds, uint64_t micros) {
    struct proc_bsdinfo bsd;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) return 0;
    return bsd.pbi_uid == uid && bsd.pbi_start_tvsec == seconds && bsd.pbi_start_tvusec == micros;
}

#include <sys/socket.h>
#include <net/if.h>
#include <net/route.h>
int dc_read_network(DCNetwork *output) {
    memset(output, 0, sizeof(*output));
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t length = 0;
    if (sysctl(mib, 6, NULL, &length, NULL, 0) != 0 || length == 0 || length > 4 * 1024 * 1024) return 0;
    char *buffer = malloc(length); if (!buffer) return 0;
    if (sysctl(mib, 6, buffer, &length, NULL, 0) != 0) { free(buffer); return 0; }
    uint64_t hash = 0;
    for (char *cursor = buffer; cursor + sizeof(struct rt_msghdr) <= buffer + length;) {
        const struct rt_msghdr *header = (const struct rt_msghdr *)cursor;
        if (!header->rtm_msglen || cursor + header->rtm_msglen > buffer + length) break;
        if (header->rtm_type == RTM_IFINFO2 && header->rtm_msglen >= sizeof(struct if_msghdr2)) {
            const struct if_msghdr2 *row = (const struct if_msghdr2 *)cursor;
            char name[IF_NAMESIZE];
            if (if_indextoname(row->ifm_index, name) && strncmp(name, "en", 2) == 0 &&
                (row->ifm_flags & IFF_UP) && !(row->ifm_flags & IFF_LOOPBACK)) {
                // NET_RT_IFLIST2 supplies 64-bit byte counters; getifaddrs' legacy
                // if_data fields wrap at 4 GB on macOS.
                output->received += row->ifm_data.ifi_ibytes; output->sent += row->ifm_data.ifi_obytes;
                uint64_t entry = 1469598103934665603ULL;
                for (const char *letter = name; *letter; letter++) { entry ^= (unsigned char)*letter; entry *= 1099511628211ULL; }
                hash ^= entry; output->available = 1;
            }
        }
        cursor += header->rtm_msglen;
    }
    free(buffer); output->generation = hash; return output->available;
}

int dc_process_arguments(int32_t pid, char *output, int capacity) {
    struct proc_bsdinfo info;
    if (capacity < 1 || proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info) || info.pbi_uid != getuid()) return 0;
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
    const size_t allocation = 65536; size_t size = allocation;
    char *buffer = calloc(allocation, 1); if (!buffer) return 0;
    int written = 0;
    if (sysctl(mib, 3, buffer, &size, NULL, 0) == 0 && size <= allocation && size > sizeof(int)) {
        int argc = 0; memcpy(&argc, buffer, sizeof(int));
        size_t offset = sizeof(int);
        while (offset < size && buffer[offset]) offset++;
        while (offset < size && !buffer[offset]) offset++;
        for (int i = 0; i < argc && i < 2 && offset < size; i++) {
            size_t length = strnlen(buffer + offset, size - offset);
            if (length >= size - offset || written + (int)length + 1 > capacity) break;
            memcpy(output + written, buffer + offset, length + 1);
            written += (int)length + 1; offset += length + 1;
        }
    }
    memset(buffer, 0, allocation); free(buffer);
    return written;
}
