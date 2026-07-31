#define BARISTA_POPUP_MANAGER_TESTING 1
#define main barista_popup_manager_main
#include "../helpers/popup_manager.c"
#undef main

#include <assert.h>
#include <sys/stat.h>

static MachDispatchResult configured_mach_result = MACH_DISPATCH_NOT_SENT;
static SketchybarPayload captured_payload = {0};
static int mach_calls = 0;
static int cli_calls = 0;
static int configured_cli_result = 0;
static int captured_replace_process = -1;
static char captured_binary[PATH_MAX] = {0};
static char *captured_argv[MAX_SKETCHYBAR_PAYLOAD_ARGUMENTS + 2] = {0};
static size_t captured_argc = 0;

static void clear_captured_argv(void) {
  for (size_t i = 0; i < captured_argc; i++) {
    free(captured_argv[i]);
    captured_argv[i] = NULL;
  }
  captured_argc = 0;
}

static void reset_capture(void) {
  clear_captured_argv();
  memset(&captured_payload, 0, sizeof(captured_payload));
  memset(captured_binary, 0, sizeof(captured_binary));
  mach_calls = 0;
  cli_calls = 0;
  configured_cli_result = 0;
  captured_replace_process = -1;
  unsetenv("BARISTA_POPUP_MACH_DISABLE");
  unsetenv("BARISTA_SKETCHYBAR_BIN");
  unsetenv("BAR_NAME");
}

static MachDispatchResult capture_mach(const SketchybarPayload *payload) {
  mach_calls++;
  assert(payload != NULL);
  captured_payload = *payload;
  return configured_mach_result;
}

static int capture_cli(const char *binary, char **argv, size_t argc, int replace_process) {
  cli_calls++;
  assert(binary != NULL);
  assert(argv != NULL);
  assert(argc < MAX_SKETCHYBAR_PAYLOAD_ARGUMENTS + 2);
  snprintf(captured_binary, sizeof(captured_binary), "%s", binary);
  captured_argc = argc;
  captured_replace_process = replace_process;
  for (size_t i = 0; i < argc; i++) {
    captured_argv[i] = strdup(argv[i]);
    assert(captured_argv[i] != NULL);
  }
  assert(argv[argc] == NULL);
  return configured_cli_result;
}

static void reset_topology(void) {
  free_list(&popup_items);
  free_list(&submenu_parents);
  free_ancestor_list(&submenu_ancestors);
  assert(append_name(&popup_items, "front_app"));
  assert(append_name(&popup_items, "control_center"));
  assert(append_name(&submenu_parents, "front_app.more"));
  assert(append_name(&submenu_parents, "cc.more"));
}

static void assert_payload_tokens(const char **expected, size_t expected_count) {
  assert(captured_payload.arguments == expected_count);
  assert(captured_payload.length >= 2);
  size_t offset = 0;
  for (size_t i = 0; i < expected_count; i++) {
    assert(offset < captured_payload.length);
    const char *actual = (const char *)(captured_payload.bytes + offset);
    assert(strcmp(actual, expected[i]) == 0);
    offset += strlen(actual) + 1;
  }
  assert(offset + 1 == captured_payload.length);
  assert(captured_payload.bytes[offset] == 0);
  assert(captured_payload.bytes[captured_payload.length - 2] == 0);
  assert(captured_payload.bytes[captured_payload.length - 1] == 0);
}

static void assert_payload_matches_captured_cli(void) {
  assert(captured_argc == captured_payload.arguments + 1);
  size_t offset = 0;
  for (size_t i = 1; i < captured_argc; i++) {
    assert(offset < captured_payload.length);
    const char *token = (const char *)(captured_payload.bytes + offset);
    assert(strcmp(token, captured_argv[i]) == 0);
    offset += strlen(token) + 1;
  }
  assert(offset + 1 == captured_payload.length);
  assert(captured_payload.bytes[offset] == 0);
}

static void assert_root_switch_payload(void) {
  static const char *expected[] = {
    "--set", "front_app", "popup.drawing=off",
    "--set", "front_app.more", "popup.drawing=off",
    "background.drawing=off", "background.color=0x00000000",
    "--set", "cc.more", "popup.drawing=off",
    "background.drawing=off", "background.color=0x00000000",
    "--set", "control_center", "popup.drawing=toggle",
  };
  assert_payload_tokens(expected, sizeof(expected) / sizeof(expected[0]));
}

static void test_confirmed_direct_dispatch(void) {
  reset_capture();
  reset_topology();
  configured_mach_result = MACH_DISPATCH_CONFIRMED_SUCCESS;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, "control_center", 1) == 0);
  assert(mach_calls == 1);
  assert(cli_calls == 0);
  assert_root_switch_payload();
}

static void test_unconfirmed_delivery_is_not_replayed(void) {
  reset_capture();
  reset_topology();
  configured_mach_result = MACH_DISPATCH_SENT_UNCONFIRMED;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, "control_center", 1) == 0);
  assert(mach_calls == 1);
  assert(cli_calls == 0);
}

