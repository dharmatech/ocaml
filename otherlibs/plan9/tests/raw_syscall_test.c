/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*                             Dharmatech                                 */
/*                                                                        */
/*   Copyright 2026 Dharmatech                                            */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../../../runtime/plan9_syscall.h"

enum {
  RAW_ERROR_SENTINEL = 0xa5,
  RAW_REPEAT_COUNT = 256,
  DESCRIPTOR_LINE_MAX = 1024
};

enum pipe_result {
  PIPE_RESULT_OK,
  PIPE_RESULT_RAW_ERROR,
  PIPE_RESULT_PROTOCOL_ERROR
};

struct owned_fd {
  int number;
  int owned;
};

struct pipe_pair {
  struct owned_fd reader;
  struct owned_fd writer;
};

struct raw_error {
  const char *operation;
  char message[CAML_PLAN9_SYSCALL_ERRMAX];
  unsigned int terminator_index;
  int errstr_result;
};

struct cleanup_report {
  int count;
  struct raw_error errors[2];
};

struct descriptor_inventory {
  long observed_count;
  long normalized_count;
  int observer_fd;
};

static void stop_after_errstr_failure(void)
{
  fputs("raw_syscall_test: raw ERRSTR failed; raw syscalls stopped\n",
        stderr);
  exit(1);
}

static void stop_after_invalid_errstr(void)
{
  fputs("raw_syscall_test: raw ERRSTR returned an invalid bounded message; "
        "raw syscalls stopped\n", stderr);
  exit(1);
}

static void capture_raw_error(struct raw_error *error, const char *operation)
{
  unsigned int index;
  int result;

  error->operation = operation;
  for (index = 1; index < CAML_PLAN9_SYSCALL_ERRMAX; index++) {
    error->message[index] = (char) RAW_ERROR_SENTINEL;
  }
  error->message[0] = '\0';
  result = caml_plan9_sys_errstr(error->message,
                                 CAML_PLAN9_SYSCALL_ERRMAX);
  if (result < 0) stop_after_errstr_failure();

  error->errstr_result = result;
  if (error->message[0] == '\0') stop_after_invalid_errstr();
  for (index = 1; index < CAML_PLAN9_SYSCALL_ERRMAX; index++) {
    if (error->message[index] == '\0') break;
  }
  if (index == CAML_PLAN9_SYSCALL_ERRMAX) stop_after_invalid_errstr();
  error->terminator_index = index;
}

static int same_raw_error(const struct raw_error *left,
                          const struct raw_error *right)
{
  return left->operation == right->operation
      && left->terminator_index == right->terminator_index
      && left->errstr_result == right->errstr_result
      && memcmp(left->message, right->message,
                CAML_PLAN9_SYSCALL_ERRMAX) == 0;
}

static void report_raw_error(const char *test, const struct raw_error *error)
{
  fprintf(stderr,
          "raw_syscall_test: %s: raw %s failed: %s "
          "(ERRSTR=%d, NUL=%u)\n",
          test, error->operation, error->message, error->errstr_result,
          error->terminator_index);
}

static void initialize_pair(struct pipe_pair *pair)
{
  pair->reader.number = -1;
  pair->reader.owned = 0;
  pair->writer.number = -1;
  pair->writer.owned = 0;
}

static enum pipe_result create_pipe(struct pipe_pair *pair,
                                    struct raw_error *error)
{
  int descriptors[2];
  int result;

  initialize_pair(pair);
  descriptors[0] = -1;
  descriptors[1] = -1;
  result = caml_plan9_sys_pipe(descriptors);
  if (result < 0) {
    capture_raw_error(error, "PIPE");
    return PIPE_RESULT_RAW_ERROR;
  }

  if (descriptors[0] >= 0) {
    pair->reader.number = descriptors[0];
    pair->reader.owned = 1;
  }
  if (descriptors[1] >= 0 && descriptors[1] != descriptors[0]) {
    pair->writer.number = descriptors[1];
    pair->writer.owned = 1;
  }
  if (result != 0 || !pair->reader.owned || !pair->writer.owned) {
    return PIPE_RESULT_PROTOCOL_ERROR;
  }
  return PIPE_RESULT_OK;
}

