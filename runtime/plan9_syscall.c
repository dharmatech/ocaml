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

/* Private, validated OCaml integration for the raw amd64 Plan 9 syscall
   entries.  This file is selected only for x86_64 Plan 9 bytecode
   runtimes. */

#define CAML_INTERNALS

#include "plan9_syscall.h"

#include "caml/alloc.h"
#include "caml/custom.h"
#include "caml/memory.h"
#include "caml/mlvalues.h"
#include "caml/signals.h"

enum {
  P9S_NATIVE_INVALID = 0,
  P9S_NATIVE_OTHER = 1,
  P9S_NATIVE_INTERRUPTED = 2,
  P9S_NATIVE_NO_CHILDREN = 3,
  P9S_NATIVE_PROTOCOL = 4,

  P9S_CAPABILITY_UNPUBLISHED = 0,
  P9S_CAPABILITY_OPEN = 1,
  P9S_CAPABILITY_CLOSED = 2,

  P9S_ACCEPT_OPEN = 1 << P9S_CAPABILITY_OPEN,
  P9S_ACCEPT_CLOSED = 1 << P9S_CAPABILITY_CLOSED,

  P9S_STAGING_CAPACITY = 4096
};

struct p9s_capability {
  int descriptor;
  int state;
};

typedef char p9s_capability_payload_is_eight_bytes[
  sizeof(struct p9s_capability) == 8 ? 1 : -1];

struct p9s_failure {
  int kind;
  char message[CAML_PLAN9_SYSCALL_ERRMAX];
};

#define P9S_CAPABILITY_WOSIZE \
  (1 + ((sizeof(struct p9s_capability) + sizeof(value) - 1) / sizeof(value)))

static struct custom_operations p9s_capability_operations = {
  "_ocaml_plan9_syscall_capability_v1",
  custom_finalize_default,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

static void p9s_initialize_failure(struct p9s_failure *failure)
{
  unsigned int index;

  failure->kind = P9S_NATIVE_PROTOCOL;
  for (index = 0; index < CAML_PLAN9_SYSCALL_ERRMAX; index++) {
    failure->message[index] = 0;
  }
}

static void p9s_set_failure(struct p9s_failure *failure, int kind,
                            const char *message)
{
  unsigned int index;

  p9s_initialize_failure(failure);
  failure->kind = kind;
  index = 0;
  while (index + 1 < CAML_PLAN9_SYSCALL_ERRMAX && message[index] != 0) {
    failure->message[index] = message[index];
    index++;
  }
  failure->message[index] = 0;
}

static int p9s_message_is(const char *message, const char *expected)
{
  unsigned int index;

  index = 0;
  while (message[index] != 0 && expected[index] != 0) {
    if (message[index] != expected[index]) return 0;
    index++;
  }
  return message[index] == expected[index];
}

/* The caller zeroes the complete buffer before the primary raw operation.
   On a negative result this call must be the next native operation. */
static void p9s_capture_failure(struct p9s_failure *failure)
{
  unsigned int index;
  int result;

  result = caml_plan9_sys_errstr(failure->message,
                                 CAML_PLAN9_SYSCALL_ERRMAX);
  index = 0;
  while (index < CAML_PLAN9_SYSCALL_ERRMAX
         && failure->message[index] != 0) {
    index++;
  }
  failure->message[CAML_PLAN9_SYSCALL_ERRMAX - 1] = 0;
  if (result != 0 || index == 0 || index == CAML_PLAN9_SYSCALL_ERRMAX) {
    p9s_set_failure(failure, P9S_NATIVE_PROTOCOL,
                    "raw ERRSTR returned an unusable result");
  } else if (p9s_message_is(failure->message, "interrupted")) {
    failure->kind = P9S_NATIVE_INTERRUPTED;
  } else {
    failure->kind = P9S_NATIVE_OTHER;
  }
}

static value p9s_alloc_failure(const struct p9s_failure *failure)
{
  CAMLparam0();
  CAMLlocal2(result, message);

  message = caml_copy_string(failure->message);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, Val_int(failure->kind));
  Store_field(result, 1, message);
  CAMLreturn(result);
}