static void test_confirmed_error_is_not_replayed(void) {
  reset_capture();
  reset_topology();
  configured_mach_result = MACH_DISPATCH_CONFIRMED_ERROR;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, "control_center", 1) == 1);
  assert(mach_calls == 1);
  assert(cli_calls == 0);
}

static void test_not_sent_falls_back_to_exact_argv(void) {
  reset_capture();
  reset_topology();
  configured_mach_result = MACH_DISPATCH_NOT_SENT;
  configured_cli_result = 23;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, "control_center", 1) == 23);
  assert(mach_calls == 1);
  assert(cli_calls == 1);
  assert(captured_replace_process == 1);
  assert(strcmp(captured_binary, "sketchybar") == 0);
  assert_payload_matches_captured_cli();
  assert(strcmp(captured_argv[0], "sketchybar") == 0);
  assert(strcmp(captured_argv[captured_argc - 3], "--set") == 0);
  assert(strcmp(captured_argv[captured_argc - 2], "control_center") == 0);
  assert(strcmp(captured_argv[captured_argc - 1], "popup.drawing=toggle") == 0);
}

static void test_custom_binary_stays_on_exact_argv(void) {
  reset_capture();
  reset_topology();
  const char *custom = "/tmp/custom bin;literal/sketchybar";
  setenv("BARISTA_SKETCHYBAR_BIN", custom, 1);
  configured_mach_result = MACH_DISPATCH_CONFIRMED_SUCCESS;
  configured_cli_result = 17;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, "control_center", 1) == 17);
  assert(mach_calls == 0);
  assert(cli_calls == 1);
  assert(strcmp(captured_binary, custom) == 0);
  assert(strcmp(captured_argv[0], custom) == 0);
}

static void test_canonical_configured_binary_uses_direct_payload(void) {
  reset_capture();
  reset_topology();
  setenv("BARISTA_SKETCHYBAR_BIN", "/opt/homebrew/bin/sketchybar", 1);
  configured_mach_result = MACH_DISPATCH_CONFIRMED_SUCCESS;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, "control_center", 1) == 0);
  assert(mach_calls == 1);
  assert(cli_calls == 0);
  assert_root_switch_payload();
}

static void test_explicit_bare_binary_stays_on_exact_argv(void) {
  reset_capture();
  reset_topology();
  setenv("BARISTA_SKETCHYBAR_BIN", "sketchybar", 1);
  configured_mach_result = MACH_DISPATCH_CONFIRMED_SUCCESS;
  configured_cli_result = 19;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, "control_center", 1) == 19);
  assert(mach_calls == 0);
  assert(cli_calls == 1);
  assert(strcmp(captured_binary, "sketchybar") == 0);
}

static void test_disable_gate_stays_on_exact_argv(void) {
  reset_capture();
  reset_topology();
  setenv("BARISTA_POPUP_MACH_DISABLE", "true", 1);
  configured_cli_result = 9;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, "control_center", 1) == 9);
  assert(mach_calls == 0);
  assert(cli_calls == 1);
}

static void test_oversized_bar_name_stays_on_exact_argv(void) {
  reset_capture();
  reset_topology();
  char bar_name[130];
  memset(bar_name, 'b', sizeof(bar_name) - 1);
  bar_name[sizeof(bar_name) - 1] = '\0';
  setenv("BAR_NAME", bar_name, 1);
  configured_cli_result = 11;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, "control_center", 1) == 11);
  assert(mach_calls == 0);
  assert(cli_calls == 1);
}

static void test_maximum_bar_name_uses_direct_payload(void) {
  reset_capture();
  reset_topology();
  char bar_name[129];
  memset(bar_name, 'b', sizeof(bar_name) - 1);
  bar_name[sizeof(bar_name) - 1] = '\0';
  setenv("BAR_NAME", bar_name, 1);
  configured_mach_result = MACH_DISPATCH_CONFIRMED_SUCCESS;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, "control_center", 1) == 0);
  assert(mach_calls == 1);
  assert(cli_calls == 0);
}

