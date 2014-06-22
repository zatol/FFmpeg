;******************************************************************************
;* MMX optimized DSP utils
;* Copyright (c) 2008 Loren Merritt
;* Copyright (c) 2003-2013 Michael Niedermayer
;* Copyright (c) 2013 Daniel Kang
;*
;* This file is part of FFmpeg.
;*
;* FFmpeg is free software; you can redistribute it and/or
;* modify it under the terms of the GNU Lesser General Public
;* License as published by the Free Software Foundation; either
;* version 2.1 of the License, or (at your option) any later version.
;*
;* FFmpeg is distributed in the hope that it will be useful,
;* but WITHOUT ANY WARRANTY; without even the implied warranty of
;* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;* Lesser General Public License for more details.
;*
;* You should have received a copy of the GNU Lesser General Public
;* License along with FFmpeg; if not, write to the Free Software
;* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
;******************************************************************************

%include "libavutil/x86/x86util.asm"

SECTION_RODATA
pb_bswap32: db 3, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12

cextern pb_80

SECTION_TEXT

; %1 = aligned/unaligned
%macro BSWAP_LOOPS  1
    mov      r3, r2
    sar      r2, 3
    jz       .left4_%1
.loop8_%1:
    mov%1    m0, [r1 +  0]
    mov%1    m1, [r1 + 16]
%if cpuflag(ssse3)
    pshufb   m0, m2
    pshufb   m1, m2
    mov%1    [r0 +  0], m0
    mov%1    [r0 + 16], m1
%else
    pshuflw  m0, m0, 10110001b
    pshuflw  m1, m1, 10110001b
    pshufhw  m0, m0, 10110001b
    pshufhw  m1, m1, 10110001b
    mova     m2, m0
    mova     m3, m1
    psllw    m0, 8
    psllw    m1, 8
    psrlw    m2, 8
    psrlw    m3, 8
    por      m2, m0
    por      m3, m1
    mov%1    [r0 +  0], m2
    mov%1    [r0 + 16], m3
%endif
    add      r0, 32
    add      r1, 32
    dec      r2
    jnz      .loop8_%1
.left4_%1:
    mov      r2, r3
    and      r3, 4
    jz       .left
    mov%1    m0, [r1]
%if cpuflag(ssse3)
    pshufb   m0, m2
    mov%1    [r0], m0
%else
    pshuflw  m0, m0, 10110001b
    pshufhw  m0, m0, 10110001b
    mova     m2, m0
    psllw    m0, 8
    psrlw    m2, 8
    por      m2, m0
    mov%1    [r0], m2
%endif
    add      r1, 16
    add      r0, 16
%endmacro

; void ff_bswap_buf(uint32_t *dst, const uint32_t *src, int w);
%macro BSWAP32_BUF 0
%if cpuflag(ssse3)
cglobal bswap32_buf, 3,4,3
    mov      r3, r1
    mova     m2, [pb_bswap32]
%else
cglobal bswap32_buf, 3,4,5
    mov      r3, r1
%endif
    or       r3, r0
    and      r3, 15
    jz       .start_align
    BSWAP_LOOPS  u
    jmp      .left
.start_align:
    BSWAP_LOOPS  a
.left:
%if cpuflag(ssse3)
    mov      r3, r2
    and      r2, 2
    jz       .left1
    movq     m0, [r1]
    pshufb   m0, m2
    movq     [r0], m0
    add      r1, 8
    add      r0, 8
.left1:
    and      r3, 1
    jz       .end
    mov      r2d, [r1]
    bswap    r2d
    mov      [r0], r2d
%else
    and      r2, 3
    jz       .end
.loop2:
    mov      r3d, [r1]
    bswap    r3d
    mov      [r0], r3d
    add      r1, 4
    add      r0, 4
    dec      r2
    jnz      .loop2
%endif
.end:
    RET
%endmacro

INIT_XMM sse2
BSWAP32_BUF

INIT_XMM ssse3
BSWAP32_BUF

;--------------------------------------------------------------------------
;void ff_put_signed_pixels_clamped(const int16_t *block, uint8_t *pixels,
;                                  int line_size)
;--------------------------------------------------------------------------

%macro PUT_SIGNED_PIXELS_CLAMPED_HALF 1
    mova     m1, [blockq+mmsize*0+%1]
    mova     m2, [blockq+mmsize*2+%1]
%if mmsize == 8
    mova     m3, [blockq+mmsize*4+%1]
    mova     m4, [blockq+mmsize*6+%1]
%endif
    packsswb m1, [blockq+mmsize*1+%1]
    packsswb m2, [blockq+mmsize*3+%1]
%if mmsize == 8
    packsswb m3, [blockq+mmsize*5+%1]
    packsswb m4, [blockq+mmsize*7+%1]
%endif
    paddb    m1, m0
    paddb    m2, m0
%if mmsize == 8
    paddb    m3, m0
    paddb    m4, m0
    movq     [pixelsq+lsizeq*0], m1
    movq     [pixelsq+lsizeq*1], m2
    movq     [pixelsq+lsizeq*2], m3
    movq     [pixelsq+lsize3q ], m4
%else
    movq     [pixelsq+lsizeq*0], m1
    movhps   [pixelsq+lsizeq*1], m1
    movq     [pixelsq+lsizeq*2], m2
    movhps   [pixelsq+lsize3q ], m2
%endif
%endmacro

%macro PUT_SIGNED_PIXELS_CLAMPED 1
cglobal put_signed_pixels_clamped, 3, 4, %1, block, pixels, lsize, lsize3
    mova     m0, [pb_80]
    lea      lsize3q, [lsizeq*3]
    PUT_SIGNED_PIXELS_CLAMPED_HALF 0
    lea      pixelsq, [pixelsq+lsizeq*4]
    PUT_SIGNED_PIXELS_CLAMPED_HALF 64
    RET
%endmacro

INIT_MMX mmx
PUT_SIGNED_PIXELS_CLAMPED 0
INIT_XMM sse2
PUT_SIGNED_PIXELS_CLAMPED 3

;-----------------------------------------------------
;void ff_vector_clipf(float *dst, const float *src,
;                     float min, float max, int len)
;-----------------------------------------------------
INIT_XMM sse
%if UNIX64
cglobal vector_clipf, 3,3,6, dst, src, len
%else
cglobal vector_clipf, 5,5,6, dst, src, min, max, len
%endif
%if WIN64
    SWAP 0, 2
    SWAP 1, 3
%elif ARCH_X86_32
    movss   m0, minm
    movss   m1, maxm
%endif
    SPLATD  m0
    SPLATD  m1
        shl lend, 2
        add srcq, lenq
        add dstq, lenq
        neg lenq
.loop:
    mova    m2,  [srcq+lenq+mmsize*0]
    mova    m3,  [srcq+lenq+mmsize*1]
    mova    m4,  [srcq+lenq+mmsize*2]
    mova    m5,  [srcq+lenq+mmsize*3]
    maxps   m2, m0
    maxps   m3, m0
    maxps   m4, m0
    maxps   m5, m0
    minps   m2, m1
    minps   m3, m1
    minps   m4, m1
    minps   m5, m1
    mova    [dstq+lenq+mmsize*0], m2
    mova    [dstq+lenq+mmsize*1], m3
    mova    [dstq+lenq+mmsize*2], m4
    mova    [dstq+lenq+mmsize*3], m5
    add     lenq, mmsize*4
    jl .loop
    REP_RET
