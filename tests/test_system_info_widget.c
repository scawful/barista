#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define BARISTA_SYSTEM_INFO_TESTING 1
#define main barista_system_info_helper_entry
#include "../helpers/system_info_widget.c"
#undef main

static const char *token_at(const Payload *payload, size_t wanted) {
    size_t index = 0;
    size_t offset = 0;
    while (offset + 1 < payload->length && payload->bytes[offset] != 0) {
        const char *token = (const char *)payload->bytes + offset;
        if (index == wanted) return token;
        offset += strlen(token) + 1;
        index++;
    }
    return NULL;
}

static bool payload_has_token(const Payload *payload, const char *wanted) {
    for (size_t index = 0; index < payload->arguments; index++) {
        const char *token = token_at(payload, index);
        if (token && strcmp(token, wanted) == 0) return true;
    }
    return false;
}

static bool payload_has_prefix(const Payload *payload, const char *prefix) {
    size_t prefix_length = strlen(prefix);
    for (size_t index = 0; index < payload->arguments; index++) {
        const char *token = token_at(payload, index);
        if (token && strncmp(token, prefix, prefix_length) == 0) return true;
    }
    return false;
}

static void assert_group(const Payload *payload,
                         size_t offset,
                         const char *item,
                         const char *label) {
    assert(strcmp(token_at(payload, offset), "--set") == 0);
    assert(strcmp(token_at(payload, offset + 1), item) == 0);
    assert(strcmp(token_at(payload, offset + 2), label) == 0);
    assert(strncmp(token_at(payload, offset + 3), "icon=", 5) == 0);
    assert(strncmp(token_at(payload, offset + 4), "icon.color=", 11) == 0);
}

static SystemInfo fixture_info(void) {
    SystemInfo info = {0};
    info.cpu_available = true;
    info.cpu_percent = 67;
    info.load_avg = 2.5;
    info.memory_available = true;
    info.memory_used_bytes = 11ULL * 1024ULL * 1024ULL * 1024ULL;
    info.memory_total_bytes = 32ULL * 1024ULL * 1024ULL * 1024ULL;
    info.disk_available = true;
    info.disk_percent = 28;
    snprintf(info.disk_used, sizeof(info.disk_used), "120Gi");
    snprintf(info.disk_total, sizeof(info.disk_total), "460Gi");
    info.network_online = true;
    snprintf(info.network_ip, sizeof(info.network_ip), "192.168.1.5");
    snprintf(info.network_name, sizeof(info.network_name),
             "Studio \"WiFi\"\n$(touch /tmp/barista-system-info-injection) --set");
    info.swap_available = true;
    info.swap_used_bytes = 512ULL * 1024ULL * 1024ULL;
    info.swap_total_bytes = 2ULL * 1024ULL * 1024ULL * 1024ULL;
    info.uptime_available = true;
    info.uptime_seconds = 86400ULL + 2ULL * 3600ULL + 3ULL * 60ULL;
    info.process_available = true;
    info.process_cpu = 99.5;
    snprintf(info.process_name, sizeof(info.process_name),
             "evil\n--set $(touch /tmp/barista-system-info-process-injection)");
    return info;
}

static void test_row_parser(void) {
    PopupRows rows = {0};
    assert(parse_popup_rows(NULL, &rows));
    assert(rows.mask == DEFAULT_POPUP_ROWS);
    assert(parse_popup_rows("cpu,mem,disk,net,swap,uptime,procs", &rows));
    assert(rows.mask == ALL_POPUP_ROWS);
    assert(parse_popup_rows("none", &rows));
    assert(rows.mask == 0);
    assert(!parse_popup_rows("cpu,cpu", &rows));
    assert(!parse_popup_rows("cpu,unknown", &rows));
    assert(!parse_popup_rows(",cpu", &rows));
    assert(!parse_popup_rows("cpu,", &rows));
    assert(!parse_popup_rows("cpu,,mem", &rows));
    assert(!parse_popup_rows("cpu, mem", &rows));
}

