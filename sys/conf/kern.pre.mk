# $FreeBSD$

# Part of a unified Makefile for building kernels.  This part contains all
# of the definitions that need to be before %BEFORE_DEPEND.

# Allow user to configure things that only effect src tree builds.
# Note: This is duplicated from src.sys.mk to ensure that we include
# /etc/src.conf when building the kernel. Kernels can be built without
# the rest of /usr/src, but they still always process SRCCONF even though
# the normal mechanisms to prevent that (compiling out of tree) won't
# work. To ensure they do work, we have to duplicate thee few lines here.
SRCCONF?=	/etc/src.conf
.if (exists(${SRCCONF}) || ${SRCCONF} != "/etc/src.conf") && !target(_srcconf_included_)
.include "${SRCCONF}"
_srcconf_included_:
.endif

.include <bsd.own.mk>
.include <bsd.compiler.mk>
.include "kern.opts.mk"

# Can be overridden by makeoptions or /etc/make.conf
KERNEL_KO?=	kernel
KERNEL?=	kernel
KODIR?=		/boot/${KERNEL}
LDSCRIPT_NAME?=	ldscript.$M
LDSCRIPT?=	$S/conf/${LDSCRIPT_NAME}

M=		${MACHINE}

AWK?=		awk
CP?=		cp
LINT?=		lint
NM?=		nm
OBJCOPY?=	objcopy
SIZE?=		size

.if defined(DEBUG)
_MINUS_O=	-O
CTFFLAGS+=	-g
.else
.if ${MACHINE_CPUARCH} == "powerpc"
_MINUS_O=	-O	# gcc miscompiles some code at -O2
.else
_MINUS_O=	-O2
.endif
.endif
.if ${MACHINE_CPUARCH} == "amd64"
.if ${COMPILER_TYPE} == "clang"
COPTFLAGS?=-O2 -pipe
.else
COPTFLAGS?=-O2 -frename-registers -pipe
.endif
.else
COPTFLAGS?=${_MINUS_O} -pipe
.endif
.if !empty(COPTFLAGS:M-O[23s]) && empty(COPTFLAGS:M-fno-strict-aliasing)
COPTFLAGS+= -fno-strict-aliasing
.endif
.if !defined(NO_CPU_COPTFLAGS)
COPTFLAGS+= ${_CPUCFLAGS}
.endif
NOSTDINC= -nostdinc

INCLUDES= ${NOSTDINC} ${INCLMAGIC} -I. -I$S

.if make(depend) || make(kernel-depend)

# This hack lets us use the ipfilter code without spamming a new
# include path into contrib'ed source files.
INCLUDES+= -I$S/contrib/ipfilter

# ... and the same for ath
INCLUDES+= -I$S/dev/ath -I$S/dev/ath/ath_hal -I$S/contrib/dev/ath/ath_hal

# ... and the same for the NgATM stuff
INCLUDES+= -I$S/contrib/ngatm

# ... and the same for vchiq
INCLUDES+= -I$S/contrib/vchiq

# ... and the same for twa
INCLUDES+= -I$S/dev/twa

# ... and the same for cxgb and cxgbe
INCLUDES+= -I$S/dev/cxgb -I$S/dev/cxgbe

.endif

CFLAGS=	${COPTFLAGS} ${DEBUG}
CFLAGS+= ${INCLUDES} -D_KERNEL -DHAVE_KERNEL_OPTION_HEADERS -include opt_global.h
CFLAGS_PARAM_INLINE_UNIT_GROWTH?=100
CFLAGS_PARAM_LARGE_FUNCTION_GROWTH?=1000
.if ${MACHINE_CPUARCH} == "mips"
CFLAGS_ARCH_PARAMS?=--param max-inline-insns-single=1000
.endif
CFLAGS.gcc+= -fno-common -fms-extensions -finline-limit=${INLINE_LIMIT}
CFLAGS.gcc+= --param inline-unit-growth=${CFLAGS_PARAM_INLINE_UNIT_GROWTH}
CFLAGS.gcc+= --param large-function-growth=${CFLAGS_PARAM_LARGE_FUNCTION_GROWTH}
.if defined(CFLAGS_ARCH_PARAMS)
CFLAGS.gcc+=${CFLAGS_ARCH_PARAMS}
.endif
WERROR?= -Werror

