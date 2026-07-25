/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*                             Dharmatech                                 */
/*                                                                        */
/*   Copyright 2026 Dharmatech                                            */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the           */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

/*
 * This file is compiled only into Plan 9 runtimes.  The executable remains
 * APE-linked, but these operations use APE's direct Plan 9 syscall entry
 * points rather than its POSIX process and environment wrappers.
 */

#define CAML_INTERNALS

#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "plan9_process_frame.h"

#include "caml/alloc.h"
#include "caml/custom.h"
#include "caml/fail.h"
#include "caml/memory.h"
#include "caml/misc.h"
#include "caml/mlvalues.h"
#include "caml/signals.h"

enum {
  P9_RFENVG = 1 << 1,
  P9_RFFDG = 1 << 2,
  P9_RFPROC = 1 << 4,
  P9_RFMEM = 1 << 5,
  P9_RFNOWAIT = 1 << 6,
  P9_RFREND = 1 << 13,
  P9_RFNOMNT = 1 << 14,

  P9_SPAWN_FLAGS = P9_RFPROC | P9_RFFDG | P9_RFREND,

  P9_OWRITE = 1,
  P9_OTRUNC = 16,
  P9_OCEXEC = 32,

  P9_ERRMAX = 128,
  P9_ERROR_PAYLOAD_MAX = P9_FRAME_PAYLOAD_MAX,

  P9_NATIVE_INVALID = 0,
  P9_NATIVE_OTHER = 1,
  P9_NATIVE_INTERRUPTED = 2,
  P9_NATIVE_NO_CHILDREN = 3,
  P9_NATIVE_PROTOCOL = 4,

  P9_HANDSHAKE_UNKNOWN = 0,
  P9_HANDSHAKE_EXECUTED = 1,
  P9_HANDSHAKE_EXEC_FAILED = 2,
  P9_HANDSHAKE_INTERRUPTED = 3,
  P9_HANDSHAKE_PROTOCOL = 4,

  P9_WAIT_COMPLETION = 0,
  P9_WAIT_ERROR = 1,
  P9_WAIT_MALFORMED = 2
};

/*
 * These declarations mirror /sys/src/ape/lib/ap/plan9/sys9.h.  They are
 * private APE entries for the underlying Plan 9 operations.
 */
struct p9_waitmsg {
  int pid;
  unsigned long time[3];
  char *msg;
};

extern int _CLOSE(int);
extern int _CREATE(char *, int, unsigned long);
extern int _DUP(int, int);
extern int _ERRSTR(char *, unsigned int);
extern int _EXEC(char *, char **);
extern void _EXITS(char *);
extern int _OPEN(const char *, int);
extern int _PIPE(int *);
extern long _READ(int, void *, long);
extern int _RFORK(int);
extern struct p9_waitmsg *_WAIT(void);
extern long _WRITE(int, const void *, long);

struct p9_failure {
  int kind;
  char message[P9_ERRMAX];
};

struct p9_pending {
  int64_t process_id;
  int pid;
  int handshake;
  struct p9_failure detail;
  int queue_lost;
  struct p9_failure loss;
  struct p9_pending *next;
};

struct p9_inputs {
  char *program;
  char **argv;
  size_t argc;
  char *stdout_path;
};

struct p9_wait_event {
  int retained;
  int64_t sequence;
  int kind;
  int pid;
  uint32_t time[3];
  struct p9_failure detail;
};

static struct p9_pending *p9_pending_head;
static int64_t p9_next_process_id = 1;
static struct p9_wait_event p9_wait_event;
static int64_t p9_next_wait_sequence = 1;

static int p9_identity_exhausted(int64_t identity)
{
  uint64_t largest;

  largest = ((uint64_t) -1) >> 1;
  return identity <= 0 || (uint64_t) identity == largest;
}

static void p9_set_failure(struct p9_failure *failure, int kind,
                           const char *message)
{
  size_t index;

  failure->kind = kind;
  index = 0;
  while (index + 1 < sizeof(failure->message) && message[index] != 0) {
    failure->message[index] = message[index];
    index++;
  }
  failure->message[index] = 0;
}

