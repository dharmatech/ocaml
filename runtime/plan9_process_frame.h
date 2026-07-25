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

#ifndef CAML_PLAN9_PROCESS_FRAME_H
#define CAML_PLAN9_PROCESS_FRAME_H

#include <stddef.h>
#include <stdint.h>

enum {
  P9_FRAME_PAYLOAD_MAX = 127
};

enum p9_frame_outcome {
  P9_FRAME_EXECUTED,
  P9_FRAME_EXEC_FAILED,
  P9_FRAME_IO_ERROR,
  P9_FRAME_PROTOCOL_ERROR
};

struct p9_frame_result {
  enum p9_frame_outcome outcome;
  unsigned char payload[P9_FRAME_PAYLOAD_MAX + 1];
  size_t payload_length;
  const char *protocol_message;
};

typedef long (*p9_frame_read_fn)(void *, unsigned char *, size_t);
typedef long (*p9_frame_write_fn)(void *, const unsigned char *, size_t);

static int p9_frame_write_all(p9_frame_write_fn write_fn, void *context,
                              const unsigned char *buffer, size_t length)
{
  size_t offset;
  long count;

  offset = 0;
  while (offset < length) {
    count = write_fn(context, buffer + offset, length - offset);
    if (count <= 0 || (size_t) count > length - offset) return 0;
    offset += (size_t) count;
  }
  return 1;
}

static int p9_write_exec_frame(p9_frame_write_fn write_fn, void *context,
                               const unsigned char *payload, size_t length)
{
  unsigned char header[8];

  if (length == 0 || length > P9_FRAME_PAYLOAD_MAX) return 0;
  header[0] = 'P';
  header[1] = '9';
  header[2] = 'E';
  header[3] = '1';
  header[4] = (unsigned char) ((length >> 24) & 0xff);
  header[5] = (unsigned char) ((length >> 16) & 0xff);
  header[6] = (unsigned char) ((length >> 8) & 0xff);
  header[7] = (unsigned char) (length & 0xff);
  if (!p9_frame_write_all(write_fn, context, header, sizeof(header))) {
    return 0;
  }
  return p9_frame_write_all(write_fn, context, payload, length);
}

static int p9_frame_read_exact(p9_frame_read_fn read_fn, void *context,
                               unsigned char *buffer, size_t length)
{
  size_t offset;
  long count;

  offset = 0;
  while (offset < length) {
    count = read_fn(context, buffer + offset, length - offset);
    if (count < 0) return -1;
    if (count == 0) return 0;
    if ((size_t) count > length - offset) return -2;
    offset += (size_t) count;
  }
  return 1;
}

static void p9_read_exec_frame(p9_frame_read_fn read_fn, void *context,
                               struct p9_frame_result *result)
{
  unsigned char header[8];
  unsigned char trailing;
  uint32_t length;
  long first;
  int read_result;

  result->outcome = P9_FRAME_PROTOCOL_ERROR;
  result->payload[0] = 0;
  result->payload_length = 0;
  result->protocol_message = "exec handshake was not decoded";

  first = read_fn(context, header, 1);
  if (first == 0) {
    result->outcome = P9_FRAME_EXECUTED;
    result->protocol_message = NULL;
    return;
  }
  if (first < 0) {
    result->outcome = P9_FRAME_IO_ERROR;
    result->protocol_message = NULL;
    return;
  }
  if (first != 1) {
    result->protocol_message =
      "native frame reader returned an invalid count";
    return;
  }

  read_result =
    p9_frame_read_exact(read_fn, context, header + 1, sizeof(header) - 1);
  if (read_result < 0) {
    if (read_result == -1) {
      result->outcome = P9_FRAME_IO_ERROR;
      result->protocol_message = NULL;
    } else {
      result->protocol_message =
        "native frame reader returned an invalid count";
    }
    return;
  }
  if (read_result == 0) {
    result->protocol_message = "truncated P9E1 header";
    return;
  }
  if (header[0] != 'P' || header[1] != '9'
      || header[2] != 'E' || header[3] != '1') {
    result->protocol_message = "invalid P9E1 tag or version";
    return;
  }
  length = ((uint32_t) header[4] << 24)
    | ((uint32_t) header[5] << 16)
    | ((uint32_t) header[6] << 8)
    | (uint32_t) header[7];
  if (length == 0 || length > P9_FRAME_PAYLOAD_MAX) {
    result->protocol_message = "invalid P9E1 payload length";
    return;
  }

  read_result =
    p9_frame_read_exact(read_fn, context, result->payload, length);
  if (read_result < 0) {
    if (read_result == -1) {
      result->outcome = P9_FRAME_IO_ERROR;
      result->protocol_message = NULL;
    } else {
      result->protocol_message =
        "native frame reader returned an invalid count";
    }
    return;
  }
  if (read_result == 0) {
    result->protocol_message = "truncated P9E1 payload";
    return;
  }
  result->payload[length] = 0;
  result->payload_length = length;

  first = read_fn(context, &trailing, 1);
  if (first < 0) {
    result->outcome = P9_FRAME_IO_ERROR;
    result->protocol_message = NULL;
    return;
  }
  if (first != 0) {
    result->protocol_message = "trailing data after P9E1 payload";
    return;
  }

  result->outcome = P9_FRAME_EXEC_FAILED;
  result->protocol_message = NULL;
}

#endif /* CAML_PLAN9_PROCESS_FRAME_H */
