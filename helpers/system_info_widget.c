// Native System Info widget and popup refresher.
//
// No arguments updates the compact bar item. `popup_refresh` updates only the
// enabled detail rows. Both paths send one bounded SketchyBar Mach request;
// the shell wrapper remains the portable fallback when native transport fails.

#include <arpa/inet.h>
#include <bootstrap.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/message.h>
#include <net/if.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/mount.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

#define MAX_ARGUMENTS 64
#define MAX_TOKEN_BYTES 1024
#define MAX_PAYLOAD_BYTES (16 * 1024)
#define DEFAULT_PROBE_TIMEOUT_MS 500
#define LABEL_BYTES 512
#define SMALL_VALUE_BYTES 128

static const mach_msg_timeout_t kMachSendTimeoutMilliseconds = 50;
static const mach_msg_timeout_t kMachReceiveTimeoutMilliseconds = 150;

#ifdef BARISTA_SYSTEM_INFO_TESTING
static void (*capture_test_hook)(const char *stage, const char *path) = NULL;
#endif

typedef enum {
    ROW_CPU = 1u << 0,
    ROW_MEM = 1u << 1,
    ROW_DISK = 1u << 2,
    ROW_NET = 1u << 3,
    ROW_SWAP = 1u << 4,
    ROW_UPTIME = 1u << 5,
    ROW_PROCS = 1u << 6,
} RowMask;

#define DEFAULT_POPUP_ROWS (ROW_MEM | ROW_DISK | ROW_NET | ROW_SWAP | ROW_UPTIME | ROW_PROCS)
#define ALL_POPUP_ROWS (ROW_CPU | DEFAULT_POPUP_ROWS)

typedef struct {
    uint32_t mask;
} PopupRows;

typedef struct {
    bool cpu_available;
    int cpu_percent;
    double load_avg;

    bool memory_available;
    uint64_t memory_used_bytes;
    uint64_t memory_total_bytes;

    bool disk_available;
    int disk_percent;
    char disk_used[SMALL_VALUE_BYTES];
    char disk_total[SMALL_VALUE_BYTES];

    bool network_online;
    char network_ip[INET6_ADDRSTRLEN];
    char network_name[SMALL_VALUE_BYTES];

    bool swap_available;
    uint64_t swap_used_bytes;
    uint64_t swap_total_bytes;

    bool uptime_available;
    uint64_t uptime_seconds;

    bool process_available;
    double process_cpu;
    char process_name[256];
} SystemInfo;

typedef struct {
    uint8_t bytes[MAX_PAYLOAD_BYTES];
    size_t length;
    size_t arguments;
    bool failed;
} Payload;

struct barista_mach_message {
    mach_msg_header_t header;
    mach_msg_size_t descriptor_count;
    mach_msg_ool_descriptor_t descriptor;
};

struct barista_mach_buffer {
    struct barista_mach_message message;
    mach_msg_trailer_t trailer;
};

static uint64_t monotonic_milliseconds(void) {
    struct timespec value = {0};
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) {
        return 0;
    }
    return (uint64_t)value.tv_sec * 1000ULL + (uint64_t)value.tv_nsec / 1000000ULL;
}

static int clamp_percent(int value) {
    if (value < 0) return 0;
    if (value > 100) return 100;
    return value;
}

static bool parse_bool(const char *value, bool *result) {
    if (!value || value[0] == '\0') return false;
    if (strcmp(value, "1") == 0 || strcasecmp(value, "true") == 0
        || strcasecmp(value, "yes") == 0 || strcasecmp(value, "on") == 0) {
        if (result) *result = true;
        return true;
    }
    if (strcmp(value, "0") == 0 || strcasecmp(value, "false") == 0
        || strcasecmp(value, "no") == 0 || strcasecmp(value, "off") == 0) {
        if (result) *result = false;
        return true;
    }
    return false;
}

static bool native_disabled(void) {
    bool disabled = false;
    return parse_bool(getenv("BARISTA_SYSTEM_INFO_NATIVE_DISABLE"), &disabled) && disabled;
}

static uint32_t row_for_name(const char *name) {
    if (strcmp(name, "cpu") == 0) return ROW_CPU;
    if (strcmp(name, "mem") == 0) return ROW_MEM;
    if (strcmp(name, "disk") == 0) return ROW_DISK;
    if (strcmp(name, "net") == 0) return ROW_NET;
    if (strcmp(name, "swap") == 0) return ROW_SWAP;
    if (strcmp(name, "uptime") == 0) return ROW_UPTIME;
    if (strcmp(name, "procs") == 0) return ROW_PROCS;
    return 0;
}

static bool parse_popup_rows(const char *value, PopupRows *rows) {
    if (!rows) return false;
    rows->mask = DEFAULT_POPUP_ROWS;
    if (!value || value[0] == '\0') return true;
    if (strcmp(value, "none") == 0) {
        rows->mask = 0;
        return true;
    }

    size_t length = strlen(value);
    if (length == 0 || length >= 256 || value[0] == ',' || value[length - 1] == ','
        || strstr(value, ",,") != NULL) {
        return false;
    }

    char copy[256];
    memcpy(copy, value, length + 1);
    uint32_t mask = 0;
    char *save = NULL;
    char *token = strtok_r(copy, ",", &save);
    while (token) {
        uint32_t row = row_for_name(token);
        if (row == 0 || (mask & row) != 0) return false;
        mask |= row;
        token = strtok_r(NULL, ",", &save);
    }
    rows->mask = mask;
    return true;
}

static bool row_enabled(const PopupRows *rows, RowMask row) {
    return rows && (rows->mask & (uint32_t)row) != 0;
}