static value p9s_alloc_error(const struct p9s_failure *failure)
{
  CAMLparam0();
  CAMLlocal2(result, detail);

  detail = p9s_alloc_failure(failure);
  result = caml_alloc_small(1, 1);
  Store_field(result, 0, detail);
  CAMLreturn(result);
}

static value p9s_alloc_unit_ok(void)
{
  CAMLparam0();
  CAMLlocal1(result);

  result = caml_alloc_small(1, 0);
  Store_field(result, 0, Val_unit);
  CAMLreturn(result);
}

static value p9s_alloc_capability(void)
{
  CAMLparam0();
  CAMLlocal1(result);
  struct p9s_capability *payload;

  result = caml_alloc_custom(&p9s_capability_operations,
                             sizeof(struct p9s_capability), 0, 1);
  payload = (struct p9s_capability *) Data_custom_val(result);
  payload->descriptor = -1;
  payload->state = P9S_CAPABILITY_UNPUBLISHED;
  CAMLreturn(result);
}

static int p9s_validate_capability(value input, int accepted_states,
                                   int *state,
                                   struct p9s_failure *failure)
{
  struct p9s_capability *payload;
  int accepted;

  if (!Is_block(input)) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "primitive argument is not a capability block");
    return 0;
  }
  if (Tag_val(input) != Custom_tag) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "primitive argument has the wrong capability tag");
    return 0;
  }
  if (Wosize_val(input) != P9S_CAPABILITY_WOSIZE) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "primitive argument has the wrong capability size");
    return 0;
  }
  if (Custom_ops_val(input) != &p9s_capability_operations) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "primitive argument has a foreign capability identity");
    return 0;
  }

  payload = (struct p9s_capability *) Data_custom_val(input);
  if (payload->state != P9S_CAPABILITY_UNPUBLISHED
      && payload->state != P9S_CAPABILITY_OPEN
      && payload->state != P9S_CAPABILITY_CLOSED) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "capability has an unknown lifecycle state");
    return 0;
  }
  if ((payload->state == P9S_CAPABILITY_UNPUBLISHED
       && payload->descriptor != -1)
      || (payload->state == P9S_CAPABILITY_OPEN
          && payload->descriptor < 0)
      || (payload->state == P9S_CAPABILITY_CLOSED
          && payload->descriptor != -1)) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "capability state and descriptor are inconsistent");
    return 0;
  }

  accepted = 1 << payload->state;
  if ((accepted_states & accepted) == 0) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "capability lifecycle state rejects this operation");
    return 0;
  }
  *state = payload->state;
  return 1;
}

static int p9s_validate_requested_length(value input, intnat *length,
                                         struct p9s_failure *failure)
{
  intnat decoded;

  if (!Is_long(input)) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "requested length is not an integer");
    return 0;
  }
  decoded = Long_val(input);
  if (decoded < 0 || decoded > P9S_STAGING_CAPACITY) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "requested length is outside the staging capacity");
    return 0;
  }
  *length = decoded;
  return 1;
}

static int p9s_validate_write_range(value source, value position_value,
                                    value length_value, intnat *position,
                                    intnat *length,
                                    struct p9s_failure *failure)
{
  mlsize_t source_length;
  intnat decoded_position;
  intnat decoded_length;

  if (!Is_block(source) || Tag_val(source) != String_tag) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "write source is not a byte string");
    return 0;
  }
  if (!Is_long(position_value)) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "write position is not an integer");
    return 0;
  }
  if (!p9s_validate_requested_length(length_value, &decoded_length,
                                     failure)) {
    return 0;
  }

  decoded_position = Long_val(position_value);
  if (decoded_position < 0) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "write position is negative");
    return 0;
  }
  source_length = caml_string_length(source);
  if ((uintnat) decoded_position > source_length
      || (uintnat) decoded_length
           > source_length - (mlsize_t) decoded_position) {
    p9s_set_failure(failure, P9S_NATIVE_INVALID,
                    "write range is outside the source");
    return 0;
  }

  *position = decoded_position;
  *length = decoded_length;
  return 1;
}

