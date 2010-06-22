#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

struct trampoline_ud {
    UV uplevel;
    SV *cb;
};

struct uplevel_entersub {
    UNOP op;
    struct trampoline_ud ud;
    PERL_CONTEXT *cx;
    OP *retop;
};

STATIC void setup_trampoline (pTHX_ UV, SV *);

/* Originally stolen from pp_ctl.c; now significantly different */

STATIC I32
dopoptosub_at(pTHX_ PERL_CONTEXT *cxstk, I32 startingblock)
{
    dTHR;
    I32 i;
    PERL_CONTEXT *cx;
    for (i = startingblock; i >= 0; i--) {
        cx = &cxstk[i];
        switch (CxTYPE(cx)) {
        default:
            continue;
        case CXt_SUB:
        /* In Perl 5.005, formats just used CXt_SUB */
#ifdef CXt_FORMAT
       case CXt_FORMAT:
#endif
            return i;
        }
    }
    return i;
}

STATIC I32
dopoptosub(pTHX_ I32 startingblock)
{
    dTHR;
    return dopoptosub_at(aTHX_ cxstack, startingblock);
}

/* This function is based on the code of pp_caller */
STATIC PERL_CONTEXT*
upcontext(pTHX_ I32 count, COP **cop_p, PERL_CONTEXT **ccstack_p,
                                I32 *cxix_from_p, I32 *cxix_to_p)
{
    PERL_SI *top_si = PL_curstackinfo;
    I32 cxix = dopoptosub(aTHX_ cxstack_ix);
    PERL_CONTEXT *ccstack = cxstack;

    if (cxix_from_p) *cxix_from_p = cxstack_ix+1;
    if (cxix_to_p)   *cxix_to_p   = cxix;
    for (;;) {
        /* we may be in a higher stacklevel, so dig down deeper */
        while (cxix < 0 && top_si->si_type != PERLSI_MAIN) {
            top_si  = top_si->si_prev;
            ccstack = top_si->si_cxstack;
            cxix = dopoptosub_at(aTHX_ ccstack, top_si->si_cxix);
                        if (cxix_to_p && cxix_from_p) *cxix_from_p = *cxix_to_p;
                        if (cxix_to_p) *cxix_to_p = cxix;
        }
        if (cxix < 0 && count == 0) {
                    if (ccstack_p) *ccstack_p = ccstack;
            return (PERL_CONTEXT *)0;
                }
        else if (cxix < 0)
            return (PERL_CONTEXT *)-1;
        if (PL_DBsub && cxix >= 0 &&
                ccstack[cxix].blk_sub.cv == GvCV(PL_DBsub))
            count++;
        if (!count--)
            break;

        if (cop_p) *cop_p = ccstack[cxix].blk_oldcop;
        cxix = dopoptosub_at(aTHX_ ccstack, cxix - 1);
                        if (cxix_to_p && cxix_from_p) *cxix_from_p = *cxix_to_p;
                        if (cxix_to_p) *cxix_to_p = cxix;
    }
    if (ccstack_p) *ccstack_p = ccstack;
    return &ccstack[cxix];
}

STATIC OP *
invoke_cb (pTHX)
{
    OP *ret;
    struct uplevel_entersub *op = (struct uplevel_entersub *)PL_op;

    if (op->ud.uplevel == 0) {
        dSP;
        PUSHMARK(SP);
        PUTBACK;
        warn("exec");
        call_sv(op->ud.cb, G_VOID | G_DISCARD);
        PUTBACK;
        FREETMPS;
        LEAVE;
        SvREFCNT_dec(op->ud.cb);
//        op->cx->blk_sub.retop = op->retop;
    }
    else {
        setup_trampoline(aTHX_ --op->ud.uplevel, op->ud.cb);
    }

    ret = op->op.op_next;
    //op->cx->blk_sub.retop = op->retop;
    //Safefree(op);
    return ret;
}

STATIC void
trampoline_cb (pTHX_ void *_ud)
{
    struct uplevel_entersub *trampoline_op;
    PERL_CONTEXT *cx;
    OP *fake_op;
    struct trampoline_ud *ud = (struct trampoline_ud *)_ud;

    cx = upcontext(aTHX_ ud->uplevel, 0, 0, 0, 0);
    if (!cx || cx == (PERL_CONTEXT *)-1) {
        croak("failed to find context");
    }

    if (!(cx->cx_type & CXt_SUB)) {
        croak("cx_type is %d, not CXt_SUB", cx->cx_type);
    }

    if (ud->uplevel == 0) {
        warn("nao");
        Newxz(fake_op, 1, OP);
        fake_op->op_next = PL_op->op_next;
        PL_op = PL_op->op_next;
    }
    else {
        Newxz(trampoline_op, 1, struct uplevel_entersub);
        trampoline_op->op.op_type = OP_ENTERSUB;
        trampoline_op->op.op_next = PL_op->op_next;
        trampoline_op->op.op_ppaddr = invoke_cb;
        trampoline_op->ud.uplevel = ud->uplevel;
        trampoline_op->ud.cb = ud->cb;
        trampoline_op->cx = cx;
        trampoline_op->retop = cx->blk_sub.retop;

        Newxz(fake_op, 1, OP); /* leak */
        fake_op->op_next = (OP *)trampoline_op;

        PL_op = fake_op;
        cx->blk_sub.retop = fake_op->op_next;
    }

    Safefree(ud);
}

STATIC void
setup_trampoline (pTHX_ UV uplevel, SV *cb)
{
    struct trampoline_ud *ud;

    warn("setup %u", uplevel);

    Newx(ud, 1, struct trampoline_ud);
    ud->uplevel = uplevel;
    ud->cb = cb;

    SAVEDESTRUCTOR_X(trampoline_cb, ud);
}

MODULE = Guard::Uplevel  PACKAGE = Guard::Uplevel

PROTOTYPES: disable

void
scope_guard (uplevel, cb)
        UV uplevel
        SV *cb
    PPCODE:
        setup_trampoline(aTHX_ uplevel, newSVsv(cb));