static void test_popup_payload(void) {
    unlink("/tmp/barista-system-info-injection");
    unlink("/tmp/barista-system-info-process-injection");
    setenv("BARISTA_ICON_CPU", "CPU_ICON", 1);
    setenv("BARISTA_ICON_MEM", "MEM_ICON", 1);
    setenv("BARISTA_ICON_DISK", "DISK_ICON", 1);
    setenv("BARISTA_ICON_WIFI", "WIFI_ICON", 1);
    setenv("BARISTA_ICON_WIFI_OFF", "WIFI_OFF_ICON", 1);
    setenv("BARISTA_ICON_SWAP", "SWAP_ICON", 1);
    setenv("BARISTA_ICON_UPTIME", "UPTIME_ICON", 1);
    setenv("BARISTA_SYSTEM_INFO_RED", "RED", 1);
    setenv("BARISTA_SYSTEM_INFO_YELLOW", "YELLOW", 1);
    setenv("BARISTA_SYSTEM_INFO_GREEN", "GREEN", 1);
    setenv("BARISTA_SYSTEM_INFO_BLUE", "BLUE", 1);
    setenv("BARISTA_SYSTEM_INFO_TEAL", "TEAL", 1);

    PopupRows rows = {.mask = ALL_POPUP_ROWS};
    SystemInfo info = fixture_info();
    Payload payload;
    payload_init(&payload);
    assert(build_popup_payload(&rows, &info, &payload));
    assert(payload_finish(&payload));
    assert(payload.arguments == 35);
    assert(payload.bytes[payload.length - 1] == 0);
    assert(payload.bytes[payload.length - 2] == 0);

    assert_group(&payload, 0, "system_info.cpu", "label=CPU Usage: 67% (Load: 2.50)");
    assert_group(&payload, 5, "system_info.mem", "label=Memory: 11/32G (34%)");
    assert_group(&payload, 10, "system_info.disk", "label=Disk Usage: 28% (120Gi/460Gi)");
    assert_group(
        &payload,
        15,
        "system_info.net",
        "label=Wi-Fi: Studio \"WiFi\" $(touch /tmp/barista-system-info-injection) --set (192.168.1.5)");
    assert_group(&payload, 20, "system_info.swap", "label=Swap: 512.00M/2048.00M");
    assert_group(&payload, 25, "system_info.uptime", "label=Uptime: 1d 2h 3m");
    assert_group(
        &payload,
        30,
        "system_info.procs",
        "label=Top CPU: evil --set $(touch /tmp/barista-system-info-process-injection) 99.5%");
    assert(strcmp(token_at(&payload, 18), "icon=WIFI_ICON") == 0);
    assert(strcmp(token_at(&payload, 19), "icon.color=GREEN") == 0);
    assert(!payload_has_token(&payload, "touch"));
    assert(access("/tmp/barista-system-info-injection", F_OK) != 0);
    assert(access("/tmp/barista-system-info-process-injection", F_OK) != 0);

    rows.mask = ROW_MEM | ROW_UPTIME;
    payload_init(&payload);
    assert(build_popup_payload(&rows, &info, &payload));
    assert(payload_finish(&payload));
    assert(payload.arguments == 10);
    assert(payload_has_token(&payload, "system_info.mem"));
    assert(payload_has_token(&payload, "system_info.uptime"));
    assert(!payload_has_prefix(&payload, "system_info.cpu"));
    assert(!payload_has_prefix(&payload, "system_info.net"));
}

static void test_placeholders_and_routine(void) {
    PopupRows rows = {.mask = ROW_CPU | ROW_MEM | ROW_DISK | ROW_NET | ROW_SWAP | ROW_UPTIME | ROW_PROCS};
    SystemInfo empty = {0};
    Payload payload;
    payload_init(&payload);
    assert(build_popup_payload(&rows, &empty, &payload));
    assert(payload_finish(&payload));
    assert(payload_has_token(&payload, "label=CPU Usage: --"));
    assert(payload_has_token(&payload, "label=Memory: --/--"));
    assert(payload_has_token(&payload, "label=Disk Usage: --"));
    assert(payload_has_token(&payload, "label=Wi-Fi: Disconnected"));
    assert(payload_has_token(&payload, "label=Swap: --"));
    assert(payload_has_token(&payload, "label=Uptime: --"));
    assert(payload_has_token(&payload, "label=Top CPU: --"));

    SystemInfo info = fixture_info();
    payload_init(&payload);
    assert(build_routine_payload(&info, &payload));
    assert(payload_finish(&payload));
    assert(payload.arguments == 7);
    assert(strcmp(token_at(&payload, 0), "--set") == 0);
    assert(strcmp(token_at(&payload, 1), "system_info") == 0);
    assert(payload_has_token(&payload, "label=67% 11/32G"));
}