CAMLprim value caml_plan9_syscall_pipe(value unit)
{
  CAMLparam1(unit);
  CAMLlocal4(left, right, pair, success);
  struct p9s_capability *left_payload;
  struct p9s_capability *right_payload;
  struct p9s_failure failure;
  int descriptors[2];
  int owned[2];
  int result;

  if (unit != Val_unit) {
    p9s_set_failure(&failure, P9S_NATIVE_INVALID,
                    "pipe primitive expects unit");
    CAMLreturn(p9s_alloc_error(&failure));
  }

  left = p9s_alloc_capability();
  right = p9s_alloc_capability();
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, left);
  Store_field(pair, 1, right);
  success = caml_alloc_small(1, 0);
  Store_field(success, 0, pair);

  p9s_initialize_failure(&failure);
  descriptors[0] = -1;
  descriptors[1] = -1;
  owned[0] = 0;
  owned[1] = 0;

  caml_enter_blocking_section();
  result = caml_plan9_sys_pipe(descriptors);
  if (result < 0) {
    p9s_capture_failure(&failure);
    caml_leave_blocking_section();
    CAMLreturn(p9s_alloc_error(&failure));
  }

  if (descriptors[0] >= 0) owned[0] = 1;
  if (descriptors[1] >= 0 && descriptors[1] != descriptors[0]) {
    owned[1] = 1;
  }
  if (result != 0 || !owned[0] || !owned[1]) {
    p9s_set_failure(&failure, P9S_NATIVE_PROTOCOL,
                    "raw PIPE returned an invalid result");
    if (owned[0]) (void) caml_plan9_sys_close(descriptors[0]);
    if (owned[1]) (void) caml_plan9_sys_close(descriptors[1]);
    caml_leave_blocking_section();
    CAMLreturn(p9s_alloc_error(&failure));
  }

  caml_leave_blocking_section();
  left_payload = (struct p9s_capability *) Data_custom_val(left);
  right_payload = (struct p9s_capability *) Data_custom_val(right);
  left_payload->descriptor = descriptors[0];
  left_payload->state = P9S_CAPABILITY_OPEN;
  right_payload->descriptor = descriptors[1];
  right_payload->state = P9S_CAPABILITY_OPEN;
  CAMLreturn(success);
}

CAMLprim value caml_plan9_syscall_close(value capability)
{
  CAMLparam1(capability);
  CAMLlocal1(success);
  struct p9s_failure failure;
  int descriptor;
  int result;
  int state;

  if (!p9s_validate_capability(capability,
          P9S_ACCEPT_OPEN | P9S_ACCEPT_CLOSED, &state, &failure)) {
    CAMLreturn(p9s_alloc_error(&failure));
  }
  if (state == P9S_CAPABILITY_CLOSED) {
    CAMLreturn(p9s_alloc_unit_ok());
  }

  p9s_initialize_failure(&failure);
  descriptor = -1;
  result = 0;
  success = p9s_alloc_unit_ok();

  if (caml_check_pending_actions()) caml_process_pending_actions();

  if (!p9s_validate_capability(capability,
          P9S_ACCEPT_OPEN | P9S_ACCEPT_CLOSED, &state, &failure)) {
    CAMLreturn(p9s_alloc_error(&failure));
  }
  if (state == P9S_CAPABILITY_CLOSED) CAMLreturn(success);

  {
    struct p9s_capability *payload;

    payload = (struct p9s_capability *) Data_custom_val(capability);
    descriptor = payload->descriptor;
    payload->descriptor = -1;
    payload->state = P9S_CAPABILITY_CLOSED;
  }
  caml_enter_blocking_section_no_pending();
  result = caml_plan9_sys_close(descriptor);
  if (result < 0) {
    p9s_capture_failure(&failure);
  } else if (result > 0) {
    p9s_set_failure(&failure, P9S_NATIVE_PROTOCOL,
                    "raw CLOSE returned an invalid result");
  }
  caml_leave_blocking_section();

  if (result == 0) CAMLreturn(success);
  CAMLreturn(p9s_alloc_error(&failure));
}