static bool capture_process_internal(const char *path,
                                     char *const argv[],
                                     char *output,
                                     size_t output_size,
                                     int timeout_ms,
                                     bool first_line_only) {
    if (!path || !argv || !output || output_size < 2 || timeout_ms <= 0) return false;
    output[0] = '\0';

    int pipe_fds[2] = {-1, -1};
    if (pipe(pipe_fds) != 0) return false;
#ifdef BARISTA_SYSTEM_INFO_TESTING
    if (capture_test_hook) capture_test_hook("after_pipe", path);
#endif
    if (fcntl(pipe_fds[0], F_SETFD, FD_CLOEXEC) != 0
        || fcntl(pipe_fds[1], F_SETFD, FD_CLOEXEC) != 0) {
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        return false;
    }
    int flags = fcntl(pipe_fds[0], F_GETFL, 0);
    if (flags < 0 || fcntl(pipe_fds[0], F_SETFL, flags | O_NONBLOCK) != 0) {
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        return false;
    }

    posix_spawn_file_actions_t actions;
    if (posix_spawn_file_actions_init(&actions) != 0) {
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        return false;
    }
    int action_error = 0;
    action_error |= posix_spawn_file_actions_addclose(&actions, pipe_fds[0]);
    action_error |= posix_spawn_file_actions_adddup2(&actions, pipe_fds[1], STDOUT_FILENO);
    action_error |= posix_spawn_file_actions_addclose(&actions, pipe_fds[1]);
    action_error |= posix_spawn_file_actions_addopen(
        &actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    if (action_error != 0) {
        posix_spawn_file_actions_destroy(&actions);
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        return false;
    }

    posix_spawnattr_t attributes;
    if (posix_spawnattr_init(&attributes) != 0) {
        posix_spawn_file_actions_destroy(&actions);
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        return false;
    }
    if (posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT) != 0) {
        posix_spawnattr_destroy(&attributes);
        posix_spawn_file_actions_destroy(&actions);
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        return false;
    }

    pid_t child = -1;
    int spawn_error = posix_spawn(&child, path, &actions, &attributes, argv, environ);
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    close(pipe_fds[1]);
    if (spawn_error != 0) {
        close(pipe_fds[0]);
        return false;
    }
#ifdef BARISTA_SYSTEM_INFO_TESTING
    if (capture_test_hook) capture_test_hook("after_spawn", path);
#endif

    uint64_t start = monotonic_milliseconds();
    size_t used = 0;
    bool eof = false;
    bool overflow = false;
    bool child_done = false;
    bool timed_out = false;
    bool io_failed = false;
    bool first_line_complete = false;
    int child_status = 0;

    while (!child_done || !eof) {
        uint64_t now = monotonic_milliseconds();
        uint64_t elapsed = now >= start ? now - start : 0;
        if (elapsed >= (uint64_t)timeout_ms) {
            timed_out = true;
            break;
        }
        int remaining = timeout_ms - (int)elapsed;
        if (remaining > 25) remaining = 25;

        struct pollfd descriptor = {
            .fd = pipe_fds[0],
            .events = POLLIN | POLLHUP,
            .revents = 0,
        };
        int poll_result = poll(&descriptor, 1, remaining);
        if (poll_result < 0 && errno != EINTR) {
            io_failed = true;
            break;
        }
        if (poll_result > 0 && (descriptor.revents & (POLLIN | POLLHUP))) {
            while (true) {
                char chunk[4096];
                ssize_t count = read(pipe_fds[0], chunk, sizeof(chunk));
                if (count > 0) {
                    size_t copy_length = (size_t)count;
                    if (first_line_only) {
                        char *newline = memchr(chunk, '\n', copy_length);
                        if (newline) {
                            copy_length = (size_t)(newline - chunk) + 1;
                            first_line_complete = true;
                        }
                    }
                    if (used + copy_length + 1 > output_size) {
                        overflow = true;
                        break;
                    }
                    memcpy(output + used, chunk, copy_length);
                    used += copy_length;
                    if (first_line_complete) break;
                    continue;
                }
                if (count == 0) eof = true;
                if (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
                    eof = true;
                    io_failed = true;
                }
                break;
            }
        }

        if (!child_done) {
            pid_t waited = waitpid(child, &child_status, WNOHANG);
            if (waited == child) child_done = true;
            else if (waited < 0 && errno != EINTR) {
                child_done = true;
                io_failed = true;
            }
        }
        if (overflow || first_line_complete) break;
    }

    bool stopped_after_first_line = first_line_complete && !child_done;
    if (!child_done) {
        kill(child, SIGTERM);
        uint64_t grace_start = monotonic_milliseconds();
        while (monotonic_milliseconds() - grace_start < 25) {
            pid_t waited = waitpid(child, &child_status, WNOHANG);
            if (waited == child) {
                child_done = true;
                break;
            }
            usleep(1000);
        }
        if (!child_done) {
            kill(child, SIGKILL);
            while (waitpid(child, &child_status, 0) < 0 && errno == EINTR) {
            }
            child_done = true;
        }
    }
    close(pipe_fds[0]);
    output[used] = '\0';

    if (first_line_only && used > 0 && !timed_out && !overflow && !io_failed) {
        return stopped_after_first_line
            || (child_done && WIFEXITED(child_status) && WEXITSTATUS(child_status) == 0);
    }
    return !timed_out && !overflow && !io_failed && child_done
        && WIFEXITED(child_status) && WEXITSTATUS(child_status) == 0;
}

static bool capture_process(const char *path,
                            char *const argv[],
                            char *output,
                            size_t output_size,
                            int timeout_ms) {
    return capture_process_internal(path, argv, output, output_size, timeout_ms, false);
}

static bool capture_first_line(const char *path,
                               char *const argv[],
                               char *output,
                               size_t output_size,
                               int timeout_ms) {
    return capture_process_internal(path, argv, output, output_size, timeout_ms, true);
}

