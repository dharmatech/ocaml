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

#ifndef CAML_PLAN9_SYSCALL_H
#define CAML_PLAN9_SYSCALL_H

enum { CAML_PLAN9_SYSCALL_ERRMAX = 128 };

#define CAML_PLAN9_SYSCALL_STREAM_OFFSET (-1LL)

/* These raw entries accept only native C values and caller-owned buffers.
   They allocate nothing, call no C or OCaml function, and return the kernel
   result unchanged.  Each entry is safe for the constrained post-rfork,
   pre-exec child path.  Callers own descriptor lifetime and must capture a
   negative result with caml_plan9_sys_errstr before cleanup or diagnostics. */
extern int caml_plan9_sys_errstr(char *, unsigned int);
extern int caml_plan9_sys_close(int);
extern int caml_plan9_sys_pipe(int *);
extern long caml_plan9_sys_pread(int, void *, long, long long);
extern long caml_plan9_sys_pwrite(int, void *, long, long long);

#endif /* CAML_PLAN9_SYSCALL_H */