CAMLprim value caml_plan9_syscall_read(value capability,
                                       value requested_length)
{
  CAMLparam2(capability, requested_length);
  CAMLlocal3(buffer, pair, success);
  struct p9s_failure failure;
  unsigned char staging[P9S_STAGING_CAPACITY];
  intnat length;
  mlsize_t index;
  int descriptor;
  int state;
  long result;

  if (!p9s_validate_requested_length(requested_length, &length, &failure)) {
    CAMLreturn(p9s_alloc_error(&failure));
  }
  if (!p9s_validate_capability(capability, P9S_ACCEPT_OPEN, &state,
                               &failure)) {
    CAMLreturn(p9s_alloc_error(&failure));
  }

  buffer = caml_alloc_string((mlsize_t) length);
  for (index = 0; index < (mlsize_t) length; index++) {
    Bytes_val(buffer)[index] = 0;
  }
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, buffer);
  Store_field(pair, 1, Val_int(0));
  success = caml_alloc_small(1, 0);
  Store_field(success, 0, pair);

  p9s_initialize_failure(&failure);
  descriptor = -1;
  result = 0;

  if (caml_check_pending_actions()) caml_process_pending_actions();

  if (!p9s_validate_capability(capability, P9S_ACCEPT_OPEN, &state,
                               &failure)) {
    CAMLreturn(p9s_alloc_error(&failure));
  }
  {
    struct p9s_capability *payload;

    payload = (struct p9s_capability *) Data_custom_val(capability);
    descriptor = payload->descriptor;
  }
  if (length == 0) CAMLreturn(success);

  caml_enter_blocking_section_no_pending();
  result = caml_plan9_sys_pread(descriptor, staging, (long) length,
                                CAML_PLAN9_SYSCALL_STREAM_OFFSET);
  if (result < 0) p9s_capture_failure(&failure);
  caml_leave_blocking_section();

  if (result < 0) CAMLreturn(p9s_alloc_error(&failure));
  if (result > (long) length) {
    p9s_set_failure(&failure, P9S_NATIVE_PROTOCOL,
                    "raw PREAD returned an invalid success count");
    CAMLreturn(p9s_alloc_error(&failure));
  }

  for (index = 0; index < (mlsize_t) result; index++) {
    Bytes_val(buffer)[index] = staging[index];
  }
  Store_field(pair, 1, Val_long(result));
  CAMLreturn(success);
}