static int p9_classify_error(const char *message)
{
  if (strcmp(message, "interrupted") == 0) return P9_NATIVE_INTERRUPTED;
  if (strcmp(message, "no living children") == 0) {
    return P9_NATIVE_NO_CHILDREN;
  }
  return P9_NATIVE_OTHER;
}

static void p9_capture_error(struct p9_failure *failure)
{
  char message[P9_ERRMAX];

  message[0] = 0;
  message[P9_ERRMAX - 1] = 0;
  (void) _ERRSTR(message, sizeof(message));
  message[P9_ERRMAX - 1] = 0;
  p9_set_failure(failure, p9_classify_error(message), message);
}

static int p9_is_string(value input)
{
  return Is_block(input) && Tag_val(input) == String_tag;
}

static int p9_is_int64(value input)
{
  return Is_block(input)
    && Tag_val(input) == Custom_tag
    && Custom_ops_val(input) == &caml_int64_ops;
}

static int p9_string_has_nul(value input)
{
  mlsize_t length;

  length = caml_string_length(input);
  return memchr(String_val(input), 0, length) != NULL;
}

static int p9_validate_string(value input, int require_nonempty,
                              const char *empty_message,
                              const char *nul_message,
                              struct p9_failure *failure)
{
  mlsize_t length;

  if (!p9_is_string(input)) {
    p9_set_failure(failure, P9_NATIVE_INVALID,
                   "primitive argument is not an OCaml string");
    return 0;
  }
  length = caml_string_length(input);
  if (require_nonempty && length == 0) {
    p9_set_failure(failure, P9_NATIVE_INVALID, empty_message);
    return 0;
  }
  if (p9_string_has_nul(input)) {
    p9_set_failure(failure, P9_NATIVE_INVALID, nul_message);
    return 0;
  }
  if ((uintnat) length > (uintnat) INT_MAX) {
    p9_set_failure(failure, P9_NATIVE_INVALID,
                   "primitive string exceeds the native length bound");
    return 0;
  }
  return 1;
}

static char *p9_copy_string(value input)
{
  mlsize_t length;
  char *copy;

  length = caml_string_length(input);
  copy = caml_stat_alloc_noexc((asize_t) length + 1);
  if (copy == NULL) return NULL;
  memcpy(copy, String_val(input), length);
  copy[length] = 0;
  return copy;
}

static void p9_free_inputs(struct p9_inputs *inputs)
{
  size_t index;

  if (inputs->argv != NULL) {
    for (index = 0; index < inputs->argc; index++) {
      if (inputs->argv[index] != NULL) caml_stat_free(inputs->argv[index]);
    }
    caml_stat_free(inputs->argv);
  }
  if (inputs->program != NULL) caml_stat_free(inputs->program);
  if (inputs->stdout_path != NULL) caml_stat_free(inputs->stdout_path);
  inputs->program = NULL;
  inputs->argv = NULL;
  inputs->argc = 0;
  inputs->stdout_path = NULL;
}

static int p9_copy_inputs(value program, value argv, int stdout_kind,
                          value stdout_path, struct p9_inputs *inputs,
                          struct p9_failure *failure)
{
  mlsize_t argc;
  mlsize_t index;
  uintnat aggregate;

  inputs->program = NULL;
  inputs->argv = NULL;
  inputs->argc = 0;
  inputs->stdout_path = NULL;