static void get_cpu_info(SystemInfo *info) {
    if (!info) return;
    double load_average[3] = {0};
    int cores = 0;
    size_t cores_size = sizeof(cores);
    if (getloadavg(load_average, 3) < 1) return;
    if (sysctlbyname("hw.logicalcpu", &cores, &cores_size, NULL, 0) != 0 || cores <= 0) {
        cores_size = sizeof(cores);
        if (sysctlbyname("hw.ncpu", &cores, &cores_size, NULL, 0) != 0 || cores <= 0) {
            cores = 1;
        }
    }
    info->load_avg = load_average[0];
    info->cpu_percent = clamp_percent((int)((load_average[0] / (double)cores) * 100.0 + 0.5));
    info->cpu_available = true;
}

static void get_memory_info(SystemInfo *info) {
    if (!info) return;
    uint64_t memory_size = 0;
    size_t memory_size_length = sizeof(memory_size);
    if (sysctlbyname("hw.memsize", &memory_size, &memory_size_length, NULL, 0) != 0
        || memory_size == 0) {
        return;
    }

    char *const arguments[] = {"/usr/bin/memory_pressure", NULL};
    char pressure_output[4096];
    if (capture_process("/usr/bin/memory_pressure", arguments, pressure_output,
                        sizeof(pressure_output), DEFAULT_PROBE_TIMEOUT_MS)) {
        const char *prefix = "System-wide memory free percentage: ";
        char *match = strstr(pressure_output, prefix);
        if (match) {
            char *end = NULL;
            long free_percent = strtol(match + strlen(prefix), &end, 10);
            if (end != match + strlen(prefix) && free_percent >= 0 && free_percent <= 100) {
                info->memory_total_bytes = memory_size;
                info->memory_used_bytes = (memory_size * (uint64_t)(100 - free_percent)) / 100ULL;
                info->memory_available = true;
                return;
            }
        }
    }

    mach_port_t host = mach_host_self();
    vm_statistics64_data_t statistics = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_size_t page_size = 0;
    kern_return_t stats_result = host_statistics64(
        host, HOST_VM_INFO64, (host_info64_t)&statistics, &count);
    kern_return_t page_result = host_page_size(host, &page_size);
    mach_port_deallocate(mach_task_self(), host);
    if (stats_result != KERN_SUCCESS || page_result != KERN_SUCCESS || page_size == 0) {
        return;
    }

    uint64_t used_pages = (uint64_t)statistics.internal_page_count
        + (uint64_t)statistics.compressor_page_count;
    uint64_t purgeable = (uint64_t)statistics.purgeable_count;
    used_pages = used_pages > purgeable ? used_pages - purgeable : 0;
    uint64_t used_bytes = used_pages * (uint64_t)page_size;
    if (used_bytes > memory_size) used_bytes = memory_size;

    info->memory_total_bytes = memory_size;
    info->memory_used_bytes = used_bytes;
    info->memory_available = true;
}

static const char *disk_mount_path(void) {
    return access("/System/Volumes/Data", F_OK) == 0
        ? "/System/Volumes/Data"
        : "/";
}

static bool parse_disk_output(char *output, SystemInfo *info) {
    if (!output || !info) return false;
    char *save = NULL;
    char *line = strtok_r(output, "\n", &save);
    char *data_line = NULL;
    while (line) {
        if (line[0] != '\0' && strncmp(line, "Filesystem", 10) != 0) data_line = line;
        line = strtok_r(NULL, "\n", &save);
    }
    if (!data_line) return false;

    char total[SMALL_VALUE_BYTES] = "";
    char used[SMALL_VALUE_BYTES] = "";
    char available[SMALL_VALUE_BYTES] = "";
    int percent = 0;
    if (sscanf(data_line, "%*s %127s %127s %127s %d%%", total, used, available, &percent) != 4) {
        return false;
    }
    (void)available;
    snprintf(info->disk_total, sizeof(info->disk_total), "%s", total);
    snprintf(info->disk_used, sizeof(info->disk_used), "%s", used);
    info->disk_percent = clamp_percent(percent);
    info->disk_available = true;
    return true;
}

static void get_disk_info(SystemInfo *info) {
    if (!info) return;
    const char *mount_path = disk_mount_path();
    char *const arguments[] = {"/bin/df", "-h", (char *)mount_path, NULL};
    char output[4096];
    if (!capture_process("/bin/df", arguments, output, sizeof(output), DEFAULT_PROBE_TIMEOUT_MS)) {
        return;
    }
    parse_disk_output(output, info);
}

static bool valid_interface_name(const char *name) {
    if (!name || name[0] == '\0' || strlen(name) >= IFNAMSIZ) return false;
    for (const unsigned char *cursor = (const unsigned char *)name; *cursor; cursor++) {
        if (!( (*cursor >= 'a' && *cursor <= 'z')
            || (*cursor >= 'A' && *cursor <= 'Z')
            || (*cursor >= '0' && *cursor <= '9')
            || *cursor == '_' || *cursor == '-' || *cursor == '.')) {
            return false;
        }
    }
    return true;
}

static bool interface_ipv4(const char *interface, char *output, size_t output_size) {
    if (!interface || !output || output_size == 0) return false;
    struct ifaddrs *addresses = NULL;
    if (getifaddrs(&addresses) != 0) return false;
    bool found = false;
    for (struct ifaddrs *entry = addresses; entry; entry = entry->ifa_next) {
        if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET
            || strcmp(entry->ifa_name, interface) != 0) {
            continue;
        }
        struct sockaddr_in *address = (struct sockaddr_in *)entry->ifa_addr;
        if (inet_ntop(AF_INET, &address->sin_addr, output, (socklen_t)output_size)) {
            found = true;
            break;
        }
    }
    freeifaddrs(addresses);
    return found;
}