static int close_owned(struct owned_fd *owned, const char *operation,
                       struct raw_error *error)
{
  int target;
  int result;

  if (!owned->owned) return 1;
  target = owned->number;

  /* Retirement is the terminal ownership commit and precedes raw close. */
  owned->owned = 0;
  owned->number = -1;
  result = caml_plan9_sys_close(target);
  if (result < 0) {
    capture_raw_error(error, operation);
    return 0;
  }
  return 1;
}

static void cleanup_pair(struct pipe_pair *pair,
                         struct cleanup_report *report)
{
  struct raw_error error;

  report->count = 0;
  if (!close_owned(&pair->reader, "CLOSE reader during cleanup", &error)) {
    report->errors[report->count++] = error;
  }
  if (!close_owned(&pair->writer, "CLOSE writer during cleanup", &error)) {
    report->errors[report->count++] = error;
  }
}

static void report_cleanup(const char *test,
                           const struct cleanup_report *report)
{
  int index;

  for (index = 0; index < report->count; index++) {
    report_raw_error(test, &report->errors[index]);
  }
}

static int fail_after_raw_error(const char *test, struct pipe_pair *pair,
                                const struct raw_error *error)
{
  struct raw_error preserved;
  struct cleanup_report cleanup;

  preserved = *error;
  cleanup_pair(pair, &cleanup);
  if (!same_raw_error(&preserved, error)) {
    fputs("raw_syscall_test: original raw error changed during cleanup\n",
          stderr);
  }
  report_raw_error(test, &preserved);
  report_cleanup(test, &cleanup);
  return 0;
}

static int fail_after_protocol_error(const char *test, const char *message,
                                     struct pipe_pair *pair)
{
  struct cleanup_report cleanup;

  cleanup_pair(pair, &cleanup);
  fprintf(stderr, "raw_syscall_test: %s: %s\n", test, message);
  report_cleanup(test, &cleanup);
  return 0;
}

static int write_once(int fd, const unsigned char *bytes, long length,
                      long *count, struct raw_error *error)
{
  *count = caml_plan9_sys_pwrite(fd, (void *) bytes, length,
                                 CAML_PLAN9_SYSCALL_STREAM_OFFSET);
  if (*count < 0) {
    capture_raw_error(error, "PWRITE");
    return 0;
  }
  return 1;
}

static int read_once(int fd, unsigned char *bytes, long length,
                     long *count, struct raw_error *error)
{
  *count = caml_plan9_sys_pread(fd, bytes, length,
                                CAML_PLAN9_SYSCALL_STREAM_OFFSET);
  if (*count < 0) {
    capture_raw_error(error, "PREAD");
    return 0;
  }
  return 1;
}

static int message_round_trip(const char *test,
                              const unsigned char *payload,
                              unsigned int payload_length,
                              unsigned int read_request)
{
  unsigned char received[64];
  struct pipe_pair pair;
  struct raw_error error;
  struct cleanup_report cleanup;
  enum pipe_result pipe_status;
  unsigned int index;
  long count;

  if (read_request > sizeof(received) || payload_length > read_request) {
    fprintf(stderr, "raw_syscall_test: %s: invalid test dimensions\n", test);
    return 0;
  }
  for (index = 0; index < sizeof(received); index++) received[index] = 0xcc;

  pipe_status = create_pipe(&pair, &error);
  if (pipe_status == PIPE_RESULT_RAW_ERROR) {
    report_raw_error(test, &error);
    return 0;
  }
  if (pipe_status == PIPE_RESULT_PROTOCOL_ERROR) {
    return fail_after_protocol_error(test,
                                     "PIPE returned an invalid success result",
                                     &pair);
  }
  if (!write_once(pair.writer.number, payload, (long) payload_length,
                  &count, &error)) {
    return fail_after_raw_error(test, &pair, &error);
  }
  if (count != (long) payload_length) {
    return fail_after_protocol_error(test,
                                     "PWRITE did not preserve the exact count",
                                     &pair);
  }
  if (!read_once(pair.reader.number, received, (long) read_request,
                 &count, &error)) {
    return fail_after_raw_error(test, &pair, &error);
  }
  if (count != (long) payload_length
      || memcmp(received, payload, payload_length) != 0) {
    return fail_after_protocol_error(test,
                                     "PREAD did not preserve the pipe message",
                                     &pair);
  }

  cleanup_pair(&pair, &cleanup);
  if (cleanup.count != 0) {
    report_cleanup(test, &cleanup);
    return 0;
  }
  return 1;
}

