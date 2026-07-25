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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../../runtime/plan9_process_frame.h"

struct scripted_reader {
  const unsigned char *bytes;
  size_t length;
  size_t offset;
  size_t maximum_chunk;
  long fail_at_offset;
  int invalid_count;
};

struct scripted_writer {
  unsigned char bytes[8 + P9_FRAME_PAYLOAD_MAX];
  size_t offset;
  size_t maximum_chunk;
  long fail_at_offset;
  int return_zero;
  int invalid_count;
};

static void fail(const char *message)
{
  fprintf(stderr, "process_frame_parser_test: %s\n", message);
  exit(1);
}

static long scripted_read(void *context, unsigned char *buffer, size_t length)
{
  struct scripted_reader *reader;
  size_t available;
  size_t count;

  reader = context;
  if (reader->invalid_count) return (long) length + 1;
  if (reader->fail_at_offset >= 0
      && reader->offset == (size_t) reader->fail_at_offset) {
    return -1;
  }
  if (reader->offset == reader->length) return 0;
  available = reader->length - reader->offset;
  count = length < available ? length : available;
  if (reader->maximum_chunk != 0 && count > reader->maximum_chunk) {
    count = reader->maximum_chunk;
  }
  memcpy(buffer, reader->bytes + reader->offset, count);
  reader->offset += count;
  return (long) count;
}

static long scripted_write(void *context, const unsigned char *buffer,
                           size_t length)
{
  struct scripted_writer *writer;
  size_t count;

  writer = context;
  if (writer->invalid_count) return (long) length + 1;
  if (writer->fail_at_offset >= 0
      && writer->offset == (size_t) writer->fail_at_offset) {
    return -1;
  }
  if (writer->return_zero) return 0;
  count = length;
  if (writer->maximum_chunk != 0 && count > writer->maximum_chunk) {
    count = writer->maximum_chunk;
  }
  if (writer->offset + count > sizeof(writer->bytes)) return -1;
  memcpy(writer->bytes + writer->offset, buffer, count);
  writer->offset += count;
  return (long) count;
}

static struct p9_frame_result decode(const unsigned char *bytes, size_t length,
                                     size_t maximum_chunk,
                                     long fail_at_offset, int invalid_count)
{
  struct scripted_reader reader;
  struct p9_frame_result result;

  reader.bytes = bytes;
  reader.length = length;
  reader.offset = 0;
  reader.maximum_chunk = maximum_chunk;
  reader.fail_at_offset = fail_at_offset;
  reader.invalid_count = invalid_count;
  p9_read_exec_frame(scripted_read, &reader, &result);
  return result;
}

static void expect_protocol(const char *label, const unsigned char *bytes,
                            size_t length, const char *message)
{
  struct p9_frame_result result;

  result = decode(bytes, length, 1, -1, 0);
  if (result.outcome != P9_FRAME_PROTOCOL_ERROR) fail(label);
  if (result.protocol_message == NULL
      || strcmp(result.protocol_message, message) != 0) {
    fail(label);
  }
}

static void test_clean_eof(void)
{
  struct p9_frame_result result;

  result = decode((const unsigned char *) "", 0, 1, -1, 0);
  if (result.outcome != P9_FRAME_EXECUTED) {
    fail("clean EOF was not exec success");
  }
}

static void test_partial_valid_frame(void)
{
  static const unsigned char frame[] = {
    'P', '9', 'E', '1', 0, 0, 0, 5, 'e', 'r', 'r', 'o', 'r'
  };
  struct p9_frame_result result;

  result = decode(frame, sizeof(frame), 1, -1, 0);
  if (result.outcome != P9_FRAME_EXEC_FAILED) {
    fail("one-byte reads did not decode a valid P9E1 frame");
  }
  if (result.payload_length != 5
      || memcmp(result.payload, "error", 5) != 0
      || result.payload[5] != 0) {
    fail("valid P9E1 payload was not preserved");
  }
}

static void test_maximum_payload(void)
{
  unsigned char frame[8 + P9_FRAME_PAYLOAD_MAX];
  struct p9_frame_result result;
  size_t index;

  frame[0] = 'P';
  frame[1] = '9';
  frame[2] = 'E';
  frame[3] = '1';
  frame[4] = 0;
  frame[5] = 0;
  frame[6] = 0;
  frame[7] = P9_FRAME_PAYLOAD_MAX;
  for (index = 0; index < P9_FRAME_PAYLOAD_MAX; index++) {
    frame[8 + index] = 'x';
  }
  result = decode(frame, sizeof(frame), 7, -1, 0);
  if (result.outcome != P9_FRAME_EXEC_FAILED
      || result.payload_length != P9_FRAME_PAYLOAD_MAX
      || result.payload[P9_FRAME_PAYLOAD_MAX] != 0) {
    fail("maximum bounded P9E1 payload was not preserved");
  }
}