static bool parse_route_interface(const char *command_output,
                                  char *output,
                                  size_t output_size) {
    if (!command_output || !output || output_size == 0) return false;
    const char *match = strstr(command_output, "interface:");
    if (!match) return false;
    match += strlen("interface:");
    while (*match == ' ' || *match == '\t') match++;
    char candidate[IFNAMSIZ] = "";
    size_t length = strcspn(match, " \t\r\n");
    if (length == 0 || length >= sizeof(candidate)) return false;
    memcpy(candidate, match, length);
    candidate[length] = '\0';
    if (!valid_interface_name(candidate)) return false;
    snprintf(output, output_size, "%s", candidate);
    return true;
}

static bool default_route_interface(char *output, size_t output_size) {
    if (!output || output_size == 0) return false;
    char *const arguments[] = {"/sbin/route", "-n", "get", "default", NULL};
    char command_output[4096];
    if (!capture_process("/sbin/route", arguments, command_output,
                         sizeof(command_output), DEFAULT_PROBE_TIMEOUT_MS)) {
        return false;
    }
    return parse_route_interface(command_output, output, output_size);
}

static bool first_active_ipv4(char *interface,
                              size_t interface_size,
                              char *address,
                              size_t address_size) {
    struct ifaddrs *addresses = NULL;
    if (getifaddrs(&addresses) != 0) return false;
    bool found = false;
    for (struct ifaddrs *entry = addresses; entry; entry = entry->ifa_next) {
        if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET
            || (entry->ifa_flags & IFF_UP) == 0 || (entry->ifa_flags & IFF_LOOPBACK) != 0) {
            continue;
        }
        struct sockaddr_in *value = (struct sockaddr_in *)entry->ifa_addr;
        if (!inet_ntop(AF_INET, &value->sin_addr, address, (socklen_t)address_size)) continue;
        snprintf(interface, interface_size, "%s", entry->ifa_name);
        found = true;
        break;
    }
    freeifaddrs(addresses);
    return found;
}

static bool wifi_interface(char *output, size_t output_size) {
    char *const arguments[] = {"/usr/sbin/networksetup", "-listallhardwareports", NULL};
    char command_output[8192];
    if (!capture_process("/usr/sbin/networksetup", arguments, command_output,
                         sizeof(command_output), DEFAULT_PROBE_TIMEOUT_MS)) {
        return false;
    }

    bool found_wifi = false;
    char *save = NULL;
    for (char *line = strtok_r(command_output, "\n", &save);
         line;
         line = strtok_r(NULL, "\n", &save)) {
        if (strncmp(line, "Hardware Port: Wi-Fi", 20) == 0
            || strncmp(line, "Hardware Port: AirPort", 22) == 0) {
            found_wifi = true;
            continue;
        }
        if (found_wifi && strncmp(line, "Device: ", 8) == 0) {
            const char *candidate = line + 8;
            if (!valid_interface_name(candidate)) return false;
            snprintf(output, output_size, "%s", candidate);
            return true;
        }
        if (strncmp(line, "Hardware Port: ", 15) == 0) found_wifi = false;
    }
    return false;
}

static void wifi_network_name(const char *interface, char *output, size_t output_size) {
    if (!valid_interface_name(interface) || !output || output_size == 0) return;
    char *const arguments[] = {
        "/usr/sbin/networksetup", "-getairportnetwork", (char *)interface, NULL,
    };
    char command_output[1024];
    if (!capture_process("/usr/sbin/networksetup", arguments, command_output,
                         sizeof(command_output), DEFAULT_PROBE_TIMEOUT_MS)) {
        return;
    }
    const char *prefix = "Current Wi-Fi Network: ";
    char *match = strstr(command_output, prefix);
    if (!match) return;
    match += strlen(prefix);
    match[strcspn(match, "\r\n")] = '\0';
    if (match[0] == '\0' || strstr(match, "not associated") != NULL) return;
    snprintf(output, output_size, "%s", match);
}

static void get_network_info(SystemInfo *info) {
    if (!info) return;
    char primary[IFNAMSIZ] = "";
    const char *configured = getenv("SKETCHYBAR_NET_INTERFACE");
    if (valid_interface_name(configured)) {
        snprintf(primary, sizeof(primary), "%s", configured);
    } else {
        default_route_interface(primary, sizeof(primary));
    }

    char wifi[IFNAMSIZ] = "";
    bool has_wifi = wifi_interface(wifi, sizeof(wifi));
    if (primary[0] != '\0') {
        interface_ipv4(primary, info->network_ip, sizeof(info->network_ip));
    }
    if (has_wifi && (primary[0] == '\0' || strcmp(primary, wifi) == 0)) {
        if (info->network_ip[0] == '\0') {
            interface_ipv4(wifi, info->network_ip, sizeof(info->network_ip));
        }
        wifi_network_name(wifi, info->network_name, sizeof(info->network_name));
    }
    if (info->network_ip[0] == '\0' && has_wifi) {
        if (interface_ipv4(wifi, info->network_ip, sizeof(info->network_ip))) {
            snprintf(primary, sizeof(primary), "%s", wifi);
            wifi_network_name(wifi, info->network_name, sizeof(info->network_name));
        }
    }
    if (info->network_ip[0] == '\0') {
        first_active_ipv4(primary, sizeof(primary), info->network_ip, sizeof(info->network_ip));
    }
    info->network_online = info->network_ip[0] != '\0' || info->network_name[0] != '\0';
}

static void get_swap_info(SystemInfo *info) {
    if (!info) return;
    struct xsw_usage usage = {0};
    size_t length = sizeof(usage);
    if (sysctlbyname("vm.swapusage", &usage, &length, NULL, 0) != 0) return;
    info->swap_used_bytes = usage.xsu_used;
    info->swap_total_bytes = usage.xsu_total;
    info->swap_available = true;
}