static void test_sanitizer_and_bounds(void) {
    char clean[64];
    const char hostile[] = "bad\xff\nvalue\tend";
    sanitize_text(hostile, clean, sizeof(clean));
    assert(strcmp(clean, "bad value end") == 0);

    Payload payload;
    payload_init(&payload);
    for (size_t index = 0; index < MAX_ARGUMENTS; index++) {
        assert(payload_add_token(&payload, "x"));
    }
    assert(!payload_add_token(&payload, "overflow"));
    assert(payload.failed);

    char long_token[MAX_TOKEN_BYTES + 2];
    memset(long_token, 'x', sizeof(long_token));
    long_token[sizeof(long_token) - 1] = '\0';
    payload_init(&payload);
    assert(!payload_add_token(&payload, long_token));
    assert(payload.failed);
}

static void test_response_parser(void) {
    const char success[] = "ok\0";
    const char notice[] = "notice\0";
    const char failure[] = "[!] Item not found\0";
    const char unterminated[] = {'o', 'k'};
    assert(response_is_success(success, sizeof(success)));
    assert(response_is_success(notice, sizeof(notice)));
    assert(!response_is_success(failure, sizeof(failure)));
    assert(!response_is_success(unterminated, sizeof(unterminated)));
    assert(!response_is_success(success, MAX_PAYLOAD_BYTES + 1));
}

static void test_memory_vm_stats_and_floor_labels(void) {
    const uint64_t gib = 1024ULL * 1024ULL * 1024ULL;
    vm_statistics64_data_t statistics = {0};
    statistics.active_count = 5;
    statistics.wire_count = 3;
    statistics.compressor_page_count = 2;
    SystemInfo info = {0};
    assert(memory_info_from_vm_stats(32 * gib, 1024 * 1024, &statistics, &info));
    assert(info.memory_available);
    assert(info.memory_total_bytes == 32 * gib);
    assert(info.memory_used_bytes == 10ULL * 1024ULL * 1024ULL);

    statistics.active_count = UINT32_MAX;
    statistics.wire_count = UINT32_MAX;
    statistics.compressor_page_count = UINT32_MAX;
    memset(&info, 0, sizeof(info));
    assert(memory_info_from_vm_stats(32 * gib, 16384, &statistics, &info));
    assert(info.memory_used_bytes == 32 * gib);
    assert(!memory_info_from_vm_stats(0, 16384, &statistics, &info));
    assert(!memory_info_from_vm_stats(32 * gib, 0, &statistics, &info));

    info = fixture_info();
    info.memory_used_bytes = 11 * gib + gib - 1;
    PopupRows rows = {.mask = ROW_MEM};
    Payload payload;
    payload_init(&payload);
    assert(build_popup_payload(&rows, &info, &payload));
    assert(payload_finish(&payload));
    assert(payload_has_token(&payload, "label=Memory: 11/32G (37%)"));
    assert(floor_gibibytes(gib - 1) == 0);
    assert(floor_gibibytes(gib) == 1);
}

static void test_wifi_interface_candidates(void) {
    char output[IFNAMSIZ] = "sentinel";
    assert(wifi_interface_candidate(CFSTR("en7"),
                                    kSCNetworkInterfaceTypeIEEE80211,
                                    output,
                                    sizeof(output)));
    assert(strcmp(output, "en7") == 0);

    snprintf(output, sizeof(output), "sentinel");
    assert(!wifi_interface_candidate(CFSTR("en7"),
                                     kSCNetworkInterfaceTypeEthernet,
                                     output,
                                     sizeof(output)));
    assert(output[0] == '\0');

    int number_value = 7;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &number_value);
    assert(number);
    assert(!wifi_interface_candidate(number,
                                     kSCNetworkInterfaceTypeIEEE80211,
                                     output,
                                     sizeof(output)));
    assert(!wifi_interface_candidate(CFSTR("en7"), number, output, sizeof(output)));
    CFRelease(number);

    assert(!wifi_interface_candidate(CFSTR("../../bad"),
                                     kSCNetworkInterfaceTypeIEEE80211,
                                     output,
                                     sizeof(output)));
    assert(!wifi_interface_candidate(CFSTR("en7"),
                                     kSCNetworkInterfaceTypeIEEE80211,
                                     output,
                                     3));
    assert(!wifi_interface_candidate(
        CFSTR("interface-name-that-exceeds-the-system-bound"),
        kSCNetworkInterfaceTypeIEEE80211,
        output,
        sizeof(output)));

    const UniChar embedded_nul[] = {'e', 'n', '0', 0, 'x'};
    CFStringRef malformed = CFStringCreateWithCharacters(
        NULL, embedded_nul, (CFIndex)(sizeof(embedded_nul) / sizeof(embedded_nul[0])));
    assert(malformed);
    assert(!wifi_interface_candidate(malformed,
                                     kSCNetworkInterfaceTypeIEEE80211,
                                     output,
                                     sizeof(output)));
    CFRelease(malformed);
}

