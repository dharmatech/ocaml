/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*             Xavier Leroy, projet Gallium, INRIA Paris                  */
/*                                                                        */
/*   Copyright 2017 Institut National de Recherche en Informatique et     */
/*     en Automatique.                                                    */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

#define CAML_INTERNALS

#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <caml/mlvalues.h>
#include <caml/io.h>
#include <caml/signals.h>
#include "unixsupport.h"

#ifdef HAS_SOCKETS
#include <sys/socket.h>
#include "socketaddr.h"
#endif

#if defined(CAML_PLAN9_CHANNEL_SOCKET_FALLBACKS) && defined(HAS_SOCKETS)
/* APE keeps socket type in a private Rock table.  See
   /sys/src/ape/lib/bsd/priv.h; only the stable prefix is repeated here. */
typedef struct caml_plan9_ape_socket_rock {
  struct caml_plan9_ape_socket_rock *next;
  unsigned long dev;
  unsigned long inode;
  int domain;
  int stype;
  int protocol;
} caml_plan9_ape_socket_rock;

extern caml_plan9_ape_socket_rock *_sock_findrock(int, struct stat *);

static int caml_plan9_socket_stream_semantics
           (int fd, struct stat *buf, int *is_socket)
{
  caml_plan9_ape_socket_rock *rock = _sock_findrock(fd, buf);
  if (rock == NULL) {
    *is_socket = 0;
    return 0;
  }
  *is_socket = 1;
  return rock->stype == SOCK_STREAM ? 0 : EINVAL;
}
#endif

/* Check that the given file descriptor has "stream semantics" and
   can therefore be used as part of buffered I/O.  Things that
   don't have "stream semantics" include block devices and
   UDP (datagram) sockets.
   Returns 0 if OK, a nonzero error code if error. */

static int unix_check_stream_semantics(int fd)
{
  struct stat buf;

  if (fstat(fd, &buf) == -1) return errno;
#if defined(CAML_PLAN9_CHANNEL_SOCKET_FALLBACKS) && defined(HAS_SOCKETS)
  {
    int is_socket;
    int socket_err = caml_plan9_socket_stream_semantics(fd, &buf, &is_socket);
    if (is_socket || socket_err != 0) return socket_err;
  }
#endif
  switch (buf.st_mode & S_IFMT) {
  case S_IFREG: case S_IFCHR: case S_IFIFO:
    /* These have stream semantics */
    return 0;
#if defined(HAS_SOCKETS) && defined(S_IFSOCK) && \
    (!defined(S_IFIFO) || S_IFSOCK != S_IFIFO)
  case S_IFSOCK: {
    int so_type;
    socklen_param_type so_type_len = sizeof(so_type);
    if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &so_type, &so_type_len) == -1)
      return errno;
    switch (so_type) {
    case SOCK_STREAM:
      return 0;
    default:
      return EINVAL;
    }
    }
#endif
  default:
    /* All other file types are suspect: block devices, directories,
       symbolic links, whatnot. */
    return EINVAL;
  }
}

CAMLprim value unix_inchannel_of_filedescr(value fd)
{
  int err;
  caml_enter_blocking_section();
  err = unix_check_stream_semantics(Int_val(fd));
  caml_leave_blocking_section();
  if (err != 0) unix_error(err, "in_channel_of_descr", Nothing);
  return caml_ml_open_descriptor_in(fd);
}

CAMLprim value unix_outchannel_of_filedescr(value fd)
{
  int err;
  caml_enter_blocking_section();
  err = unix_check_stream_semantics(Int_val(fd));
  caml_leave_blocking_section();
  if (err != 0) unix_error(err, "out_channel_of_descr", Nothing);
  return caml_ml_open_descriptor_out(fd);
}