# XXX LOCORE means "don't declare C stuff" not "for locore.s".
ASM_CFLAGS= -x assembler-with-cpp -DLOCORE ${CFLAGS} ${ASM_CFLAGS.${.IMPSRC:T}} 

.if defined(PROFLEVEL) && ${PROFLEVEL} >= 1
CFLAGS+=	-DGPROF
CFLAGS.gcc+=	-falign-functions=16
.if ${PROFLEVEL} >= 2
CFLAGS+=	-DGPROF4 -DGUPROF
PROF=		-pg
.if ${COMPILER_TYPE} == "gcc"
PROF+=		-mprofiler-epilogue
.endif
.else
PROF=		-pg
.endif
.endif
DEFINED_PROF=	${PROF}

# Put configuration-specific C flags last (except for ${PROF}) so that they
# can override the others.
CFLAGS+=	${CONF_CFLAGS}

# Optional linting. This can be overridden in /etc/make.conf.
LINTFLAGS=	${LINTOBJKERNFLAGS}

NORMAL_C= ${CC} -c ${CFLAGS} ${WERROR} ${PROF} ${.IMPSRC}
NORMAL_S= ${CC} -c ${ASM_CFLAGS} ${WERROR} ${.IMPSRC}
PROFILE_C= ${CC} -c ${CFLAGS} ${WERROR} ${.IMPSRC}
NORMAL_C_NOWERROR= ${CC} -c ${CFLAGS} ${PROF} ${.IMPSRC}

NORMAL_M= ${AWK} -f $S/tools/makeobjops.awk ${.IMPSRC} -c ; \
	  ${CC} -c ${CFLAGS} ${WERROR} ${PROF} ${.PREFIX}.c

NORMAL_FW= uudecode -o ${.TARGET} ${.ALLSRC}
NORMAL_FWO= ${LD} -b binary --no-warn-mismatch -d -warn-common -r \
	-o ${.TARGET} ${.ALLSRC:M*.fw}

# Common for dtrace / zfs
CDDL_CFLAGS=	-DFREEBSD_NAMECACHE -nostdinc -I$S/cddl/compat/opensolaris -I$S/cddl/contrib/opensolaris/uts/common -I$S -I$S/cddl/contrib/opensolaris/common ${CFLAGS} -Wno-unknown-pragmas -Wno-missing-prototypes -Wno-undef -Wno-strict-prototypes -Wno-cast-qual -Wno-parentheses -Wno-redundant-decls -Wno-missing-braces -Wno-uninitialized -Wno-unused -Wno-inline -Wno-switch -Wno-pointer-arith -Wno-unknown-pragmas
CDDL_CFLAGS+=	-include $S/cddl/compat/opensolaris/sys/debug_compat.h
CDDL_C=		${CC} -c ${CDDL_CFLAGS} ${WERROR} ${PROF} ${.IMPSRC}

# Special flags for managing the compat compiles for ZFS
ZFS_CFLAGS=	-DBUILDING_ZFS -I$S/cddl/contrib/opensolaris/uts/common/fs/zfs -I$S/cddl/contrib/opensolaris/uts/common/zmod -I$S/cddl/contrib/opensolaris/common/zfs ${CDDL_CFLAGS}
ZFS_ASM_CFLAGS= -x assembler-with-cpp -DLOCORE ${ZFS_CFLAGS}
ZFS_C=		${CC} -c ${ZFS_CFLAGS} ${WERROR} ${PROF} ${.IMPSRC}
ZFS_S=		${CC} -c ${ZFS_ASM_CFLAGS} ${WERROR} ${.IMPSRC}