static void get_uptime_info(SystemInfo *info) {
    if (!info) return;
    struct timeval boot_time = {0};
    size_t length = sizeof(boot_time);
    if (sysctlbyname("kern.boottime", &boot_time, &length, NULL, 0) != 0
        || boot_time.tv_sec <= 0) {
        return;
    }
    time_t now = time(NULL);
    if (now < boot_time.tv_sec) return;
    info->uptime_seconds = (uint64_t)(now - boot_time.tv_sec);
    info->uptime_available = true;
}

static bool parse_process_line(char *output, SystemInfo *info) {
    if (!output || !info) return false;
    char *line = output;
    while (*line == ' ' || *line == '\t' || *line == '\r' || *line == '\n') line++;
    char *end = NULL;
    double cpu = strtod(line, &end);
    if (end == line) return false;
    while (*end == ' ' || *end == '\t') end++;
    end[strcspn(end, "\r\n")] = '\0';
    if (end[0] == '\0') return false;
    const char *display_name = strrchr(end, '/');
    display_name = display_name && display_name[1] != '\0' ? display_name + 1 : end;
    info->process_cpu = cpu < 0.0 ? 0.0 : cpu;
    snprintf(info->process_name, sizeof(info->process_name), "%s", display_name);
    info->process_available = true;
    return true;
}

static void get_process_info(SystemInfo *info) {
    if (!info) return;
    char *const arguments[] = {"/bin/ps", "-axo", "pcpu=,comm=", "-r", NULL};
    char output[4096];
    if (!capture_first_line("/bin/ps", arguments, output,
                            sizeof(output), DEFAULT_PROBE_TIMEOUT_MS)) return;
    parse_process_line(output, info);
}

static bool valid_utf8_sequence(const unsigned char *bytes, size_t remaining, size_t *length) {
    unsigned char first = bytes[0];
    if (first < 0x80) {
        *length = 1;
        return true;
    }
    size_t expected = 0;
    uint32_t codepoint = 0;
    if (first >= 0xC2 && first <= 0xDF) {
        expected = 2;
        codepoint = first & 0x1F;
    } else if (first >= 0xE0 && first <= 0xEF) {
        expected = 3;
        codepoint = first & 0x0F;
    } else if (first >= 0xF0 && first <= 0xF4) {
        expected = 4;
        codepoint = first & 0x07;
    } else {
        return false;
    }
    if (remaining < expected) return false;
    for (size_t index = 1; index < expected; index++) {
        unsigned char byte = bytes[index];
        if ((byte & 0xC0) != 0x80) return false;
        codepoint = (codepoint << 6) | (uint32_t)(byte & 0x3F);
    }
    if ((expected == 3 && codepoint < 0x800)
        || (expected == 4 && codepoint < 0x10000)
        || (codepoint >= 0xD800 && codepoint <= 0xDFFF)
        || codepoint > 0x10FFFF) {
        return false;
    }
    *length = expected;
    return true;
}

static void sanitize_text(const char *source, char *output, size_t output_size) {
    if (!output || output_size == 0) return;
    output[0] = '\0';
    if (!source) return;

    const unsigned char *cursor = (const unsigned char *)source;
    size_t source_length = strlen(source);
    size_t source_index = 0;
    size_t used = 0;
    bool last_space = true;

    while (source_index < source_length && used + 1 < output_size) {
        unsigned char byte = cursor[source_index];
        if (byte < 0x20 || byte == 0x7F) {
            if (!last_space && used + 1 < output_size) {
                output[used++] = ' ';
                last_space = true;
            }
            source_index++;
            continue;
        }
        if (byte == ' ' || byte == '\t') {
            if (!last_space && used + 1 < output_size) output[used++] = ' ';
            last_space = true;
            source_index++;
            continue;
        }
        if (byte < 0x80) {
            output[used++] = (char)byte;
            last_space = false;
            source_index++;
            continue;
        }
        size_t sequence_length = 0;
        if (!valid_utf8_sequence(cursor + source_index,
                                 source_length - source_index,
                                 &sequence_length)) {
            if (!last_space && used + 1 < output_size) {
                output[used++] = ' ';
                last_space = true;
            }
            source_index++;
            continue;
        }
        if (used + sequence_length >= output_size) break;
        memcpy(output + used, cursor + source_index, sequence_length);
        used += sequence_length;
        source_index += sequence_length;
        last_space = false;
    }
    while (used > 0 && (output[used - 1] == ' ' || output[used - 1] == '\t')) used--;
    output[used] = '\0';
}

static const char *environment_or_default(const char *name, const char *fallback) {
    const char *value = getenv(name);
    return value && value[0] != '\0' ? value : fallback;
}

static void payload_init(Payload *payload) {
    if (payload) memset(payload, 0, sizeof(*payload));
}

static bool payload_add_token(Payload *payload, const char *token) {
    if (!payload || payload->failed || !token) return false;
    size_t length = strnlen(token, MAX_TOKEN_BYTES + 1);
    if (length > MAX_TOKEN_BYTES || payload->arguments >= MAX_ARGUMENTS
        || payload->length + length + 2 > MAX_PAYLOAD_BYTES) {
        payload->failed = true;
        return false;
    }
    memcpy(payload->bytes + payload->length, token, length);
    payload->length += length;
    payload->bytes[payload->length++] = 0;
    payload->arguments++;
    return true;
}

static bool payload_add_property(Payload *payload, const char *name, const char *value) {
    char clean[LABEL_BYTES];
    char token[MAX_TOKEN_BYTES + 1];
    sanitize_text(value, clean, sizeof(clean));
    int written = snprintf(token, sizeof(token), "%s=%s", name, clean);
    if (written < 0 || (size_t)written >= sizeof(token)) {
        if (payload) payload->failed = true;
        return false;
    }
    return payload_add_token(payload, token);
}

static bool payload_begin_set(Payload *payload, const char *item) {
    return payload_add_token(payload, "--set") && payload_add_token(payload, item);
}