static int test_eof_after_buffered_data(void)
{
  static const unsigned char payload[] = { 'e', 'o', '\0', 'f' };
  unsigned char received[16];
  struct pipe_pair pair;
  struct raw_error error;
  struct cleanup_report cleanup;
  enum pipe_result pipe_status;
  long count;

  pipe_status = create_pipe(&pair, &error);
  if (pipe_status == PIPE_RESULT_RAW_ERROR) {
    report_raw_error("EOF", &error);
    return 0;
  }
  if (pipe_status == PIPE_RESULT_PROTOCOL_ERROR) {
    return fail_after_protocol_error("EOF",
                                     "PIPE returned an invalid success result",
                                     &pair);
  }
  if (!write_once(pair.writer.number, payload, sizeof(payload),
                  &count, &error)) {
    return fail_after_raw_error("EOF", &pair, &error);
  }
  if (count != sizeof(payload)) {
    return fail_after_protocol_error("EOF", "PWRITE returned a short count",
                                     &pair);
  }
  if (!close_owned(&pair.writer, "CLOSE designated EOF writer", &error)) {
    return fail_after_raw_error("EOF", &pair, &error);
  }
  if (!read_once(pair.reader.number, received, sizeof(received),
                 &count, &error)) {
    return fail_after_raw_error("EOF", &pair, &error);
  }
  if (count != sizeof(payload)
      || memcmp(received, payload, sizeof(payload)) != 0) {
    return fail_after_protocol_error("EOF",
                                     "buffered data was not preserved",
                                     &pair);
  }
  if (!read_once(pair.reader.number, received, 1, &count, &error)) {
    return fail_after_raw_error("EOF", &pair, &error);
  }
  if (count != 0) {
    return fail_after_protocol_error("EOF",
                                     "positive-length read did not observe EOF",
                                     &pair);
  }

  cleanup_pair(&pair, &cleanup);
  if (cleanup.count != 0) {
    report_cleanup("EOF", &cleanup);
    return 0;
  }
  return 1;
}

static int test_native_error_capture(void)
{
  unsigned char byte;
  struct pipe_pair pair;
  struct raw_error close_error;
  struct raw_error read_error;
  struct raw_error preserved;
  struct cleanup_report cleanup;
  enum pipe_result pipe_status;
  int saved_reader;
  long count;

  pipe_status = create_pipe(&pair, &read_error);
  if (pipe_status == PIPE_RESULT_RAW_ERROR) {
    report_raw_error("native error", &read_error);
    return 0;
  }
  if (pipe_status == PIPE_RESULT_PROTOCOL_ERROR) {
    return fail_after_protocol_error(
        "native error", "PIPE returned an invalid success result", &pair);
  }

  saved_reader = pair.reader.number;
  if (!close_owned(&pair.reader, "CLOSE deliberate probe target",
                   &close_error)) {
    /* The saved integer is never read after an uncertain close. */
    return fail_after_raw_error("native error close", &pair, &close_error);
  }

  count = caml_plan9_sys_pread(saved_reader, &byte, 1,
                               CAML_PLAN9_SYSCALL_STREAM_OFFSET);
  if (count >= 0) {
    return fail_after_protocol_error(
        "native error", "PREAD on the closed target did not fail", &pair);
  }
  capture_raw_error(&read_error, "PREAD deliberately closed target");
  preserved = read_error;
  cleanup_pair(&pair, &cleanup);
  if (!same_raw_error(&preserved, &read_error)) {
    fputs("raw_syscall_test: native read error changed during cleanup\n",
          stderr);
    report_cleanup("native error", &cleanup);
    return 0;
  }
  if (cleanup.count != 0) {
    report_raw_error("native error", &preserved);
    report_cleanup("native error", &cleanup);
    return 0;
  }

  printf("raw_syscall_test: native error captured: %s "
         "(ERRSTR=%d, sentinel NUL=%u)\n",
         preserved.message, preserved.errstr_result,
         preserved.terminator_index);
  return 1;
}