static void test_probe_parsers_and_bounds(void) {
    char disk_fixture[] =
        "Filesystem Size Used Avail Capacity Mounted on\n"
        "/dev/disk3s5 1.8Ti 1.7Ti 14Gi 99% /System/Volumes/Data\n";
    SystemInfo disk = {0};
    assert(parse_disk_output(disk_fixture, &disk));
    assert(disk.disk_available);
    assert(disk.disk_percent == 99);
    assert(strcmp(disk.disk_used, "1.7Ti") == 0);
    assert(strcmp(disk.disk_total, "1.8Ti") == 0);
    if (access("/System/Volumes/Data", F_OK) == 0) {
        assert(strcmp(disk_mount_path(), "/System/Volumes/Data") == 0);
    }

    const char route_fixture[] =
        "route to: default\n"
        "gateway: 192.168.1.1\n"
        "interface: en7\n";
    char interface[IFNAMSIZ] = "";
    assert(parse_route_interface(route_fixture, interface, sizeof(interface)));
    assert(strcmp(interface, "en7") == 0);
    assert(!parse_route_interface("interface: ../../bad\n", interface, sizeof(interface)));

    char process_fixture[] = "  87.4 123 Test App   \n";
    ProcessSample sample = {0};
    assert(parse_process_line(process_fixture, &sample));
    assert(sample.pid == 123);
    assert(sample.cpu > 87.3 && sample.cpu < 87.5);
    assert(strcmp(sample.fallback_name, "Test App") == 0);

    char localized_process_fixture[] = "  87,4 123 Test App\n";
    assert(parse_process_line(localized_process_fixture, &sample));
    assert(sample.cpu > 87.3 && sample.cpu < 87.5);

    SystemInfo process = {0};
    assert(process_info_from_sample(&sample,
                                    "/Applications/Test App.app/Contents/MacOS/Test App",
                                    "ignored-name",
                                    &process));
    assert(process.process_available);
    assert(process.process_cpu > 87.3 && process.process_cpu < 87.5);
    assert(strcmp(process.process_name, "Test App") == 0);

    memset(&process, 0, sizeof(process));
    assert(process_info_from_sample(&sample, NULL, "Long Process Name", &process));
    assert(strcmp(process.process_name, "Long Process Name") == 0);
    memset(&process, 0, sizeof(process));
    assert(process_info_from_sample(&sample, NULL, NULL, &process));
    assert(strcmp(process.process_name, "Test App") == 0);

    char invalid_pid[] = "10.0 0 invalid\n";
    char missing_name[] = "10.0 123   \n";
    char missing_pid[] = "10.0 process\n";
    char nonfinite_cpu[] = "nan 123 process\n";
    assert(!parse_process_line(invalid_pid, &sample));
    assert(!parse_process_line(missing_name, &sample));
    assert(!parse_process_line(missing_pid, &sample));
    assert(!parse_process_line(nonfinite_cpu, &sample));

    char output[64];
    char *const echo_arguments[] = {"/bin/echo", "hello", NULL};
    assert(capture_process("/bin/echo", echo_arguments, output, sizeof(output), 100));
    assert(strcmp(output, "hello\n") == 0);

    char *const sleep_arguments[] = {"/bin/sleep", "1", NULL};
    uint64_t start = monotonic_milliseconds();
    assert(!capture_process("/bin/sleep", sleep_arguments, output, sizeof(output), 20));
    assert(monotonic_milliseconds() - start < 250);

    char *const yes_arguments[] = {"/usr/bin/yes", NULL};
    assert(!capture_process("/usr/bin/yes", yes_arguments, output, sizeof(output), 100));
}