  if (!p9_validate_string(program, 1,
          "program path is empty",
          "program path contains NUL", failure)) {
    return 0;
  }
  if (!Is_block(argv) || Tag_val(argv) != 0) {
    p9_set_failure(failure, P9_NATIVE_INVALID,
                   "argument vector is not an OCaml array");
    return 0;
  }
  argc = Wosize_val(argv);
  if (argc == 0) {
    p9_set_failure(failure, P9_NATIVE_INVALID,
                   "argument vector is empty");
    return 0;
  }
  if ((uintnat) argc > ((uintnat) INT_MAX / sizeof(char *)) - 1) {
    p9_set_failure(failure, P9_NATIVE_INVALID,
                   "argument vector exceeds the native count bound");
    return 0;
  }
  aggregate = 0;
  for (index = 0; index < argc; index++) {
    value argument;
    mlsize_t length;

    argument = Field(argv, index);
    if (!p9_validate_string(argument, 0, "",
            "argument vector element contains NUL", failure)) {
      return 0;
    }
    length = caml_string_length(argument);
    if ((uintnat) length + 1 > (uintnat) INT_MAX - aggregate) {
      p9_set_failure(failure, P9_NATIVE_INVALID,
                     "argument vector exceeds the native aggregate bound");
      return 0;
    }
    aggregate += (uintnat) length + 1;
  }
  if (stdout_kind != -1 && stdout_kind != 0 && stdout_kind != 1) {
    p9_set_failure(failure, P9_NATIVE_INVALID,
                   "unknown stdout policy");
    return 0;
  }
  if (stdout_kind >= 0 && !p9_is_string(stdout_path)) {
    p9_set_failure(failure, P9_NATIVE_INVALID,
                   "stdout path is not an OCaml string");
    return 0;
  }
  if (stdout_kind == 0 && caml_string_length(stdout_path) != 0) {
    p9_set_failure(failure, P9_NATIVE_INVALID,
                   "inherited stdout has a path");
    return 0;
  }
  if (stdout_kind == 1
      && !p9_validate_string(stdout_path, 1,
           "stdout path is empty",
           "stdout path contains NUL", failure)) {
    return 0;
  }

  inputs->program = p9_copy_string(program);
  if (inputs->program == NULL) goto out_of_memory;
  inputs->argv =
    caml_stat_calloc_noexc((asize_t) argc + 1, sizeof(char *));
  if (inputs->argv == NULL) goto out_of_memory;
  inputs->argc = argc;
  for (index = 0; index < argc; index++) {
    inputs->argv[index] = p9_copy_string(Field(argv, index));
    if (inputs->argv[index] == NULL) goto out_of_memory;
  }
  inputs->argv[argc] = NULL;
  if (stdout_kind == 1) {
    inputs->stdout_path = p9_copy_string(stdout_path);
    if (inputs->stdout_path == NULL) goto out_of_memory;
  }
  return 1;

out_of_memory:
  p9_free_inputs(inputs);
  p9_set_failure(failure, P9_NATIVE_OTHER,
                 "out of memory while copying native process inputs");
  return 0;
}

static value p9_alloc_failure(const struct p9_failure *failure)
{
  CAMLparam0();
  CAMLlocal2(result, message);

  message = caml_copy_string(failure->message);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, Val_int(failure->kind));
  Store_field(result, 1, message);
  CAMLreturn(result);
}

static value p9_alloc_result_error(const struct p9_failure *failure)
{
  CAMLparam0();
  CAMLlocal2(result, error);

  error = p9_alloc_failure(failure);
  result = caml_alloc_small(1, 1);
  Store_field(result, 0, error);
  CAMLreturn(result);
}

static value p9_alloc_result_unit(void)
{
  CAMLparam0();
  CAMLlocal1(result);

  result = caml_alloc_small(1, 0);
  Store_field(result, 0, Val_unit);
  CAMLreturn(result);
}

static value p9_alloc_pending(const struct p9_pending *pending)
{
  CAMLparam0();
  CAMLlocal5(result, process_id, detail, loss, loss_detail);

  process_id = caml_copy_int64(pending->process_id);
  detail = p9_alloc_failure(&pending->detail);
  if (pending->queue_lost) {
    loss_detail = p9_alloc_failure(&pending->loss);
    loss = caml_alloc_small(1, 0);
    Store_field(loss, 0, loss_detail);
  } else {
    loss = Val_none;
  }
  result = caml_alloc_tuple(5);
  Store_field(result, 0, process_id);
  Store_field(result, 1, Val_int(pending->pid));
  Store_field(result, 2, Val_int(pending->handshake));
  Store_field(result, 3, detail);
  Store_field(result, 4, loss);
  CAMLreturn(result);
}

static value p9_alloc_spawn_success(const struct p9_pending *pending)
{
  CAMLparam0();
  CAMLlocal2(result, registered);

  registered = p9_alloc_pending(pending);
  result = caml_alloc_small(1, 0);
  Store_field(result, 0, registered);
  CAMLreturn(result);
}

static void p9_close_if_open(int fd)
{
  if (fd >= 0) (void) _CLOSE(fd);
}