static bool payload_finish(Payload *payload) {
    if (!payload || payload->failed || payload->arguments == 0
        || payload->length + 1 > MAX_PAYLOAD_BYTES) {
        return false;
    }
    payload->bytes[payload->length++] = 0;
    return payload->length >= 2
        && payload->bytes[payload->length - 1] == 0
        && payload->bytes[payload->length - 2] == 0;
}

static uint64_t rounded_gibibytes(uint64_t bytes) {
    const uint64_t gib = 1024ULL * 1024ULL * 1024ULL;
    return (bytes + gib / 2ULL) / gib;
}

static const char *cpu_color(const SystemInfo *info) {
    if (info && info->cpu_available && info->cpu_percent > 80) {
        return environment_or_default("BARISTA_SYSTEM_INFO_RED", "0xfff38ba8");
    }
    if (info && info->cpu_available && info->cpu_percent > 50) {
        return environment_or_default("BARISTA_SYSTEM_INFO_YELLOW", "0xfff9e2af");
    }
    return environment_or_default("BARISTA_SYSTEM_INFO_GREEN", "0xffa6e3a1");
}

static const char *memory_color(const SystemInfo *info) {
    if (!info || !info->memory_available || info->memory_total_bytes == 0) {
        return environment_or_default("BARISTA_SYSTEM_INFO_GREEN", "0xffa6e3a1");
    }
    int percent = clamp_percent((int)((info->memory_used_bytes * 100ULL
        + info->memory_total_bytes / 2ULL) / info->memory_total_bytes));
    if (percent > 80) return environment_or_default("BARISTA_SYSTEM_INFO_RED", "0xfff38ba8");
    if (percent > 60) return environment_or_default("BARISTA_SYSTEM_INFO_YELLOW", "0xfff9e2af");
    return environment_or_default("BARISTA_SYSTEM_INFO_GREEN", "0xffa6e3a1");
}

static bool build_routine_payload(const SystemInfo *info, Payload *payload) {
    if (!info || !payload) return false;
    char label[LABEL_BYTES];
    if (info->cpu_available && info->memory_available) {
        snprintf(label, sizeof(label), "%d%% %llu/%lluG",
                 info->cpu_percent,
                 (unsigned long long)rounded_gibibytes(info->memory_used_bytes),
                 (unsigned long long)rounded_gibibytes(info->memory_total_bytes));
    } else {
        snprintf(label, sizeof(label), "--%% --/--");
    }
    const char *color = cpu_color(info);
    return payload_begin_set(payload, "system_info")
        && payload_add_property(payload, "icon", environment_or_default("BARISTA_ICON_CPU", "󰻠"))
        && payload_add_property(payload, "label", label)
        && payload_add_property(payload, "icon.color", color)
        && payload_add_property(payload, "label.color", color)
        && payload_add_property(payload, "label.font.style", "Semibold");
}