static void test_stale_generation_uses_target_only_direct_payload(void) {
  reset_capture();
  free_list(&popup_items);
  free_list(&submenu_parents);
  free_ancestor_list(&submenu_ancestors);

  char temporary_directory[PATH_MAX];
  int directory_length = snprintf(temporary_directory,
                                  sizeof(temporary_directory),
                                  "/tmp/barista-popup-dispatch.%ld",
                                  (long)getpid());
  assert(directory_length > 0
         && (size_t)directory_length < sizeof(temporary_directory));
  assert(mkdir(temporary_directory, 0700) == 0);
  char topology_path[PATH_MAX];
  int written = snprintf(topology_path,
                         sizeof(topology_path),
                         "%s/sketchybar_popup_topology",
                         temporary_directory);
  assert(written > 0 && (size_t)written < sizeof(topology_path));
  FILE *topology = fopen(topology_path, "w");
  assert(topology != NULL);
  assert(fputs("version\t1\n"
               "generation\tstale\n"
               "root\tfront_app\n"
               "child\tfront_app.more\n",
               topology) >= 0);
  assert(fclose(topology) == 0);

  setenv("TMPDIR", temporary_directory, 1);
  setenv("BARISTA_POPUP_TOPOLOGY_TOKEN", "current", 1);
  load_lists(1);
  assert(popup_items.count == 0);
  assert(submenu_parents.count == 0);

  configured_mach_result = MACH_DISPATCH_CONFIRMED_SUCCESS;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, "clock", 1) == 0);
  assert(mach_calls == 1);
  assert(cli_calls == 0);
  static const char *expected[] = {
    "--set", "clock", "popup.drawing=toggle",
  };
  assert_payload_tokens(expected, sizeof(expected) / sizeof(expected[0]));

  unsetenv("TMPDIR");
  unsetenv("BARISTA_POPUP_TOPOLOGY_TOKEN");
  assert(unlink(topology_path) == 0);
  assert(rmdir(temporary_directory) == 0);
}

static void test_event_dismiss_uses_direct_payload(void) {
  reset_capture();
  reset_topology();
  configured_mach_result = MACH_DISPATCH_CONFIRMED_SUCCESS;
  assert(run_sketchybar(MUTATION_DISMISS_ALL, NULL, 0) == 0);
  assert(mach_calls == 1);
  assert(cli_calls == 0);
  assert(captured_payload.arguments > 0);
  assert(strcmp((const char *)captured_payload.bytes, "--set") == 0);
}

static void test_oversized_target_falls_back_before_send(void) {
  reset_capture();
  reset_topology();
  char target[MAX_SKETCHYBAR_TOKEN_BYTES + 2];
  memset(target, 'x', sizeof(target) - 1);
  target[sizeof(target) - 1] = '\0';
  configured_cli_result = 5;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, target, 1) == 5);
  assert(mach_calls == 0);
  assert(cli_calls == 1);
  assert(strcmp(captured_argv[captured_argc - 2], target) == 0);
}

static void append_maximum_topology(NameList *list, const char *prefix) {
  char name[MAX_TOPOLOGY_NAME_LENGTH + 1];
  for (size_t i = 0; i < MAX_TOPOLOGY_NAMES; i++) {
    int written = snprintf(name, sizeof(name), "%s-%03zu-", prefix, i);
    assert(written > 0);
    assert((size_t)written < sizeof(name));
    memset(name + written, 'x', MAX_TOPOLOGY_NAME_LENGTH - (size_t)written);
    name[MAX_TOPOLOGY_NAME_LENGTH] = '\0';
    assert(append_name(list, name));
  }
}

static void test_maximum_topology_fits_direct_payload(void) {
  reset_capture();
  free_list(&popup_items);
  free_list(&submenu_parents);
  free_ancestor_list(&submenu_ancestors);
  append_maximum_topology(&popup_items, "root");
  append_maximum_topology(&submenu_parents, "child");
  char target[MAX_TOPOLOGY_NAME_LENGTH + 1];
  memset(target, 't', sizeof(target) - 1);
  target[sizeof(target) - 1] = '\0';
  configured_mach_result = MACH_DISPATCH_CONFIRMED_SUCCESS;
  assert(run_sketchybar(MUTATION_SWITCH_ROOT, target, 1) == 0);
  assert(mach_calls == 1);
  assert(cli_calls == 0);
  assert(captured_payload.arguments == MAX_SKETCHYBAR_PAYLOAD_ARGUMENTS);
  assert(captured_payload.length == 45596);
  assert(captured_payload.length < MAX_SKETCHYBAR_PAYLOAD_BYTES);
  size_t final_offset = captured_payload.length - strlen(target)
    - strlen("popup.drawing=toggle") - strlen("--set") - 4;
  assert(strcmp((const char *)(captured_payload.bytes + final_offset), "--set") == 0);
}

int main(void) {
  mach_dispatch_test_hook = capture_mach;
  cli_dispatch_test_hook = capture_cli;
  test_confirmed_direct_dispatch();
  test_unconfirmed_delivery_is_not_replayed();
  test_confirmed_error_is_not_replayed();
  test_not_sent_falls_back_to_exact_argv();
  test_custom_binary_stays_on_exact_argv();
  test_canonical_configured_binary_uses_direct_payload();
  test_explicit_bare_binary_stays_on_exact_argv();
  test_disable_gate_stays_on_exact_argv();
  test_oversized_bar_name_stays_on_exact_argv();
  test_maximum_bar_name_uses_direct_payload();
  test_event_dismiss_uses_direct_payload();
  test_oversized_target_falls_back_before_send();
  test_stale_generation_uses_target_only_direct_payload();
  test_maximum_topology_fits_direct_payload();
  reset_capture();
  free_list(&popup_items);
  free_list(&submenu_parents);
  free_ancestor_list(&submenu_ancestors);
  puts("test_popup_manager_dispatch.c: ok");
  return 0;
}