static int p9_prepare_descriptors(int pipefd[2], int *stdout_fd,
                                  int *error_write,
                                  struct p9_failure *failure)
{
  int descriptors[3];
  int descriptor_count;
  int fillers[3];
  int filler_count;
  int index;
  int duplicate;
  int path_length;
  char path[32];

  descriptors[0] = pipefd[0];
  descriptors[1] = pipefd[1];
  descriptors[2] = *stdout_fd;
  descriptor_count = *stdout_fd >= 0 ? 3 : 2;
  filler_count = 0;

  for (index = 0; index < descriptor_count; index++) {
    if (descriptors[index] <= 2) {
      for (;;) {
        duplicate = _DUP(descriptors[index], -1);
        if (duplicate < 0) {
          p9_capture_error(failure);
          goto failed;
        }
        if (duplicate <= 2) {
          if (filler_count == 3) {
            (void) _CLOSE(duplicate);
            p9_set_failure(failure, P9_NATIVE_PROTOCOL,
                           "descriptor-hole tracking overflowed");
            goto failed;
          }
          fillers[filler_count++] = duplicate;
        } else {
          (void) _CLOSE(descriptors[index]);
          descriptors[index] = duplicate;
          break;
        }
      }
    }
  }

  for (;;) {
    duplicate = _DUP(descriptors[1], -1);
    if (duplicate < 0) {
      p9_capture_error(failure);
      goto failed;
    }
    if (duplicate <= 2) {
      if (filler_count == 3) {
        (void) _CLOSE(duplicate);
        p9_set_failure(failure, P9_NATIVE_PROTOCOL,
                       "descriptor-hole tracking overflowed");
        goto failed;
      }
      fillers[filler_count++] = duplicate;
    } else {
      (void) _CLOSE(duplicate);
      break;
    }
  }

  path_length = snprintf(path, sizeof(path), "#d/%d", descriptors[1]);
  if (path_length < 0 || (size_t) path_length >= sizeof(path)) {
    p9_set_failure(failure, P9_NATIVE_PROTOCOL,
                   "descriptor path exceeded bounded storage");
    goto failed;
  }
  duplicate = _OPEN(path, P9_OWRITE | P9_OCEXEC);
  if (duplicate < 0) {
    p9_capture_error(failure);
    goto failed;
  }
  if (duplicate <= 2) {
    (void) _CLOSE(duplicate);
    p9_set_failure(failure, P9_NATIVE_PROTOCOL,
                   "close-on-exec pipe descriptor reused standard I/O");
    goto failed;
  }
  (void) _CLOSE(descriptors[1]);
  descriptors[1] = duplicate;

  for (index = 0; index < filler_count; index++) {
    (void) _CLOSE(fillers[index]);
  }
  pipefd[0] = descriptors[0];
  pipefd[1] = -1;
  *error_write = descriptors[1];
  if (descriptor_count == 3) *stdout_fd = descriptors[2];
  return 1;

failed:
  for (index = 0; index < filler_count; index++) {
    (void) _CLOSE(fillers[index]);
  }
  pipefd[0] = descriptors[0];
  pipefd[1] = descriptors[1];
  if (descriptor_count == 3) *stdout_fd = descriptors[2];
  return 0;
}

static long p9_write_frame_bytes(void *context,
                                 const unsigned char *buffer, size_t length)
{
  int fd;

  fd = *(int *) context;
  if (length > (size_t) LONG_MAX) length = (size_t) LONG_MAX;
  return _WRITE(fd, buffer, (long) length);
}

static void p9_child_failure(int error_fd, struct p9_failure *failure)
{
  size_t length;

  if (failure->message[0] == 0) {
    p9_set_failure(failure, P9_NATIVE_OTHER,
                   "native exec failed without an error string");
  }
  length = strlen(failure->message);
  if (length > P9_ERROR_PAYLOAD_MAX) length = P9_ERROR_PAYLOAD_MAX;
  (void) p9_write_exec_frame(
    p9_write_frame_bytes, &error_fd,
    (const unsigned char *) failure->message, length);
  for (;;) {
    _EXITS("Plan9.Process child exec failure");
  }
}

struct p9_native_frame_reader {
  int fd;
  struct p9_failure failure;
};