static bool build_popup_payload(const PopupRows *rows,
                                const SystemInfo *info,
                                Payload *payload) {
    if (!rows || !info || !payload) return false;
    char label[LABEL_BYTES];

    if (row_enabled(rows, ROW_CPU)) {
        if (info->cpu_available) {
            snprintf(label, sizeof(label), "CPU Usage: %d%% (Load: %.2f)",
                     info->cpu_percent, info->load_avg);
        } else {
            snprintf(label, sizeof(label), "CPU Usage: --");
        }
        if (!payload_begin_set(payload, "system_info.cpu")
            || !payload_add_property(payload, "label", label)
            || !payload_add_property(payload, "icon", environment_or_default("BARISTA_ICON_CPU", "󰻠"))
            || !payload_add_property(payload, "icon.color", cpu_color(info))) return false;
    }

    if (row_enabled(rows, ROW_MEM)) {
        if (info->memory_available && info->memory_total_bytes > 0) {
            int percent = clamp_percent((int)((info->memory_used_bytes * 100ULL
                + info->memory_total_bytes / 2ULL) / info->memory_total_bytes));
            snprintf(label, sizeof(label), "Memory: %llu/%lluG (%d%%)",
                     (unsigned long long)rounded_gibibytes(info->memory_used_bytes),
                     (unsigned long long)rounded_gibibytes(info->memory_total_bytes),
                     percent);
        } else {
            snprintf(label, sizeof(label), "Memory: --/--");
        }
        if (!payload_begin_set(payload, "system_info.mem")
            || !payload_add_property(payload, "label", label)
            || !payload_add_property(payload, "icon", environment_or_default("BARISTA_ICON_MEM", "󰘚"))
            || !payload_add_property(payload, "icon.color", memory_color(info))) return false;
    }

    if (row_enabled(rows, ROW_DISK)) {
        if (info->disk_available) {
            snprintf(label, sizeof(label), "Disk Usage: %d%% (%s/%s)",
                     info->disk_percent, info->disk_used, info->disk_total);
        } else {
            snprintf(label, sizeof(label), "Disk Usage: --");
        }
        if (!payload_begin_set(payload, "system_info.disk")
            || !payload_add_property(payload, "label", label)
            || !payload_add_property(payload, "icon", environment_or_default("BARISTA_ICON_DISK", "󰋊"))
            || !payload_add_property(payload, "icon.color",
                                     environment_or_default("BARISTA_SYSTEM_INFO_YELLOW", "0xfff9e2af"))) return false;
    }

    if (row_enabled(rows, ROW_NET)) {
        const char *network_icon = environment_or_default("BARISTA_ICON_WIFI_OFF", "󰖪");
        const char *network_color = environment_or_default("BARISTA_SYSTEM_INFO_RED", "0xfff38ba8");
        if (info->network_name[0] != '\0' && info->network_ip[0] != '\0') {
            snprintf(label, sizeof(label), "Wi-Fi: %s (%s)",
                     info->network_name, info->network_ip);
            network_icon = environment_or_default("BARISTA_ICON_WIFI", "󰖩");
            network_color = environment_or_default("BARISTA_SYSTEM_INFO_GREEN", "0xffa6e3a1");
        } else if (info->network_name[0] != '\0') {
            snprintf(label, sizeof(label), "Wi-Fi: %s", info->network_name);
            network_icon = environment_or_default("BARISTA_ICON_WIFI", "󰖩");
            network_color = environment_or_default("BARISTA_SYSTEM_INFO_GREEN", "0xffa6e3a1");
        } else if (info->network_ip[0] != '\0') {
            snprintf(label, sizeof(label), "Network: %s", info->network_ip);
            network_icon = environment_or_default("BARISTA_ICON_WIFI", "󰖩");
            network_color = environment_or_default("BARISTA_SYSTEM_INFO_GREEN", "0xffa6e3a1");
        } else {
            snprintf(label, sizeof(label), "Wi-Fi: Disconnected");
        }
        if (!payload_begin_set(payload, "system_info.net")
            || !payload_add_property(payload, "label", label)
            || !payload_add_property(payload, "icon", network_icon)
            || !payload_add_property(payload, "icon.color", network_color)) return false;
    }

    if (row_enabled(rows, ROW_SWAP)) {
        if (info->swap_available) {
            const double mebibyte = 1024.0 * 1024.0;
            snprintf(label, sizeof(label), "Swap: %.2fM/%.2fM",
                     (double)info->swap_used_bytes / mebibyte,
                     (double)info->swap_total_bytes / mebibyte);
        } else {
            snprintf(label, sizeof(label), "Swap: --");
        }
        if (!payload_begin_set(payload, "system_info.swap")
            || !payload_add_property(payload, "label", label)
            || !payload_add_property(payload, "icon", environment_or_default("BARISTA_ICON_SWAP", "󰾴"))
            || !payload_add_property(payload, "icon.color",
                                     environment_or_default("BARISTA_SYSTEM_INFO_BLUE", "0xff89b4fa"))) return false;
    }

    if (row_enabled(rows, ROW_UPTIME)) {
        if (info->uptime_available) {
            uint64_t days = info->uptime_seconds / 86400ULL;
            uint64_t remainder = info->uptime_seconds % 86400ULL;
            uint64_t hours = remainder / 3600ULL;
            uint64_t minutes = (remainder % 3600ULL) / 60ULL;
            if (days > 0) {
                snprintf(label, sizeof(label), "Uptime: %llud %lluh %llum",
                         (unsigned long long)days,
                         (unsigned long long)hours,
                         (unsigned long long)minutes);
            } else if (hours > 0) {
                snprintf(label, sizeof(label), "Uptime: %lluh %llum",
                         (unsigned long long)hours,
                         (unsigned long long)minutes);
            } else {
                snprintf(label, sizeof(label), "Uptime: %llum",
                         (unsigned long long)minutes);
            }
        } else {
            snprintf(label, sizeof(label), "Uptime: --");
        }
        if (!payload_begin_set(payload, "system_info.uptime")
            || !payload_add_property(payload, "label", label)
            || !payload_add_property(payload, "icon", environment_or_default("BARISTA_ICON_UPTIME", "󰥔"))
            || !payload_add_property(payload, "icon.color",
                                     environment_or_default("BARISTA_SYSTEM_INFO_TEAL", "0xff94e2d5"))) return false;
    }

    if (row_enabled(rows, ROW_PROCS)) {
        if (info->process_available) {
            snprintf(label, sizeof(label), "Top CPU: %s %.1f%%",
                     info->process_name, info->process_cpu);
        } else {
            snprintf(label, sizeof(label), "Top CPU: --");
        }
        if (!payload_begin_set(payload, "system_info.procs")
            || !payload_add_property(payload, "label", label)
            || !payload_add_property(payload, "icon", environment_or_default("BARISTA_ICON_CPU", "󰻠"))
            || !payload_add_property(payload, "icon.color", cpu_color(info))) return false;
    }

    return !payload->failed;
}

static mach_port_t sketchybar_port(void) {
    const char *bar_name = getenv("BAR_NAME");
    if (!bar_name || bar_name[0] == '\0' || strlen(bar_name) > 128) bar_name = "sketchybar";
    char service_name[160];
    int written = snprintf(service_name, sizeof(service_name), "git.felix.%s", bar_name);
    if (written < 0 || (size_t)written >= sizeof(service_name)) return MACH_PORT_NULL;

    mach_port_t bootstrap_port = MACH_PORT_NULL;
    if (task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &bootstrap_port)
        != KERN_SUCCESS) {
        return MACH_PORT_NULL;
    }
    mach_port_t port = MACH_PORT_NULL;
    kern_return_t result = bootstrap_look_up(bootstrap_port, service_name, &port);
    mach_port_deallocate(mach_task_self(), bootstrap_port);
    return result == KERN_SUCCESS ? port : MACH_PORT_NULL;
}

static bool response_is_success(const void *bytes, size_t size) {
    if (!bytes || size == 0 || size > MAX_PAYLOAD_BYTES) return false;
    const char *response = bytes;
    if (memchr(response, '\0', size) == NULL) return false;
    return strstr(response, "[!]") == NULL;
}

