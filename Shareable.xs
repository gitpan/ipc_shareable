#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

#include <sys/shm.h>
#include <sys/sem.h>
#include <sys/ipc.h>

static int
not_here(s)
     char *s;
{
  croak("%s not implemented on this architecture", s);
  return -1;
}

static double
constant(name, arg)
     char *name;
     int arg;
{
  errno = 0;
  switch (*name) {
  case 'A':
    break;
  case 'B':
    break;
  case 'C':
    break;
  case 'D':
    break;
  case 'E':
    break;
  case 'F':
    break;
  case 'G':
    if (strEQ(name, "GETALL"))
#ifdef GETALL
      return GETALL;
#else
    goto not_there;
#endif
    if (strEQ(name, "GETNCNT"))
#ifdef GETNCNT
      return GETNCNT;
#else
    goto not_there;
#endif
    if (strEQ(name, "GETPID"))
#ifdef GETPID
      return GETPID;
#else
    goto not_there;
#endif
    if (strEQ(name, "GETVAL"))
#ifdef GETVAL
      return GETVAL;
#else
    goto not_there;
#endif
    if (strEQ(name, "GETZCNT"))
#ifdef GETZCNT
      return GETZCNT;
#else
    goto not_there;
#endif
    break;
  case 'H':
    break;
  case 'I':
    if (strEQ(name, "IPC_ALLOC"))
#ifdef IPC_ALLOC
      return IPC_ALLOC;
#else
    goto not_there;
#endif
    if (strEQ(name, "IPC_CREAT"))
#ifdef IPC_CREAT
      return IPC_CREAT;
#else
    goto not_there;
#endif
    if (strEQ(name, "IPC_EXCL"))
#ifdef IPC_EXCL
      return IPC_EXCL;
#else
    goto not_there;
#endif
    if (strEQ(name, "IPC_NOWAIT"))
#ifdef IPC_NOWAIT
      return IPC_NOWAIT;
#else
    goto not_there;
#endif
    if (strEQ(name, "IPC_O_RMID"))
#ifdef IPC_O_RMID
      return IPC_O_RMID;
#else
    goto not_there;
#endif
    if (strEQ(name, "IPC_O_SET"))
#ifdef IPC_O_SET
      return IPC_O_SET;
#else
    goto not_there;
#endif
    if (strEQ(name, "IPC_O_STAT"))
#ifdef IPC_O_STAT
      return IPC_O_STAT;
#else
    goto not_there;
#endif
    if (strEQ(name, "IPC_PRIVATE"))
#ifdef IPC_PRIVATE
      return IPC_PRIVATE;
#else
    goto not_there;
#endif
    if (strEQ(name, "IPC_RMID"))
#ifdef IPC_RMID
      return IPC_RMID;
#else
    goto not_there;
#endif
    if (strEQ(name, "IPC_SET"))
#ifdef IPC_SET
      return IPC_SET;
#else
    goto not_there;
#endif
    if (strEQ(name, "IPC_STAT"))
#ifdef IPC_STAT
      return IPC_STAT;
#else
    goto not_there;
#endif
    break;
  case 'J':
    break;
  case 'K':
    break;
  case 'L':
    break;
  case 'M':
    break;
  case 'N':
    break;
  case 'O':
    break;
  case 'P':
    break;
  case 'Q':
    break;
  case 'R':
    break;
  case 'S':
    if (strEQ(name, "SEM_A"))
#ifdef SEM_A
      return SEM_A;
#else
    goto not_there;
#endif
    if (strEQ(name, "SEM_R"))
#ifdef SEM_R
      return SEM_R;
#else
    goto not_there;
#endif
    if (strEQ(name, "SEM_UNDO"))
#ifdef SEM_UNDO
      return SEM_UNDO;
#else
    goto not_there;
#endif
    if (strEQ(name, "SETALL"))
#ifdef SETALL
      return SETALL;
#else
    goto not_there;
#endif
    if (strEQ(name, "SETVAL"))
#ifdef SETVAL
      return SETVAL;
#else
    goto not_there;
#endif
    if (strEQ(name, "SHM_LOCK"))
#ifdef SHM_LOCK
      return SHM_LOCK;
#else
    goto not_there;
#endif
    if (strEQ(name, "SHM_R"))
#ifdef SHM_R
      return SHM_R;
#else
    goto not_there;
#endif
    if (strEQ(name, "SHM_RDONLY"))
#ifdef SHM_RDONLY
      return SHM_RDONLY;
#else
    goto not_there;
#endif
    if (strEQ(name, "SHM_RND"))
#ifdef SHM_RND
      return SHM_RND;
#else
    goto not_there;
#endif
    if (strEQ(name, "SHM_SHARE_MMU"))
#ifdef SHM_SHARE_MMU
      return SHM_SHARE_MMU;
#else
    goto not_there;
#endif
    if (strEQ(name, "SHM_UNLOCK"))
#ifdef SHM_UNLOCK
      return SHM_UNLOCK;
#else
    goto not_there;
#endif
    if (strEQ(name, "SHM_W"))
#ifdef SHM_W
      return SHM_W;
#else
    goto not_there;
#endif
    break;
  case 'T':
    break;
  case 'U':
    break;
  case 'V':
    break;
  case 'W':
    break;
  case 'X':
    break;
  case 'Y':
    break;
  case 'Z':
    break;
  }
  errno = EINVAL;
  return 0;
  
 not_there:
  errno = ENOENT;
  return 0;
}


MODULE = IPC::Shareable		PACKAGE = IPC::Shareable		


double
constant(name,arg)
     char *		name
     int		arg