static long p9_read_frame_bytes(void *context, unsigned char *buffer,
                                size_t length)
{
  struct p9_native_frame_reader *reader;
  long count;

  reader = context;
  if (length > (size_t) LONG_MAX) length = (size_t) LONG_MAX;
  count = _READ(reader->fd, buffer, (long) length);
  if (count < 0) p9_capture_error(&reader->failure);
  return count;
}

static void p9_read_handshake(int fd, struct p9_pending *pending)
{
  struct p9_native_frame_reader reader;
  struct p9_frame_result frame;

  reader.fd = fd;
  p9_set_failure(&reader.failure, P9_NATIVE_PROTOCOL,
                 "exec handshake read failed without an error string");
  p9_read_exec_frame(p9_read_frame_bytes, &reader, &frame);

  switch (frame.outcome) {
  case P9_FRAME_EXECUTED:
    pending->handshake = P9_HANDSHAKE_EXECUTED;
    p9_set_failure(&pending->detail, P9_NATIVE_OTHER, "");
    return;
  case P9_FRAME_EXEC_FAILED:
    pending->handshake = P9_HANDSHAKE_EXEC_FAILED;
    p9_set_failure(&pending->detail,
                   p9_classify_error((char *) frame.payload),
                   (char *) frame.payload);
    return;
  case P9_FRAME_IO_ERROR:
    if (reader.failure.kind == P9_NATIVE_INTERRUPTED) {
      pending->handshake = P9_HANDSHAKE_INTERRUPTED;
    } else {
      pending->handshake = P9_HANDSHAKE_PROTOCOL;
    }
    pending->detail = reader.failure;
    return;
  case P9_FRAME_PROTOCOL_ERROR:
    pending->handshake = P9_HANDSHAKE_PROTOCOL;
    p9_set_failure(&pending->detail, P9_NATIVE_PROTOCOL,
                   frame.protocol_message);
    return;
  }

  pending->handshake = P9_HANDSHAKE_PROTOCOL;
  p9_set_failure(&pending->detail, P9_NATIVE_PROTOCOL,
                 "exec handshake decoder returned an unknown outcome");
}

static int p9_reserve_pending(struct p9_pending **result,
                              struct p9_failure *failure)
{
  struct p9_pending *pending;

  if (p9_identity_exhausted(p9_next_process_id)) {
    p9_set_failure(failure, P9_NATIVE_OTHER,
                   "managed process identity space is exhausted");
    return 0;
  }
  pending = caml_stat_calloc_noexc(1, sizeof(struct p9_pending));
  if (pending == NULL) {
    p9_set_failure(failure, P9_NATIVE_OTHER,
                   "out of memory reserving native pending-child ownership");
    return 0;
  }
  pending->process_id = p9_next_process_id++;
  pending->pid = 0;
  pending->handshake = P9_HANDSHAKE_UNKNOWN;
  p9_set_failure(&pending->detail, P9_NATIVE_PROTOCOL,
                 "exec handshake has not completed");
  pending->queue_lost = 0;
  pending->next = NULL;
  *result = pending;
  return 1;
}

static void p9_publish_pending(struct p9_pending *pending, int pid)
{
  pending->pid = pid;
  pending->next = p9_pending_head;
  p9_pending_head = pending;
}

static void p9_mark_pending_lost(const struct p9_failure *failure)
{
  struct p9_pending *pending;

  for (pending = p9_pending_head; pending != NULL; pending = pending->next) {
    pending->queue_lost = 1;
    pending->loss = *failure;
  }
}

CAMLprim value caml_plan9_copy_environment(value unit)
{
  CAMLparam1(unit);
  struct p9_failure failure;
  int result;

  if (unit != Val_unit) {
    p9_set_failure(&failure, P9_NATIVE_INVALID,
                   "copy_environment expects unit");
    CAMLreturn(p9_alloc_result_error(&failure));
  }
  result = _RFORK(P9_RFENVG);
  if (result < 0) {
    p9_capture_error(&failure);
    CAMLreturn(p9_alloc_result_error(&failure));
  }
  if (result != 0) {
    p9_set_failure(&failure, P9_NATIVE_PROTOCOL,
                   "current-process RFENVG unexpectedly created a child");
    CAMLreturn(p9_alloc_result_error(&failure));
  }
  CAMLreturn(p9_alloc_result_unit());
}