CAMLprim value caml_plan9_syscall_write(value capability, value source,
                                        value position,
                                        value requested_length)
{
  CAMLparam4(capability, source, position, requested_length);
  CAMLlocal1(success);
  struct p9s_failure failure;
  unsigned char staging[P9S_STAGING_CAPACITY];
  intnat decoded_position;
  intnat length;
  mlsize_t index;
  int descriptor;
  int state;
  long result;

  if (!p9s_validate_capability(capability, P9S_ACCEPT_OPEN, &state,
                               &failure)) {
    CAMLreturn(p9s_alloc_error(&failure));
  }
  if (!p9s_validate_write_range(source, position, requested_length,
                                &decoded_position, &length, &failure)) {
    CAMLreturn(p9s_alloc_error(&failure));
  }

  success = caml_alloc_small(1, 0);
  Store_field(success, 0, Val_int(0));

  p9s_initialize_failure(&failure);
  descriptor = -1;
  result = 0;

  if (caml_check_pending_actions()) caml_process_pending_actions();

  if (!p9s_validate_write_range(source, position, requested_length,
                                &decoded_position, &length, &failure)) {
    CAMLreturn(p9s_alloc_error(&failure));
  }
  for (index = 0; index < (mlsize_t) length; index++) {
    staging[index] = Bytes_val(source)[(mlsize_t) decoded_position + index];
  }
  if (!p9s_validate_capability(capability, P9S_ACCEPT_OPEN, &state,
                               &failure)) {
    CAMLreturn(p9s_alloc_error(&failure));
  }
  {
    struct p9s_capability *payload;

    payload = (struct p9s_capability *) Data_custom_val(capability);
    descriptor = payload->descriptor;
  }
  if (length == 0) CAMLreturn(success);

  caml_enter_blocking_section_no_pending();
  result = caml_plan9_sys_pwrite(descriptor, staging, (long) length,
                                 CAML_PLAN9_SYSCALL_STREAM_OFFSET);
  if (result < 0) p9s_capture_failure(&failure);
  caml_leave_blocking_section();

  if (result < 0) CAMLreturn(p9s_alloc_error(&failure));
  if (result > (long) length) {
    p9s_set_failure(&failure, P9S_NATIVE_PROTOCOL,
                    "raw PWRITE returned an invalid success count");
    CAMLreturn(p9s_alloc_error(&failure));
  }

  Store_field(success, 0, Val_long(result));
  CAMLreturn(success);
}

CAMLprim value caml_plan9_syscall_negative_read_probe(value unit)
{
  CAMLparam1(unit);
  struct p9s_failure failure;
  unsigned char byte;
  int descriptors[2];
  int owned[2];
  int saved_target;
  int pipe_result;
  int close_result;
  long read_result;

  if (unit != Val_unit) {
    p9s_set_failure(&failure, P9S_NATIVE_INVALID,
                    "negative read probe expects unit");
    CAMLreturn(p9s_alloc_failure(&failure));
  }

  p9s_initialize_failure(&failure);
  byte = 0;
  descriptors[0] = -1;
  descriptors[1] = -1;
  owned[0] = 0;
  owned[1] = 0;
  saved_target = -1;
  pipe_result = 0;
  close_result = 0;
  read_result = 0;

  caml_enter_blocking_section_no_pending();
  pipe_result = caml_plan9_sys_pipe(descriptors);
  if (pipe_result < 0) {
    p9s_capture_failure(&failure);
    goto leave;
  }

  if (descriptors[0] >= 0) owned[0] = 1;
  if (descriptors[1] >= 0 && descriptors[1] != descriptors[0]) {
    owned[1] = 1;
  }
  if (pipe_result != 0 || !owned[0] || !owned[1]) {
    p9s_set_failure(&failure, P9S_NATIVE_PROTOCOL,
                    "probe PIPE returned an invalid result");
    goto cleanup;
  }

  saved_target = descriptors[0];
  owned[0] = 0;
  close_result = caml_plan9_sys_close(saved_target);
  if (close_result < 0) {
    p9s_capture_failure(&failure);
    goto cleanup;
  }
  if (close_result > 0) {
    p9s_set_failure(&failure, P9S_NATIVE_PROTOCOL,
                    "probe CLOSE returned an invalid result");
    goto cleanup;
  }

  read_result = caml_plan9_sys_pread(
      saved_target, &byte, 1, CAML_PLAN9_SYSCALL_STREAM_OFFSET);
  if (read_result < 0) {
    p9s_capture_failure(&failure);
  } else {
    p9s_set_failure(&failure, P9S_NATIVE_PROTOCOL,
                    "probe PREAD on a closed descriptor did not fail");
  }

cleanup:
  if (owned[0]) (void) caml_plan9_sys_close(descriptors[0]);
  if (owned[1]) (void) caml_plan9_sys_close(descriptors[1]);
leave:
  caml_leave_blocking_section();
  CAMLreturn(p9s_alloc_failure(&failure));
}