MACH_FLAGS= -I$S../include/apple -I$S/sys
MACH_C = ${NORMAL_C} ${MACH_FLAGS}

# Special flags for managing the compat compiles for DTrace
DTRACE_CFLAGS=	-DBUILDING_DTRACE ${CDDL_CFLAGS} -I$S/cddl/dev/dtrace -I$S/cddl/dev/dtrace/${MACHINE_CPUARCH}
.if ${MACHINE_CPUARCH} == "amd64" || ${MACHINE_CPUARCH} == "i386"
DTRACE_CFLAGS+=	-I$S/cddl/contrib/opensolaris/uts/intel -I$S/cddl/dev/dtrace/x86
.endif
DTRACE_CFLAGS+=	-I$S/cddl/contrib/opensolaris/common/util -I$S -DDIS_MEM -DSMP
DTRACE_ASM_CFLAGS=	-x assembler-with-cpp -DLOCORE ${DTRACE_CFLAGS}
DTRACE_C=	${CC} -c ${DTRACE_CFLAGS} ${CDDL_CFLAGS}	${WERROR} ${PROF} ${.IMPSRC}
DTRACE_S=	${CC} -c ${DTRACE_ASM_CFLAGS} ${CDDL_CFLAGS}	${WERROR} ${.IMPSRC}

# Special flags for managing the compat compiles for DTrace/FBT
FBT_CFLAGS=	-DBUILDING_DTRACE -nostdinc -I$S/cddl/dev/fbt/${MACHINE_CPUARCH} -I$S/cddl/dev/fbt -I$S/cddl/compat/opensolaris -I$S/cddl/contrib/opensolaris/uts/common -I$S ${CDDL_CFLAGS}
.if ${MACHINE_CPUARCH} == "amd64" || ${MACHINE_CPUARCH} == "i386"
FBT_CFLAGS+=	-I$S/cddl/dev/fbt/x86
.endif
FBT_C=		${CC} -c ${FBT_CFLAGS} ${CDDL_CFLAGS}		${WERROR} ${PROF} ${.IMPSRC}

.if ${MK_CTF} != "no"
NORMAL_CTFCONVERT=	${CTFCONVERT} ${CTFFLAGS} ${.TARGET}
.elif ${MAKE_VERSION} >= 5201111300
NORMAL_CTFCONVERT=
.else
NORMAL_CTFCONVERT=	@:
.endif

NORMAL_LINT=	${LINT} ${LINTFLAGS} ${CFLAGS:M-[DIU]*} ${.IMPSRC}

# Linux Kernel Programming Interface C-flags
LINUXKPI_INCLUDES=	-I$S/compat/linuxkpi/common/include
LINUXKPI_C=		${NORMAL_C} ${LINUXKPI_INCLUDES}

# Infiniband C flags.  Correct include paths and omit errors that linux
# does not honor.
OFEDINCLUDES=	-I$S/ofed/include ${LINUXKPI_INCLUDES}
OFEDNOERR=	-Wno-cast-qual -Wno-pointer-arith
OFEDCFLAGS=	${CFLAGS:N-I*} ${OFEDINCLUDES} ${CFLAGS:M-I*} ${OFEDNOERR}
OFED_C_NOIMP=	${CC} -c -o ${.TARGET} ${OFEDCFLAGS} ${WERROR} ${PROF}
OFED_C=		${OFED_C_NOIMP} ${.IMPSRC}