CAMLprim value caml_plan9_exec(value program, value argv)
{
  CAMLparam2(program, argv);
  struct p9_inputs inputs;
  struct p9_failure failure;
  int result;

  if (!p9_copy_inputs(program, argv, -1, Val_unit,
                      &inputs, &failure)) {
    CAMLreturn(p9_alloc_result_error(&failure));
  }
  caml_enter_blocking_section();
  result = _EXEC(inputs.program, inputs.argv);
  if (result < 0) {
    p9_capture_error(&failure);
  } else {
    p9_set_failure(&failure, P9_NATIVE_PROTOCOL,
                   "native exec returned without replacing the process");
  }
  p9_free_inputs(&inputs);
  caml_leave_blocking_section();
  CAMLreturn(p9_alloc_result_error(&failure));
}

CAMLprim value caml_plan9_process_spawn(value program, value argv,
                                        value stdout_kind,
                                        value stdout_path, value flags)
{
  CAMLparam5(program, argv, stdout_kind, stdout_path, flags);
  struct p9_inputs inputs;
  struct p9_failure failure;
  struct p9_pending *pending;
  int pipefd[2];
  int error_write;
  int output_fd;
  int pid;
  int policy;
  int output_policy;
  intnat policy_value;
  intnat output_policy_value;

  pipefd[0] = -1;
  pipefd[1] = -1;
  error_write = -1;
  output_fd = -1;
  pending = NULL;

  if (!Is_long(stdout_kind) || !Is_long(flags)) {
    p9_set_failure(&failure, P9_NATIVE_INVALID,
                   "spawn policy values are not OCaml integers");
    CAMLreturn(p9_alloc_result_error(&failure));
  }
  output_policy_value = Long_val(stdout_kind);
  policy_value = Long_val(flags);
  if (output_policy_value != 0 && output_policy_value != 1) {
    p9_set_failure(&failure, P9_NATIVE_INVALID,
                   "unknown stdout policy");
    CAMLreturn(p9_alloc_result_error(&failure));
  }
  if (policy_value != P9_SPAWN_FLAGS
      || policy_value < INT_MIN || policy_value > INT_MAX
      || output_policy_value < INT_MIN || output_policy_value > INT_MAX) {
    p9_set_failure(&failure, P9_NATIVE_INVALID,
                   "spawn rejected an unknown or forbidden rfork policy");
    CAMLreturn(p9_alloc_result_error(&failure));
  }
  output_policy = (int) output_policy_value;
  policy = (int) policy_value;
  if (policy != P9_SPAWN_FLAGS
      || (policy & (P9_RFMEM | P9_RFNOWAIT | P9_RFNOMNT)) != 0) {
    p9_set_failure(&failure, P9_NATIVE_INVALID,
                   "spawn rejected an unknown or forbidden rfork policy");
    CAMLreturn(p9_alloc_result_error(&failure));
  }
  if (!p9_copy_inputs(program, argv, output_policy, stdout_path,
                      &inputs, &failure)) {
    CAMLreturn(p9_alloc_result_error(&failure));
  }
  if (!p9_reserve_pending(&pending, &failure)) {
    p9_free_inputs(&inputs);
    CAMLreturn(p9_alloc_result_error(&failure));
  }
  if (_PIPE(pipefd) < 0) {
    p9_capture_error(&failure);
    goto no_child;
  }
  if (output_policy == 1) {
    output_fd = _CREATE(inputs.stdout_path, P9_OWRITE | P9_OTRUNC, 0666);
    if (output_fd < 0) {
      p9_capture_error(&failure);
      goto no_child;
    }
  }
  if (!p9_prepare_descriptors(pipefd, &output_fd, &error_write, &failure)) {
    goto no_child;
  }

  pid = _RFORK(P9_SPAWN_FLAGS);
  if (pid < 0) {
    p9_capture_error(&failure);
    goto no_child;
  }
  if (pid == 0) {
    struct p9_failure child_failure;

    (void) _CLOSE(pipefd[0]);
    if (output_fd >= 0) {
      if (_DUP(output_fd, 1) < 0) {
        p9_capture_error(&child_failure);
        p9_child_failure(error_write, &child_failure);
      }
      (void) _CLOSE(output_fd);
    }
    (void) _EXEC(inputs.program, inputs.argv);
    p9_capture_error(&child_failure);
    p9_child_failure(error_write, &child_failure);
  }

  /*
   * The following publication is deliberately the first parent-side action
   * after a positive rfork result.  It performs no allocation.
   */
  p9_publish_pending(pending, pid);
  (void) _CLOSE(error_write);
  error_write = -1;
  p9_close_if_open(output_fd);
  output_fd = -1;

  caml_enter_blocking_section();
  p9_read_handshake(pipefd[0], pending);
  (void) _CLOSE(pipefd[0]);
  pipefd[0] = -1;
  p9_free_inputs(&inputs);
  caml_leave_blocking_section();
  CAMLreturn(p9_alloc_spawn_success(pending));

no_child:
  p9_close_if_open(pipefd[0]);
  p9_close_if_open(pipefd[1]);
  if (error_write >= 0 && error_write != pipefd[1]) {
    p9_close_if_open(error_write);
  }
  p9_close_if_open(output_fd);
  p9_free_inputs(&inputs);
  if (pending != NULL) caml_stat_free(pending);
  CAMLreturn(p9_alloc_result_error(&failure));
}

