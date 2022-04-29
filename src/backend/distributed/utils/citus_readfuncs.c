/*-------------------------------------------------------------------------
 *
 * citus_readfuncs.c
 *    Citus specific node functions
 *
 * Portions Copyright (c) 1996-2014, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 * Portions Copyright (c) Citus Data, Inc.
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "distributed/citus_nodefuncs.h"

#include <assert.h>
#undef pg_unreachable
#define pg_unreachable() assert(0)

void
ReadUnsupportedCitusNode(READFUNC_ARGS)
{
	ereport(ERROR, (errmsg("not implemented")));
}
