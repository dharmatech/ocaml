/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*                         The OCaml programmers                          */
/*                                                                        */
/*   Copyright 2020 Institut National de Recherche en Informatique et     */
/*     en Automatique.                                                    */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include "unixsupport.h"

#if defined(HAS_REALPATH) || defined(CAML_PLAN9_REALPATH_FALLBACKS)
#include <stdlib.h>
#endif

#ifdef CAML_PLAN9_REALPATH_FALLBACKS
#include <errno.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

#ifdef HAS_REALPATH

CAMLprim value unix_realpath (value p)
{
  CAMLparam1 (p);
  char *r;
  value rp;

  caml_unix_check_path (p, "realpath");
  r = realpath (String_val (p), NULL);
  if (r == NULL) { uerror ("realpath", p); }
  rp = caml_copy_string (r);
  free (r);
  CAMLreturn (rp);
}

#elif defined(CAML_PLAN9_REALPATH_FALLBACKS)

#define PLAN9_SEP(c) ((c) == '/' || (c) == '\0')

static char *caml_plan9_cleanname(char *name)
{
  char *p, *q, *dotdot;
  int rooted, erasedprefix;

  rooted = name[0] == '/';
  erasedprefix = 0;
  p = q = dotdot = name + rooted;
  while (*p) {
    if (p[0] == '/') {
      p++;
    } else if (p[0] == '.' && PLAN9_SEP(p[1])) {
      if (p == name) erasedprefix = 1;
      p += 1;
    } else if (p[0] == '.' && p[1] == '.' && PLAN9_SEP(p[2])) {
      p += 2;
      if (q > dotdot) {
        while (--q > dotdot && *q != '/') {
          /* backtrack over the previous path element */
        }
      } else if (!rooted) {
        if (q != name) *q++ = '/';
        *q++ = '.';
        *q++ = '.';
        dotdot = q;
      }
      if (q == name) erasedprefix = 1;
    } else {
      if (q != name + rooted) *q++ = '/';
      while ((*q = *p) != '/' && *q != '\0') {
        p++;
        q++;
      }
    }
  }
  if (q == name) *q++ = '.';
  *q = '\0';
  if (erasedprefix && name[0] == '#') {
    memmove(name + 2, name, strlen(name) + 1);
    name[0] = '.';
    name[1] = '/';
  }
  return name;
}

static char *caml_plan9_getcwd_alloc(void)
{
  size_t size;
  char *buf, *next;
  int saved_errno;

  size = 512;
  while (size <= UNIX_BUFFER_SIZE) {
    buf = malloc(size);
    if (buf == NULL) {
      errno = ENOMEM;
      return NULL;
    }
    if (getcwd(buf, size) != NULL) return buf;
    saved_errno = errno;
    free(buf);
    if (saved_errno != ERANGE && saved_errno != EIO) {
      errno = saved_errno;
      return NULL;
    }
    if (size > UNIX_BUFFER_SIZE / 2) break;
    size *= 2;
  }

  next = malloc(UNIX_BUFFER_SIZE);
  if (next == NULL) {
    errno = ENOMEM;
    return NULL;
  }
  if (getcwd(next, UNIX_BUFFER_SIZE) != NULL) return next;
  saved_errno = errno;
  free(next);
  errno = saved_errno;
  return NULL;
}

static char *caml_plan9_absolute_path(const char *path)
{
  char *cwd, *resolved;
  size_t cwd_len, path_len, total_len;

  path_len = strlen(path);
  if (path_len == 0) {
    errno = ENOENT;
    return NULL;
  }

  if (path[0] == '/') {
    resolved = malloc(path_len + 1);
    if (resolved == NULL) {
      errno = ENOMEM;
      return NULL;
    }
    memcpy(resolved, path, path_len + 1);
    return resolved;
  }

  cwd = caml_plan9_getcwd_alloc();
  if (cwd == NULL) return NULL;
  cwd_len = strlen(cwd);
  if (cwd_len > ((size_t) -1) - path_len - 2) {
    free(cwd);
    errno = ENAMETOOLONG;
    return NULL;
  }
  total_len = cwd_len + 1 + path_len + 1;
  resolved = malloc(total_len);
  if (resolved == NULL) {
    free(cwd);
    errno = ENOMEM;
    return NULL;
  }
  memcpy(resolved, cwd, cwd_len);
  resolved[cwd_len] = '/';
  memcpy(resolved + cwd_len + 1, path, path_len + 1);
  free(cwd);
  return resolved;
}

CAMLprim value unix_realpath(value p)
{
  CAMLparam1(p);
  char *resolved;
  value rp;
  struct stat st;
  int saved_errno;

  caml_unix_check_path(p, "realpath");
  resolved = caml_plan9_absolute_path(String_val(p));
  if (resolved == NULL) uerror("realpath", p);
  caml_plan9_cleanname(resolved);
  if (stat(resolved, &st) == -1) {
    saved_errno = errno;
    free(resolved);
    errno = saved_errno;
    uerror("realpath", p);
  }
  rp = caml_copy_string(resolved);
  free(resolved);
  CAMLreturn(rp);
}

#else

CAMLprim value unix_realpath (value p)
{ caml_invalid_argument ("realpath not implemented"); }

#endif