typedef struct {
    const char *path;
    char *const *arguments;
    int timeout_ms;
    bool result;
    uint64_t elapsed_ms;
} CaptureCase;

static pthread_mutex_t capture_hook_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t capture_hook_condition = PTHREAD_COND_INITIALIZER;
static bool capture_block_next_pipe = false;
static bool capture_first_pipe_ready = false;
static bool capture_release_first_pipe = false;
static bool capture_slow_child_spawned = false;

static void coordinated_capture_hook(const char *stage, const char *path) {
    pthread_mutex_lock(&capture_hook_mutex);
    if (strcmp(stage, "after_pipe") == 0 && capture_block_next_pipe) {
        capture_block_next_pipe = false;
        capture_first_pipe_ready = true;
        pthread_cond_broadcast(&capture_hook_condition);
        while (!capture_release_first_pipe) {
            pthread_cond_wait(&capture_hook_condition, &capture_hook_mutex);
        }
    } else if (strcmp(stage, "after_spawn") == 0 && strcmp(path, "/bin/sleep") == 0) {
        capture_slow_child_spawned = true;
        pthread_cond_broadcast(&capture_hook_condition);
    }
    pthread_mutex_unlock(&capture_hook_mutex);
}

static void *run_capture_case(void *context) {
    CaptureCase *capture = context;
    char output[64];
    uint64_t start = monotonic_milliseconds();
    capture->result = capture_process(
        capture->path, capture->arguments, output, sizeof(output), capture->timeout_ms);
    capture->elapsed_ms = monotonic_milliseconds() - start;
    return NULL;
}

static void test_concurrent_capture_descriptor_isolation(void) {
    char *const echo_arguments[] = {"/bin/echo", "isolated", NULL};
    char *const sleep_arguments[] = {"/bin/sleep", "0.2", NULL};
    CaptureCase fast = {
        .path = "/bin/echo",
        .arguments = echo_arguments,
        .timeout_ms = 75,
    };
    CaptureCase slow = {
        .path = "/bin/sleep",
        .arguments = sleep_arguments,
        .timeout_ms = 1000,
    };
    pthread_t fast_thread;
    pthread_t slow_thread;

    pthread_mutex_lock(&capture_hook_mutex);
    capture_block_next_pipe = true;
    capture_first_pipe_ready = false;
    capture_release_first_pipe = false;
    capture_slow_child_spawned = false;
    capture_test_hook = coordinated_capture_hook;
    pthread_mutex_unlock(&capture_hook_mutex);

    assert(pthread_create(&fast_thread, NULL, run_capture_case, &fast) == 0);
    pthread_mutex_lock(&capture_hook_mutex);
    while (!capture_first_pipe_ready) {
        pthread_cond_wait(&capture_hook_condition, &capture_hook_mutex);
    }
    pthread_mutex_unlock(&capture_hook_mutex);

    assert(pthread_create(&slow_thread, NULL, run_capture_case, &slow) == 0);
    pthread_mutex_lock(&capture_hook_mutex);
    while (!capture_slow_child_spawned) {
        pthread_cond_wait(&capture_hook_condition, &capture_hook_mutex);
    }
    capture_release_first_pipe = true;
    pthread_cond_broadcast(&capture_hook_condition);
    pthread_mutex_unlock(&capture_hook_mutex);

    assert(pthread_join(fast_thread, NULL) == 0);
    assert(pthread_join(slow_thread, NULL) == 0);
    capture_test_hook = NULL;

    assert(fast.result);
    assert(fast.elapsed_ms < 150);
    assert(slow.result);
}

int main(void) {
    test_row_parser();
    test_popup_payload();
    test_placeholders_and_routine();
    test_sanitizer_and_bounds();
    test_response_parser();
    test_memory_vm_stats_and_floor_labels();
    test_wifi_interface_candidates();
    test_probe_parsers_and_bounds();
    test_concurrent_capture_descriptor_isolation();
    puts("test_system_info_widget.c: ok");
    return 0;
}