GEN_CFILES= $S/$M/$M/genassym.c ${MFILES:T:S/.m$/.c/}
SYSTEM_CFILES= config.c env.c hints.c vnode_if.c
SYSTEM_DEP= Makefile ${SYSTEM_OBJS}
SYSTEM_OBJS= locore.o ${MDOBJS} ${OBJS}
SYSTEM_OBJS+= ${SYSTEM_CFILES:.c=.o}
SYSTEM_OBJS+= hack.So
.if ${MFS_IMAGE:Uno} != "no"
SYSTEM_OBJS+= embedfs_${MFS_IMAGE:T:R}.o
.endif
SYSTEM_LD= @${LD} -Bdynamic -T ${LDSCRIPT} ${_LDFLAGS} --no-warn-mismatch \
	--warn-common --export-dynamic --dynamic-linker /red/herring \
	-o ${.TARGET} -X ${SYSTEM_OBJS} vers.o
SYSTEM_LD_TAIL= @${OBJCOPY} --strip-symbol gcc2_compiled. ${.TARGET} ; \
	${SIZE} ${.TARGET} ; chmod 755 ${.TARGET}
SYSTEM_DEP+= ${LDSCRIPT}

# Calculate path for .m files early, if needed.
.if !defined(_MPATH)
__MPATH!=find ${S:tA}/ -name \*_if.m
_MPATH=${__MPATH:H:O:u}
.endif

# MKMODULESENV is set here so that port makefiles can augment
# them.

MKMODULESENV+=	MAKEOBJDIRPREFIX=${.OBJDIR}/modules KMODDIR=${KODIR}
MKMODULESENV+=	MACHINE_CPUARCH=${MACHINE_CPUARCH}
MKMODULESENV+=	MACHINE=${MACHINE} MACHINE_ARCH=${MACHINE_ARCH}
MKMODULESENV+=	MODULES_EXTRA="${MODULES_EXTRA}" WITHOUT_MODULES="${WITHOUT_MODULES}"
.if (${KERN_IDENT} == LINT)
MKMODULESENV+=	ALL_MODULES=LINT
.endif
.if defined(MODULES_OVERRIDE)
MKMODULESENV+=	MODULES_OVERRIDE="${MODULES_OVERRIDE}"
.endif
.if defined(DEBUG)
MKMODULESENV+=	DEBUG_FLAGS="${DEBUG}"
.endif
MKMODULESENV+=	_MPATH="${_MPATH}"

# Architecture and output format arguments for objdump to convert image to
# object file
.if ${MFS_IMAGE:Uno} != "no"

.if !defined(EMBEDFS_FORMAT.${MACHINE_ARCH})
EMBEDFS_FORMAT.${MACHINE_ARCH}!= awk -F'"' '/OUTPUT_FORMAT/ {print $$2}' ${LDSCRIPT}
.if empty(EMBEDFS_FORMAT.${MACHINE_ARCH})
.undef EMBEDFS_FORMAT.${MACHINE_ARCH}
.endif
.endif

.if !defined(EMBEDFS_ARCH.${MACHINE_ARCH})
EMBEDFS_ARCH.${MACHINE_ARCH}!= sed -n '/OUTPUT_ARCH/s/.*(\(.*\)).*/\1/p' ${LDSCRIPT}
.if empty(EMBEDFS_ARCH.${MACHINE_ARCH})
.undef EMBEDFS_ARCH.${MACHINE_ARCH}
.endif
.endif

EMBEDFS_FORMAT.arm?=		elf32-littlearm
EMBEDFS_FORMAT.armv6?=		elf32-littlearm
EMBEDFS_FORMAT.mips?=		elf32-tradbigmips
EMBEDFS_FORMAT.mipsel?=		elf32-tradlittlemips
EMBEDFS_FORMAT.mips64?=		elf64-tradbigmips
EMBEDFS_FORMAT.mips64el?=	elf64-tradlittlemips
.endif

# Detect kernel config options that force stack frames to be turned on.
DDB_ENABLED!=	grep DDB opt_ddb.h || true ; echo
DTR_ENABLED!=	grep KDTRACE_FRAME opt_kdtrace.h || true ; echo
HWPMC_ENABLED!=	grep HWPMC opt_hwpmc_hooks.h || true ; echo