static bool send_payload(const Payload *payload) {
    if (!payload || payload->length < 2 || payload->length > MAX_PAYLOAD_BYTES
        || payload->bytes[payload->length - 1] != 0
        || payload->bytes[payload->length - 2] != 0) {
        return false;
    }

    for (int attempt = 0; attempt < 2; attempt++) {
        mach_port_t port = sketchybar_port();
        if (port == MACH_PORT_NULL) continue;

        mach_port_t response_port = MACH_PORT_NULL;
        mach_port_name_t task = mach_task_self();
        if (mach_port_allocate(task, MACH_PORT_RIGHT_RECEIVE, &response_port) != KERN_SUCCESS) {
            mach_port_deallocate(task, port);
            continue;
        }
        if (mach_port_insert_right(task, response_port, response_port, MACH_MSG_TYPE_MAKE_SEND)
            != KERN_SUCCESS) {
            mach_port_mod_refs(task, response_port, MACH_PORT_RIGHT_RECEIVE, -1);
            mach_port_deallocate(task, port);
            continue;
        }

        struct barista_mach_message message = {0};
        message.header.msgh_remote_port = port;
        message.header.msgh_local_port = response_port;
        message.header.msgh_id = response_port;
        message.header.msgh_bits = MACH_MSGH_BITS_SET(
            MACH_MSG_TYPE_COPY_SEND,
            MACH_MSG_TYPE_MAKE_SEND,
            0,
            MACH_MSGH_BITS_COMPLEX);
        message.header.msgh_size = sizeof(message);
        message.descriptor_count = 1;
        message.descriptor.address = (void *)payload->bytes;
        message.descriptor.size = (mach_msg_size_t)payload->length;
        message.descriptor.copy = MACH_MSG_VIRTUAL_COPY;
        message.descriptor.deallocate = false;
        message.descriptor.type = MACH_MSG_OOL_DESCRIPTOR;

        mach_msg_return_t result = mach_msg(&message.header,
                                            MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                                            sizeof(message),
                                            0,
                                            MACH_PORT_NULL,
                                            kMachSendTimeoutMilliseconds,
                                            MACH_PORT_NULL);
        mach_port_deallocate(task, port);

        bool success = false;
        if (result == MACH_MSG_SUCCESS) {
            struct barista_mach_buffer buffer = {0};
            result = mach_msg(&buffer.message.header,
                              MACH_RCV_MSG | MACH_RCV_TIMEOUT,
                              0,
                              sizeof(buffer),
                              response_port,
                              kMachReceiveTimeoutMilliseconds,
                              MACH_PORT_NULL);
            if (result == MACH_MSG_SUCCESS) {
                mach_msg_ool_descriptor_t descriptor = buffer.message.descriptor;
                if (buffer.message.descriptor_count == 1
                    && descriptor.type == MACH_MSG_OOL_DESCRIPTOR
                    && descriptor.address != NULL
                    && descriptor.size > 0
                    && descriptor.size <= MAX_PAYLOAD_BYTES) {
                    success = response_is_success(descriptor.address, descriptor.size);
                }
                mach_msg_destroy(&buffer.message.header);
            }
        }
        mach_port_mod_refs(task, response_port, MACH_PORT_RIGHT_RECEIVE, -1);
        mach_port_deallocate(task, response_port);
        if (success) return true;
    }
    return false;
}

static void gather_routine_info(SystemInfo *info) {
    get_cpu_info(info);
    get_memory_info(info);
}

static void *gather_network_thread(void *context) {
    get_network_info((SystemInfo *)context);
    return NULL;
}

static void *gather_process_thread(void *context) {
    get_process_info((SystemInfo *)context);
    return NULL;
}

static void gather_popup_info(const PopupRows *rows, SystemInfo *info) {
    pthread_t network_thread;
    pthread_t process_thread;
    bool network_started = false;
    bool process_started = false;

    if (row_enabled(rows, ROW_NET)) {
        network_started = pthread_create(&network_thread, NULL, gather_network_thread, info) == 0;
        if (!network_started) get_network_info(info);
    }
    if (row_enabled(rows, ROW_PROCS)) {
        process_started = pthread_create(&process_thread, NULL, gather_process_thread, info) == 0;
        if (!process_started) get_process_info(info);
    }
    if (row_enabled(rows, ROW_CPU) || row_enabled(rows, ROW_PROCS)) get_cpu_info(info);
    if (row_enabled(rows, ROW_MEM)) get_memory_info(info);
    if (row_enabled(rows, ROW_DISK)) get_disk_info(info);
    if (row_enabled(rows, ROW_SWAP)) get_swap_info(info);
    if (row_enabled(rows, ROW_UPTIME)) get_uptime_info(info);
    if (network_started) pthread_join(network_thread, NULL);
    if (process_started) pthread_join(process_thread, NULL);
}

static void usage(const char *program) {
    fprintf(stderr, "Usage: %s [popup_refresh] [--dump0]\n", program);
}

int main(int argc, char *argv[]) {
    bool popup_refresh = false;
    bool dump_payload = false;
    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], "popup_refresh") == 0 && !popup_refresh) {
            popup_refresh = true;
            continue;
        }
        if (strcmp(argv[index], "--dump0") == 0 && !dump_payload) {
            dump_payload = true;
            continue;
        }
        usage(argv[0]);
        return 2;
    }
    if (native_disabled()) return 3;

    PopupRows rows = {.mask = DEFAULT_POPUP_ROWS};
    if (popup_refresh && !parse_popup_rows(getenv("BARISTA_SYSTEM_INFO_ROWS"), &rows)) {
        fprintf(stderr, "Invalid BARISTA_SYSTEM_INFO_ROWS\n");
        return 3;
    }
    if (popup_refresh && rows.mask == 0) return 0;

    SystemInfo info = {0};
    Payload payload;
    payload_init(&payload);
    bool built = false;
    if (popup_refresh) {
        gather_popup_info(&rows, &info);
        built = build_popup_payload(&rows, &info, &payload);
    } else {
        gather_routine_info(&info);
        built = build_routine_payload(&info, &payload);
    }
    if (!built || !payload_finish(&payload)) return 3;

    if (dump_payload) {
        return fwrite(payload.bytes, 1, payload.length, stdout) == payload.length ? 0 : 4;
    }
    return send_payload(&payload) ? 0 : 4;
}