CAMLprim value caml_plan9_process_pending(value unit)
{
  CAMLparam1(unit);
  CAMLlocal2(result, entry);
  struct p9_pending *pending;
  mlsize_t count;
  mlsize_t index;

  if (unit != Val_unit) {
    caml_invalid_argument("caml_plan9_process_pending: expected unit");
  }
  count = 0;
  for (pending = p9_pending_head; pending != NULL; pending = pending->next) {
    if (count == Max_wosize) {
      caml_failwith("Plan 9 pending-child registry exceeds OCaml array size");
    }
    count++;
  }
  result = caml_alloc(count, 0);
  index = 0;
  for (pending = p9_pending_head; pending != NULL; pending = pending->next) {
    entry = p9_alloc_pending(pending);
    Store_field(result, index, entry);
    index++;
  }
  CAMLreturn(result);
}

CAMLprim value caml_plan9_process_acknowledge(value process_id)
{
  CAMLparam1(process_id);
  struct p9_pending **link;
  struct p9_pending *pending;
  int64_t wanted;

  if (!p9_is_int64(process_id)) CAMLreturn(Val_false);
  wanted = Int64_val(process_id);
  link = &p9_pending_head;
  while (*link != NULL) {
    pending = *link;
    if (pending->process_id == wanted) {
      *link = pending->next;
      caml_stat_free(pending);
      CAMLreturn(Val_true);
    }
    link = &pending->next;
  }
  CAMLreturn(Val_false);
}

static int p9_waitmsg_layout_is_supported(void)
{
  return sizeof(int) == 4
    && sizeof(unsigned long) == 4
    && sizeof(void *) == 8
    && sizeof(struct p9_waitmsg) == 24
    && offsetof(struct p9_waitmsg, pid) == 0
    && offsetof(struct p9_waitmsg, time) == 4
    && offsetof(struct p9_waitmsg, msg) == 16;
}

static size_t p9_bounded_length(const char *message, size_t bound)
{
  size_t length;

  length = 0;
  while (length < bound && message[length] != 0) length++;
  return length;
}