static int read_descriptor_inventory(struct descriptor_inventory *inventory)
{
  char path[64];
  char line[DESCRIPTOR_LINE_MAX];
  char *end;
  FILE *stream;
  long descriptor;
  long count;
  int observer_fd;
  int observer_matches;
  int saw_directory_header;
  int ok;

  if (sprintf(path, "/proc/%ld/fd", (long) getpid()) < 0) return 0;
  stream = fopen(path, "r");
  if (stream == NULL) return 0;
  observer_fd = fileno(stream);
  count = 0;
  observer_matches = 0;
  saw_directory_header = 0;
  ok = 1;
  while (fgets(line, sizeof(line), stream) != NULL) {
    if (strchr(line, '\n') == NULL) {
      ok = 0;
      break;
    }
    /* /proc/<pid>/fd starts with the process's current-directory path. */
    if (!saw_directory_header) {
      saw_directory_header = 1;
      continue;
    }
    descriptor = strtol(line, &end, 10);
    if (end == line) {
      ok = 0;
      break;
    }
    count++;
    if (descriptor == observer_fd) observer_matches++;
  }
  if (ferror(stream)) ok = 0;
  if (fclose(stream) != 0) ok = 0;
  if (!ok || !saw_directory_header || observer_matches != 1 || count < 1) {
    return 0;
  }

  inventory->observed_count = count;
  inventory->normalized_count = count - 1;
  inventory->observer_fd = observer_fd;
  return 1;
}

static int test_repeated_round_trip(void)
{
  static const unsigned char payload[] = {
    0x00, 0x11, 0x7f, 0x80, 0xfe, 0xff
  };
  struct descriptor_inventory before;
  struct descriptor_inventory after;
  int iteration;

  if (!read_descriptor_inventory(&before)) {
    fputs("raw_syscall_test: descriptor baseline observer failed\n", stderr);
    return 0;
  }
  for (iteration = 0; iteration < RAW_REPEAT_COUNT; iteration++) {
    if (!message_round_trip("repeated binary round trip", payload,
                            sizeof(payload), sizeof(payload))) {
      fprintf(stderr, "raw_syscall_test: repetition failed at %d of %d\n",
              iteration + 1, RAW_REPEAT_COUNT);
      return 0;
    }
  }
  if (!read_descriptor_inventory(&after)) {
    fputs("raw_syscall_test: descriptor final observer failed\n", stderr);
    return 0;
  }

  printf("raw_syscall_test: descriptor observer before=%ld normalized=%ld "
         "observer-fd=%d; after=%ld normalized=%ld observer-fd=%d\n",
         before.observed_count, before.normalized_count, before.observer_fd,
         after.observed_count, after.normalized_count, after.observer_fd);
  if (before.normalized_count != after.normalized_count) {
    fputs("raw_syscall_test: descriptor inventory grew across repetitions\n",
          stderr);
    return 0;
  }
  printf("raw_syscall_test: %d repeated round trips: passed; net growth=0\n",
         RAW_REPEAT_COUNT);
  return 1;
}

int main(void)
{
  static const unsigned char binary_payload[] = {
    'p', 'l', 'a', 'n', '\0', '9', 0xff
  };
  static const unsigned char short_payload[] = { 's', '\0', 'r' };

  if (!message_round_trip("binary round trip", binary_payload,
                          sizeof(binary_payload), sizeof(binary_payload))) {
    return 1;
  }
  puts("raw_syscall_test: binary round trip with embedded NUL: passed");

  if (!message_round_trip("positive short read", short_payload,
                          sizeof(short_payload), 16)) {
    return 1;
  }
  puts("raw_syscall_test: positive short read: wrote=3 requested=16 read=3");

  if (!test_eof_after_buffered_data()) return 1;
  puts("raw_syscall_test: buffered data then positive-length EOF: passed");

  if (!test_native_error_capture()) return 1;
  if (!test_repeated_round_trip()) return 1;

  puts("raw_syscall_test: passed");
  return 0;
}
