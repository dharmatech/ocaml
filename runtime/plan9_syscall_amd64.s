/* Raw amd64 Plan 9 syscall entries for the private OCaml-owned veneer.
   The entry convention is derived from the minimal amd64 recipe in
   9front sys/src/libc/9syscall/mkfile:64-71 at commit
   2191d72205863d2c53ea6ac36991cb4c13204c7c.  Plan 9 and the relevant
   9front additions are MIT-licensed by lib/legal/NOTICE in that tree. */

/* MIT 9front 2191d72205863d2c53ea6ac36991cb4c13204c7c;
   sys/src/libc/9syscall/sys.h:5: CLOSE = 4. */
TEXT caml_plan9_sys_close(SB), 1, $0
	MOVQ RARG, a0+0(FP)
	MOVQ $4, RARG
	SYSCALL
	RET

/* MIT 9front 2191d72205863d2c53ea6ac36991cb4c13204c7c;
   sys/src/libc/9syscall/sys.h:22: PIPE = 21. */
TEXT caml_plan9_sys_pipe(SB), 1, $0
	MOVQ RARG, a0+0(FP)
	MOVQ $21, RARG
	SYSCALL
	RET

/* MIT 9front 2191d72205863d2c53ea6ac36991cb4c13204c7c;
   sys/src/libc/9syscall/sys.h:42: ERRSTR = 41. */
TEXT caml_plan9_sys_errstr(SB), 1, $0
	MOVQ RARG, a0+0(FP)
	MOVQ $41, RARG
	SYSCALL
	RET

/* MIT 9front 2191d72205863d2c53ea6ac36991cb4c13204c7c;
   sys/src/libc/9syscall/sys.h:49: PREAD = 50. */
TEXT caml_plan9_sys_pread(SB), 1, $0
	MOVQ RARG, a0+0(FP)
	MOVQ $50, RARG
	SYSCALL
	RET

/* MIT 9front 2191d72205863d2c53ea6ac36991cb4c13204c7c;
   sys/src/libc/9syscall/sys.h:50: PWRITE = 51. */
TEXT caml_plan9_sys_pwrite(SB), 1, $0
	MOVQ RARG, a0+0(FP)
	MOVQ $51, RARG
	SYSCALL
	RET