static void test_partial_frame_writes(void)
{
  static const unsigned char expected[] = {
    'P', '9', 'E', '1', 0, 0, 0, 5, 'e', 'r', 'r', 'o', 'r'
  };
  struct scripted_writer writer;

  memset(&writer, 0, sizeof(writer));
  writer.maximum_chunk = 1;
  writer.fail_at_offset = -1;
  if (!p9_write_exec_frame(scripted_write, &writer,
                           expected + 8, sizeof(expected) - 8)
      || writer.offset != sizeof(expected)
      || memcmp(writer.bytes, expected, sizeof(expected)) != 0) {
    fail("one-byte writes did not encode an exact P9E1 frame");
  }

  memset(&writer, 0, sizeof(writer));
  writer.maximum_chunk = 1;
  writer.fail_at_offset = 4;
  if (p9_write_exec_frame(scripted_write, &writer,
                          expected + 8, sizeof(expected) - 8)) {
    fail("partial frame write failure was accepted");
  }

  memset(&writer, 0, sizeof(writer));
  writer.return_zero = 1;
  writer.fail_at_offset = -1;
  if (p9_write_exec_frame(scripted_write, &writer,
                          expected + 8, sizeof(expected) - 8)) {
    fail("zero-length frame write was accepted");
  }

  memset(&writer, 0, sizeof(writer));
  writer.invalid_count = 1;
  writer.fail_at_offset = -1;
  if (p9_write_exec_frame(scripted_write, &writer,
                          expected + 8, sizeof(expected) - 8)) {
    fail("invalid writer count was accepted");
  }

  memset(&writer, 0, sizeof(writer));
  writer.fail_at_offset = -1;
  if (p9_write_exec_frame(scripted_write, &writer, expected + 8, 0)
      || p9_write_exec_frame(scripted_write, &writer, expected + 8,
                             P9_FRAME_PAYLOAD_MAX + 1)) {
    fail("invalid frame payload length was accepted by the writer");
  }
}

static void test_protocol_edges(void)
{
  static const unsigned char short_header[] = {
    'P', '9', 'E'
  };
  static const unsigned char bad_tag[] = {
    'P', '9', 'E', '2', 0, 0, 0, 1, 'x'
  };
  static const unsigned char zero_length[] = {
    'P', '9', 'E', '1', 0, 0, 0, 0
  };
  static const unsigned char long_length[] = {
    'P', '9', 'E', '1', 0, 0, 0, 128
  };
  static const unsigned char short_payload[] = {
    'P', '9', 'E', '1', 0, 0, 0, 3, 'x', 'y'
  };
  static const unsigned char trailing[] = {
    'P', '9', 'E', '1', 0, 0, 0, 1, 'x', '!'
  };

  expect_protocol("truncated header was accepted",
                  short_header, sizeof(short_header),
                  "truncated P9E1 header");
  expect_protocol("invalid tag was accepted", bad_tag, sizeof(bad_tag),
                  "invalid P9E1 tag or version");
  expect_protocol("zero payload length was accepted",
                  zero_length, sizeof(zero_length),
                  "invalid P9E1 payload length");
  expect_protocol("oversized payload length was accepted",
                  long_length, sizeof(long_length),
                  "invalid P9E1 payload length");
  expect_protocol("truncated payload was accepted",
                  short_payload, sizeof(short_payload),
                  "truncated P9E1 payload");
  expect_protocol("trailing payload data was accepted",
                  trailing, sizeof(trailing),
                  "trailing data after P9E1 payload");
}

static void test_io_and_reader_failures(void)
{
  static const unsigned char frame[] = {
    'P', '9', 'E', '1', 0, 0, 0, 1, 'x'
  };
  struct p9_frame_result result;

  result = decode(frame, sizeof(frame), 1, 0, 0);
  if (result.outcome != P9_FRAME_IO_ERROR) {
    fail("initial read error was not preserved");
  }
  result = decode(frame, sizeof(frame), 1, 4, 0);
  if (result.outcome != P9_FRAME_IO_ERROR) {
    fail("partial header read error was not preserved");
  }
  result = decode(frame, sizeof(frame), 1, 8, 0);
  if (result.outcome != P9_FRAME_IO_ERROR) {
    fail("partial payload read error was not preserved");
  }
  result = decode(frame, sizeof(frame), 1, 9, 0);
  if (result.outcome != P9_FRAME_IO_ERROR) {
    fail("trailing-EOF read error was not preserved");
  }
  result = decode(frame, sizeof(frame), 1, -1, 1);
  if (result.outcome != P9_FRAME_PROTOCOL_ERROR
      || result.protocol_message == NULL
      || strcmp(result.protocol_message,
                "native frame reader returned an invalid count") != 0) {
    fail("invalid reader count did not fail closed");
  }
}

int main(void)
{
  test_clean_eof();
  test_partial_valid_frame();
  test_maximum_payload();
  test_partial_frame_writes();
  test_protocol_edges();
  test_io_and_reader_failures();
  printf("process_frame_parser_test: passed\n");
  return 0;
}