static void p9_retain_wait_event(void)
{
  struct p9_waitmsg *waitmsg;
  struct p9_failure failure;
  size_t message_length;

  if (p9_wait_event.retained) return;
  if (p9_identity_exhausted(p9_next_wait_sequence)) {
    p9_wait_event.retained = 1;
    p9_wait_event.sequence = p9_next_wait_sequence;
    p9_wait_event.kind = P9_WAIT_MALFORMED;
    p9_wait_event.pid = 0;
    p9_wait_event.time[0] = 0;
    p9_wait_event.time[1] = 0;
    p9_wait_event.time[2] = 0;
    p9_set_failure(&p9_wait_event.detail, P9_NATIVE_PROTOCOL,
                   "native wait-event identity space is exhausted");
    return;
  }

  p9_wait_event.sequence = p9_next_wait_sequence++;
  p9_wait_event.pid = 0;
  p9_wait_event.time[0] = 0;
  p9_wait_event.time[1] = 0;
  p9_wait_event.time[2] = 0;

  if (!p9_waitmsg_layout_is_supported()) {
    p9_wait_event.kind = P9_WAIT_MALFORMED;
    p9_set_failure(&p9_wait_event.detail, P9_NATIVE_PROTOCOL,
                   "installed Waitmsg layout differs from the qualified ABI");
    p9_wait_event.retained = 1;
    return;
  }

  waitmsg = _WAIT();
  if (waitmsg == NULL) {
    p9_capture_error(&failure);
    p9_wait_event.kind = P9_WAIT_ERROR;
    p9_wait_event.detail = failure;
    if (failure.kind == P9_NATIVE_NO_CHILDREN) {
      p9_mark_pending_lost(&failure);
    }
    p9_wait_event.retained = 1;
    return;
  }

  p9_wait_event.pid = waitmsg->pid;
  p9_wait_event.time[0] = (uint32_t) waitmsg->time[0];
  p9_wait_event.time[1] = (uint32_t) waitmsg->time[1];
  p9_wait_event.time[2] = (uint32_t) waitmsg->time[2];
  if (waitmsg->msg == NULL) {
    p9_wait_event.kind = P9_WAIT_MALFORMED;
    p9_set_failure(&p9_wait_event.detail, P9_NATIVE_PROTOCOL,
                   "native Waitmsg has a null message pointer");
  } else {
    message_length = p9_bounded_length(waitmsg->msg, P9_ERRMAX);
    if (message_length > P9_ERROR_PAYLOAD_MAX) {
      p9_wait_event.kind = P9_WAIT_MALFORMED;
      p9_set_failure(&p9_wait_event.detail, P9_NATIVE_PROTOCOL,
                     "native Waitmsg exceeds the measured message bound");
    } else {
      p9_wait_event.kind = P9_WAIT_COMPLETION;
      p9_set_failure(&p9_wait_event.detail, P9_NATIVE_OTHER, waitmsg->msg);
    }
  }
  free(waitmsg);
  p9_wait_event.retained = 1;
}

static value p9_alloc_wait_event(void)
{
  CAMLparam0();
  CAMLlocal5(result, sequence, user_time, system_time, elapsed_time);
  CAMLlocal1(detail);

  sequence = caml_copy_int64(p9_wait_event.sequence);
  user_time = caml_copy_int64((int64_t) (uint64_t) p9_wait_event.time[0]);
  system_time = caml_copy_int64((int64_t) (uint64_t) p9_wait_event.time[1]);
  elapsed_time = caml_copy_int64((int64_t) (uint64_t) p9_wait_event.time[2]);
  detail = p9_alloc_failure(&p9_wait_event.detail);
  result = caml_alloc_tuple(7);
  Store_field(result, 0, sequence);
  Store_field(result, 1, Val_int(p9_wait_event.kind));
  Store_field(result, 2, Val_int(p9_wait_event.pid));
  Store_field(result, 3, user_time);
  Store_field(result, 4, system_time);
  Store_field(result, 5, elapsed_time);
  Store_field(result, 6, detail);
  CAMLreturn(result);
}

CAMLprim value caml_plan9_process_await(value unit)
{
  CAMLparam1(unit);

  if (unit != Val_unit) {
    caml_invalid_argument("caml_plan9_process_await: expected unit");
  }
  if (!p9_wait_event.retained) {
    caml_enter_blocking_section();
    p9_retain_wait_event();
    caml_leave_blocking_section();
  }
  CAMLreturn(p9_alloc_wait_event());
}

CAMLprim value caml_plan9_process_acknowledge_wait(value sequence)
{
  CAMLparam1(sequence);
  int64_t wanted;

  if (!p9_is_int64(sequence)) CAMLreturn(Val_false);
  wanted = Int64_val(sequence);
  if (!p9_wait_event.retained || p9_wait_event.sequence != wanted) {
    CAMLreturn(Val_false);
  }
  memset(&p9_wait_event, 0, sizeof(p9_wait_event));
  CAMLreturn(Val_true);
}
