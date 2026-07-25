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

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum {
  P9_OREAD = 0,
  P9_OWRITE = 1,
  P9_OTRUNC = 16
};

extern int _CLOSE(int);
extern int _CREATE(char *, int, unsigned long);
extern int _DUP(int, int);
extern int _EXEC(char *, char **);
extern void _EXITS(char *);
extern int _OPEN(const char *, int);
extern long _READ(int, void *, long);
extern long _WRITE(int, const void *, long);

static void finish(char *status)
{
  for (;;) _EXITS(status);
}

static int write_all(int fd, const unsigned char *buffer, size_t length)
{
  size_t offset;
  long count;

  offset = 0;
  while (offset < length) {
    count = _WRITE(fd, buffer + offset, (long) (length - offset));
    if (count <= 0) return 0;
    offset += (size_t) count;
  }
  return 1;
}

static int write_u32(int fd, uint32_t value)
{
  unsigned char bytes[4];

  bytes[0] = (unsigned char) ((value >> 24) & 0xff);
  bytes[1] = (unsigned char) ((value >> 16) & 0xff);
  bytes[2] = (unsigned char) ((value >> 8) & 0xff);
  bytes[3] = (unsigned char) (value & 0xff);
  return write_all(fd, bytes, sizeof(bytes));
}

static int record_argv(int argc, char **argv, const char *path)
{
  int fd;
  int index;
  size_t length;

  fd = _CREATE((char *) path, P9_OWRITE | P9_OTRUNC, 0666);
  if (fd < 0) return 0;
  if (!write_u32(fd, (uint32_t) argc)) goto failed;
  for (index = 0; index < argc; index++) {
    length = strlen(argv[index]);
    if (length > (size_t) ((uint32_t) -1)) goto failed;
    if (!write_u32(fd, (uint32_t) length)) goto failed;
    if (!write_all(fd, (const unsigned char *) argv[index], length)) {
      goto failed;
    }
  }
  (void) _CLOSE(fd);
  return 1;

failed:
  (void) _CLOSE(fd);
  return 0;
}

static int copy_file(const char *source, const char *destination)
{
  unsigned char buffer[256];
  int input;
  int output;
  long count;

  input = _OPEN(source, P9_OREAD);
  if (input < 0) return 0;
  output = _CREATE((char *) destination, P9_OWRITE | P9_OTRUNC, 0666);
  if (output < 0) {
    (void) _CLOSE(input);
    return 0;
  }
  for (;;) {
    count = _READ(input, buffer, sizeof(buffer));
    if (count < 0) goto failed;
    if (count == 0) break;
    if (!write_all(output, buffer, (size_t) count)) goto failed;
  }
  (void) _CLOSE(input);
  (void) _CLOSE(output);
  return 1;

failed:
  (void) _CLOSE(input);
  (void) _CLOSE(output);
  return 0;
}

static int wait_for_file(const char *path)
{
  int attempt;
  int fd;

  for (attempt = 0; attempt < 10; attempt++) {
    fd = _OPEN(path, P9_OREAD);
    if (fd >= 0) {
      (void) _CLOSE(fd);
      return 1;
    }
    sleep(1);
  }
  return 0;
}

static int parse_mask(const char *text)
{
  int mask;

  if (text[0] == 0 || text[1] != 0 || text[0] < '0' || text[0] > '7') {
    return -1;
  }
  mask = text[0] - '0';
  return mask;
}

static void exec_runtime(int argc, char **argv)
{
  char **exec_argv;
  const char *stdout_path;
  int output;
  int mask;
  int index;
  int exec_argc;

  if (argc < 7) finish("process helper: incomplete exec-runtime arguments");
  mask = parse_mask(argv[2]);
  if (mask < 0) finish("process helper: invalid descriptor mask");
  stdout_path = argv[3];
  if (strcmp(stdout_path, "-") != 0) {
    output = _CREATE((char *) stdout_path, P9_OWRITE | P9_OTRUNC, 0666);
    if (output < 0) finish("process helper: stdout create failed");
    if (_DUP(output, 1) < 0) {
      (void) _CLOSE(output);
      finish("process helper: stdout dup failed");
    }
    (void) _CLOSE(output);
  }

  if ((mask & 1) != 0) (void) _CLOSE(0);
  if ((mask & 2) != 0) (void) _CLOSE(1);
  if ((mask & 4) != 0) (void) _CLOSE(2);

  exec_argc = argc - 4;
  exec_argv = calloc((size_t) exec_argc + 1, sizeof(char *));
  if (exec_argv == NULL) finish("process helper: argv allocation failed");
  exec_argv[0] = argv[4];
  exec_argv[1] = argv[5];
  for (index = 6; index < argc; index++) {
    exec_argv[index - 4] = argv[index];
  }
  exec_argv[exec_argc] = NULL;
  (void) _EXEC(argv[4], exec_argv);
  finish("process helper: runtime exec failed");
}

static int interrupt_parent(unsigned int seconds)
{
  static const unsigned char note[] = "interrupt";
  char path[64];
  int fd;
  long parent;

  sleep(seconds);
  parent = (long) getppid();
  if (parent <= 0) return 0;
  if (sprintf(path, "/proc/%ld/note", parent) < 0) return 0;
  fd = _OPEN(path, P9_OWRITE);
  if (fd < 0) return 0;
  if (!write_all(fd, note, sizeof(note) - 1)) {
    (void) _CLOSE(fd);
    return 0;
  }
  (void) _CLOSE(fd);
  return 1;
}

int main(int argc, char **argv)
{
  unsigned int seconds;

  if (argc >= 3 && strcmp(argv[1], "record-argv") == 0) {
    if (!record_argv(argc, argv, argv[2])) {
      finish("process helper: argv record failed");
    }
    finish("");
  }
  if (argc == 3 && strcmp(argv[1], "emit") == 0) {
    if (!write_all(1, (const unsigned char *) argv[2], strlen(argv[2]))) {
      finish("process helper: stdout write failed");
    }
    finish("");
  }
  if (argc == 3 && strcmp(argv[1], "exit") == 0) {
    finish(argv[2]);
  }
  if (argc == 4 && strcmp(argv[1], "delay-exit") == 0) {
    seconds = (unsigned int) strtoul(argv[2], NULL, 10);
    if (seconds > 5) finish("process helper: delay exceeds bound");
    sleep(seconds);
    finish(argv[3]);
  }
  if (argc == 5 && strcmp(argv[1], "env-read-after") == 0) {
    if (!wait_for_file(argv[2])) {
      finish("process helper: environment trigger timed out");
    }
    if (!copy_file(argv[3], argv[4])) {
      finish("process helper: environment read failed");
    }
    finish("");
  }
  if (argc >= 7 && strcmp(argv[1], "exec-runtime") == 0) {
    exec_runtime(argc, argv);
  }
  if (argc == 3 && strcmp(argv[1], "interrupt-parent") == 0) {
    seconds = (unsigned int) strtoul(argv[2], NULL, 10);
    if (seconds > 5) finish("process helper: delay exceeds bound");
    if (!interrupt_parent(seconds)) {
      finish("process helper: parent interruption failed");
    }
    finish("");
  }
  finish("process helper: unknown mode");
  return 1;
}
