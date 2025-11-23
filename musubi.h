#ifndef musubi_h
#define musubi_h 1

#ifndef MU_NS_BEGIN
#ifdef __cplusplus
#define MU_NS_BEGIN extern "C" {
#define MU_NS_END   }
#else
#define MU_NS_BEGIN
#define MU_NS_END
#endif
#endif /* MU_NS_BEGIN */

#ifndef MU_STATIC
#if __GNUC__
#define MU_STATIC static __attribute((unused))
#else
#define MU_STATIC static
#endif
#endif

#ifdef MU_STATIC_API
#ifndef MU_IMPLEMENTATION
#define MU_IMPLEMENTATION
#endif
#define MU_API MU_STATIC
#endif

#if !defined(MU_API) && defined(_WIN32)
#ifdef MU_IMPLEMENTATION
#define MU_API __declspec(dllexport)
#else
#define MU_API __declspec(dllimport)
#endif
#endif

#ifndef MU_API
#define MU_API extern
#endif

#include <stddef.h>

#if !MU_NO_STDIO
#include <stdio.h>
#endif /* !MU_NO_STDIO */

#define MU_CHUNK_MAX_SIZE  63
#define MU_COLOR_CODE_SIZE 32

#define MU_OK     0  /* No error */
#define MU_ERRSRC -1 /* source ID out of range */

MU_NS_BEGIN

typedef enum mu_Kind { MU_KIND_ERROR, MU_KIND_WARNING, MU_KIND_CUSTOM } mu_Kind;

typedef enum mu_IndexType { MU_INDEX_BYTE, MU_INDEX_CHAR } mu_IndexType;

typedef enum mu_LabelAttach {
    MU_ATTACH_MIDDLE,
    MU_ATTACH_START,
    MU_ATTACH_END
} mu_LabelAttach;

typedef enum mu_ColorKind {
    MU_COLOR_RESET,
    MU_COLOR_ERROR,
    MU_COLOR_WARNING,
    MU_COLOR_KIND,
    MU_COLOR_MARGIN,
    MU_COLOR_SKIPPED_MARGIN,
    MU_COLOR_UNIMPORTANT,
    MU_COLOR_NOTE,
    MU_COLOR_LABEL
} mu_ColorKind;

typedef enum mu_CharSet {
    MU_DRAW_SPACE,
    MU_DRAW_NEWLINE,
    MU_DRAW_COLON,
    MU_DRAW_HBAR,
    MU_DRAW_VBAR,
    MU_DRAW_XBAR,
    MU_DRAW_VBAR_BREAK,
    MU_DRAW_VBAR_GAP,
    MU_DRAW_UARROW,
    MU_DRAW_RARROW,
    MU_DRAW_LTOP,
    MU_DRAW_MTOP,
    MU_DRAW_RTOP,
    MU_DRAW_LBOT,
    MU_DRAW_MBOT,
    MU_DRAW_RBOT,
    MU_DRAW_LBOX,
    MU_DRAW_RBOX,
    MU_DRAW_LCROSS,
    MU_DRAW_RCROSS,
    MU_DRAW_UNDERBAR,
    MU_DRAW_UNDERLINE,
    MU_DRAW_ELLIPSIS,
    MU_DRAW_COUNT
} mu_CharSet;

typedef unsigned mu_Id;
typedef const char *mu_Chunk; /* first char is length */

typedef struct mu_Report mu_Report;
typedef struct mu_Config mu_Config;
typedef struct mu_ColorGen mu_ColorGen;
typedef struct mu_Source mu_Source;
typedef struct mu_Line mu_Line;
typedef struct mu_Slice mu_Slice;

typedef void *mu_Allocf(void *ud, void *p, size_t nsize, size_t osize);
typedef mu_Chunk mu_Color(void *ud, mu_ColorKind kind);
typedef int mu_Writer(void *ud, const char *data, size_t len);

/* report construction and configuration */

MU_API mu_Report *mu_new(mu_Allocf *allocf, void *ud);
MU_API void mu_reset(mu_Report *R);
MU_API void mu_delete(mu_Report *R);

MU_API int mu_config(mu_Report *R, mu_Config *config);
MU_API int mu_label(mu_Report *R, int start_pos, int end_pos, mu_Id src_id);
MU_API int mu_message(mu_Report *R, const char *msg, int width);
MU_API int mu_color(mu_Report *R, mu_Color *color, void *ud);
MU_API int mu_order(mu_Report *R, int order);
MU_API int mu_priority(mu_Report *R, int priority);

MU_API int mu_help(mu_Report *R, const char *help_msg);
MU_API int mu_note(mu_Report *R, const char *note_msg);

/* rendering */

MU_API int mu_writer(mu_Report *R, mu_Writer *writer, void *ud);
MU_API int mu_kind(mu_Report *R, mu_Kind kind, const char *k, const char *msg);
MU_API int mu_code(mu_Report *R, const char *code);
MU_API int mu_render(mu_Report *R, int pos, mu_Id src_id);

/* configuration */

MU_API void mu_default_config(mu_Config *config);
MU_API void mu_ansi_charset(mu_Config *config);
MU_API void mu_unicode_charset(mu_Config *config);

typedef char mu_ColorCode[MU_COLOR_CODE_SIZE];

struct mu_Config {
    int cross_gap;        /* show crossing gaps in cross arrows */
    int compact;          /* whether to use compact mode */
    int underlines;       /* whether to draw underlines for labels */
    int multiline_arrows; /* whether to draw multiline arrows */
    int tab_width;        /* number of spaces per tab */
    int limit_width;      /* maximum line width, or 0 for no limit */
    int ambiwidth;        /* how to treat ambiguous width characters */

    mu_LabelAttach label_attach; /* where to attach inline labels */
    mu_IndexType index_type;     /* index type for label positions */

    mu_Color *color; /* a color function or NULL for no color */
    void *color_ud;  /* user data for the color function */

    mu_ColorCode color_code; /* color code storage for `default_color` */
    mu_Chunk char_set[MU_DRAW_COUNT]; /* character set to use */
};

/* color generator */

MU_API void mu_initcolorgen(mu_ColorGen *cg, float min_brightness);
MU_API void mu_gencolor(mu_ColorGen *cg, mu_ColorCode *out);
MU_API mu_Chunk mu_fromcolorcode(void *ud, mu_ColorKind kind);

struct mu_ColorGen {
    int state[3];         /* internal state */
    float min_brightness; /* minimum brightness */
};

/* source */

#define mu_source_offset(src, offset) ((src)->line_no_offset = (offset))

MU_API int mu_source(mu_Report *R, mu_Source *src);
MU_API int mu_memory_source(mu_Source *src, const char *data, size_t len,
                            const char *name);

#if !MU_NO_STDIO
MU_API int mu_file_source(mu_Source *src, FILE *fp, const char *name);
#endif /* !MU_NO_STDIO */

struct mu_Slice {
    const char *p, *e;
};

struct mu_Source {
    void *ud;           /* user data for this source */
    mu_Slice name;      /* source name slice */
    int line_no_offset; /* line number offset for this source */
    mu_Id id;           /* source id, written by `mu_source()`, start from 0 */

    int (*init)(mu_Source *src);
    void (*free)(mu_Source *src);

    mu_Slice (*get_line)(mu_Source *src, unsigned line_no);
    const mu_Line *(*get_line_info)(mu_Source *src, unsigned line_no);
    unsigned (*line_from_chars)(mu_Source *src, unsigned char_pos,
                                const mu_Line **out);
    unsigned (*line_from_bytes)(mu_Source *src, unsigned byte_pos,
                                const mu_Line **out);
};

struct mu_Line {
    unsigned offset; /* character offset of this line in the original source */
    unsigned len;    /* character length of this line in the original source */
    unsigned byte_offset; /* byte offset of this line in the original source */
    unsigned byte_len;    /* byte length of this line in the original source */
    unsigned newline;     /* extra length (usually a newline) after this line */
};

MU_NS_END

#endif /* musubi_h */

#if !defined(mu_implementation) && defined(MU_IMPLEMENTATION)
#define mu_implementation 1

#include <assert.h>
#include <limits.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

#ifndef MU_MIN_FILENAME_WIDTH
#define MU_MIN_FILENAME_WIDTH 8
#endif /* MU_MIN_FILENAME_WIDTH */

#define mu_min(a, b)    ((a) < (b) ? (a) : (b))
#define mu_max(a, b)    ((a) > (b) ? (a) : (b))
#define mu_asc(a, b, c) ((a) <= (b) && (b) <= (c))

#define muX(code)                 \
    do {                          \
        int r = (code);           \
        if (r != MU_OK) return r; \
    } while (0)

MU_NS_BEGIN

typedef int mu_Width;
typedef unsigned mu_Col;

typedef struct mu_Label {
    void *ud;           /* user data for the color function */
    mu_Color *color;    /* the color for this label */
    mu_Slice message;   /* the message to display for this label */
    unsigned start_pos; /* start position in the source */
    unsigned end_pos;   /* end position in the source */
    mu_Width width;     /* display width of the message, must >= 0 */
    mu_Id src_id;       /* source id this label belongs to */
    int order;          /* order of this label in vertical sorting */
    int priority; /* priority of this label when merging overlapping labels */
} mu_Label;

typedef struct mu_LabelInfo {
    mu_Label *label;     /* label associated with this info */
    int multi;           /* whether this label spans multiple lines */
    unsigned start_char; /* start character position of this label */
    unsigned end_char;   /* end character position of this label */
} mu_LabelInfo;

typedef struct mu_Group {
    mu_Source *src;             /* source of this group */
    mu_LabelInfo *labels;       /* labels in this group */
    mu_LabelInfo *multi_labels; /* multi-line labels in this group */
    unsigned start_char;        /* start char position of this group */
    unsigned end_char;          /* end char position of this group */
} mu_Group;

typedef struct mu_LineLabel {
    const mu_LabelInfo *info; /* label info associated with this label */
    mu_Col col;               /* column position in this line */

    /* draw_msg is 0 only if the label is multi and this line is the start */
    int draw_msg; /* whether to draw the message in this line */
} mu_LineLabel;

typedef struct mu_LabelCluster {
    const mu_Line *line;       /* line the cluster represents */
    mu_LineLabel margin_label; /* margin label for this line */
    mu_LineLabel *line_labels; /* labels in this line */
    unsigned arrow_len;        /* length of the arrows line */
    mu_Col min_col;            /* ?TODO first column of labels in this line */
    mu_Col start_col;          /* start column of this cluster */
    mu_Col end_col;            /* end column of this cluster */
    mu_Width max_msg_width;    /* maximum message width in this line */
} mu_LabelCluster;

struct mu_Report {
    void *ud;          /* userdata for allocf */
    mu_Allocf *allocf; /* custom allocation function */
    mu_Config *config; /* configuration */

    /* rendering context */
    void *writer_ud;
    mu_Writer *writer;
    const mu_Label *cur_color_label; /* current color label */
    mu_ColorKind cur_color_kind;     /* current color kind */
    mu_Group *groups;                /* groups of sources */
    mu_LabelCluster *clusters;       /* current label clusters for rendering */
    mu_LineLabel *ll_cache;  /* line label cache used in `muC_assemble` */
    mu_Width *width_cache;   /* current line width cache */
    mu_Width line_no_width;  /* maximum width of line number */
    mu_Width ellipsis_width; /* display width of ellipsis */

    const mu_Group *cur_group;          /* current group being rendered */
    const mu_LabelCluster *cur_cluster; /* current cluster being rendered */
    const mu_Line *cur_line;            /* current line being rendered */

    /* report details */
    mu_Kind kind;          /* predefined kind */
    mu_Slice code;         /* code message shown in header */
    mu_Slice kind_message; /* kind message shown in header */
    mu_Slice message;      /* main message shown in header */
    mu_Source *sources;    /* sources involved in the report */
    mu_Label *labels;      /* labels involved in the report */
    mu_Slice *helps;       /* help messages shown in footer */
    mu_Slice *notes;       /* note messages shown in footer */
};

/* array */

#define MU_MIN_CAPACITY 8
#define MU_MAX_CAPACITY (1u << 30)

#define muA_rawH(A)      (assert(A), (mu_ArrayHeader *)((A) - 1))
#define muA_size(A)      ((A) ? muA_rawH(A)->size : 0)
#define muA_delete(R, A) (muA_delete_(R, (void *)(A), sizeof(*(A))), (A) = NULL)
#define muA_push(R, A) \
    (muA_reserve_(R, (void **)&(A), sizeof(*(A)), 1), &(A)[muA_rawH(A)->size++])
#define muA_reserve(R, A, N) \
    (muA_reserve_(R, (void **)&(A), sizeof(*(A)), (N)), &(A)[muA_rawH(A)->size])
#define muA_addsize(R, A, N) (muA_rawH(A)->size += (N))
#define muA_reset(R, A)      (muA_rawH(A)->size = 0)

typedef struct mu_ArrayHeader {
    unsigned size;
    unsigned capacity;
} mu_ArrayHeader;

static void muA_delete_(mu_Report *R, void *A, size_t esize) {
    mu_ArrayHeader *h = A ? muA_rawH((void **)A) : NULL;
    if (h == NULL) return;
    R->allocf(R->ud, h, 0, sizeof(mu_ArrayHeader) + h->capacity * esize);
}

static void muA_resize(mu_Report *R, void **A, size_t newcap, size_t esize) {
    mu_ArrayHeader *h = *A ? muA_rawH((void **)*A) : NULL;
    if (h == NULL || h->size >= h->capacity) {
        size_t old_size = h ? sizeof(mu_ArrayHeader) + h->capacity * esize : 0;
        size_t new_size = sizeof(mu_ArrayHeader) + newcap * esize;
        mu_ArrayHeader *newh =
            (mu_ArrayHeader *)R->allocf(R->ud, h, new_size, old_size);
        if (newh == NULL) return (void)abort();
        if (h == NULL) newh->size = 0;
        newh->capacity = newcap;
        *A = (void *)(newh + 1);
    }
}

static void muA_reserve_(mu_Report *R, void **A, size_t esize, unsigned n) {
    mu_ArrayHeader *h = *A ? muA_rawH((void **)*A) : NULL;
    unsigned desired = h ? h->size + n : n;
    if (desired > MU_MAX_CAPACITY) return (void)abort();
    if (h == NULL || desired > h->capacity) {
        unsigned newcapa = h ? h->capacity : MU_MIN_CAPACITY;
        while ((newcapa += newcapa >> 1) < desired) /* continue */
            ;
        muA_resize(R, A, newcapa, esize);
    }
}

/* unicode */

#include "unidata.h"

#define muD_tablesize(t) (sizeof(t) / sizeof((t)[0]))
#define muD_literal(lit) muD_slice("" lit, sizeof(lit) - 1)

/* clang-format off */
static size_t muD_bytelen(mu_Slice s) { return (size_t)(s.e - s.p); }

static mu_Slice muD_slice(const char *p, size_t len)
{ mu_Slice s; s.p = p, s.e = p + len; return s; }
/* clang-format on */

static mu_Slice muD_snprintf(char *buf, size_t bufsize, const char *fmt, ...) {
    va_list args;
    int n;
    va_start(args, fmt);
    n = vsnprintf(buf, bufsize, fmt, args);
    va_end(args);
    return muD_slice(buf, n > 0 ? mu_min((size_t)n, bufsize - 1) : 0);
}

static unsigned muD_count(mu_Slice s, size_t byte_pos) {
    size_t i = 0, len = muD_bytelen(s);
    unsigned count;
    for (count = 0; i < byte_pos && i < len; ++count) {
        unsigned char c = (unsigned char)s.p[i];
        if (c < 0x80) i += 1;
        else if ((c & 0xE0) == 0xC0) i += 2;
        else if ((c & 0xF0) == 0xE0) i += 3;
        else if ((c & 0xF8) == 0xF0) i += 4;
        else i += 1; /* invalid byte, skip */
    }
    return count == 0 || i == byte_pos ? count : count - 1;
}

static void muD_advance(mu_Slice *s) {
    utfint c;
    if (s->p >= s->e) return;
    if ((c = *s->p & 0xFF) < 0x80) s->p += 1;
    else if ((c & 0xE0) == 0xC0 && s->p + 1 < s->e) s->p += 2;
    else if ((c & 0xF0) == 0xE0 && s->p + 2 < s->e) s->p += 3;
    else if ((c & 0xF8) == 0xF0 && s->p + 3 < s->e) s->p += 4;
    else s->p += 1; /* invalid byte, skip */
}

static utfint muD_decode(mu_Slice *s) {
    utfint ch;
    if (s->p >= s->e) return 0;
    ch = *s->p++ & 0xFF;
    if (ch < 0x80) return ch;
    if ((ch & 0xE0) == 0xC0 && s->p < s->e)
        return s->p += 1, ((ch & 0x1F) << 6) | (s->p[-1] & 0x3F);
    if ((ch & 0xF0) == 0xE0 && s->p + 1 < s->e)
        return s->p += 2, ((ch & 0x0F) << 12) | ((s->p[-2] & 0x3F) << 6)
                              | (s->p[-1] & 0x3F);
    if ((ch & 0xF8) == 0xF0 && s->p + 2 < s->e)
        return s->p += 3, ((ch & 0x07) << 18) | ((s->p[-3] & 0x3F) << 12)
                              | ((s->p[-2] & 0x3F) << 6) | (s->p[-1] & 0x3F);
    return ch; /* invalid, fallback */
}

static utfint muD_rdecode(mu_Slice *s) {
    mu_Slice ns = *s;
    while (s->p < s->e && ((s->e[-1] & 0xC0) == 0x80)) --s->e;
    s->e = s->p < s->e ? s->e - 1 : s->p;
    return ns.p = s->e, muD_decode(&ns);
}

static int muD_find(const range_table *t, size_t size, utfint ch) {
    size_t begin = 0, end = size;
    while (begin < end) {
        size_t mid = (begin + end) / 2;
        if (t[mid].last < ch) begin = mid + 1;
        else if (t[mid].first > ch) end = mid;
        else return (ch - t[mid].first) % t[mid].step == 0;
    }
    return 0;
}

static int muD_width(utfint ch, int ambiwidth) {
    if (muD_find(doublewidth_table, muD_tablesize(doublewidth_table), ch))
        return 2;
    if (muD_find(ambiwidth_table, muD_tablesize(ambiwidth_table), ch))
        return ambiwidth;
    if (muD_find(compose_table, muD_tablesize(compose_table), ch)) return 0;
    if (muD_find(unprintable_table, muD_tablesize(unprintable_table), ch))
        return 0;
    return 1;
}

static mu_Width muD_strwidth(mu_Slice s, mu_Width ambi) {
    mu_Width w = 0;
    while (s.p < s.e) w += muD_width(muD_decode(&s), ambi);
    return w;
}

static mu_Width muD_widthlimit(mu_Slice *s, mu_Width width, mu_Width ambi) {
    mu_Slice o = *s;
    mu_Width cw;
    if (width >= 0) {
        const char *start = s->p, *prev = s->p;
        for (; s->p < s->e && width != 0; width -= cw) {
            cw = muD_width(muD_decode((prev = s->p, s)), ambi);
            if (width < cw) break;
        }
        return *s = muD_slice(start, prev - start), width;
    } else {
        const char *end = s->e, *prev = s->e;
        for (; s->p < s->e && width != 0; width += cw) {
            cw = muD_width(muD_rdecode((prev = s->e, s)), ambi);
            if (-width < cw) break;
        }
        return *s = muD_slice(prev, end - prev), width;
    }
}

/* color generator */

MU_API void mu_initcolorgen(mu_ColorGen *cg, float min_brightness) {
    cg->state[0] = 30000, cg->state[1] = 15000, cg->state[2] = 35000;
    cg->min_brightness = min_brightness;
}

MU_API void mu_gencolor(mu_ColorGen *cg, mu_ColorCode *out) {
    int i, code = 16, n;
    for (int i = 0; i < 3; i++) {
        cg->state[i] = cg->state[i] + 40503 * (i * 4 + 1130);
        cg->state[i] = cg->state[i] % 65536;
    }
    code += ((float)cg->state[2] / 65535 * (1 - cg->min_brightness)
             + cg->min_brightness)
          * 5.0;
    code += ((float)cg->state[1] / 65535 * (1 - cg->min_brightness)
             + cg->min_brightness)
          * 30.0;
    code += ((float)cg->state[0] / 65535 * (1 - cg->min_brightness)
             + cg->min_brightness)
          * 180.0;
    n = snprintf(*out + 1, sizeof(mu_ColorCode) - 1, "\x1b[38;5;%dm", code);
    (*out)[0] = (assert(n <= sizeof(mu_ColorCode) - 1), (char)n);
}

MU_API mu_Chunk mu_fromcolorcode(void *ud, mu_ColorKind k) {
    mu_Chunk *code = (mu_Chunk *)ud;
    if (k == MU_COLOR_RESET) return (mu_Chunk) "4\x1b[0m";
    return (mu_Chunk)ud;
}

/* writer */

#define MU_PADDING_BUF_SIZE 64

/* clang-format off */
static int muW_write(mu_Report *R, mu_Slice s)
{ return (assert(R->writer), R->writer(R->writer_ud, s.p, muD_bytelen(s))); }
/* clang-format on */

static int muW_color(mu_Report *R, mu_ColorKind k) {
    mu_Color *color = R->config->color;
    void *ud = R->config->color_ud;
    if (R->cur_color_label && R->cur_color_label->color)
        color = R->cur_color_label->color, ud = R->cur_color_label->ud;
    if (color) {
        mu_Chunk code;
        if (k != R->cur_color_kind) {
            code = color(ud, MU_COLOR_RESET);
            muX(muW_write(R, muD_slice(code + 1, (size_t)*code)));
        }
        if (k != MU_COLOR_RESET) {
            code = color(ud, k);
            return muW_write(R, muD_slice(code + 1, (size_t)*code));
        }
    }
    if (k == MU_COLOR_RESET) R->cur_color_label = NULL;
    return R->cur_color_kind = k, MU_OK;
}

static int muW_use_color(mu_Report *R, const mu_Label *label, mu_ColorKind k) {
    if (R->cur_color_kind != MU_COLOR_RESET && R->cur_color_label != label)
        muX(muW_color(R, MU_COLOR_RESET));
    R->cur_color_label = label;
    return muW_color(R, k);
}

static int muW_draw(mu_Report *R, mu_CharSet cs, int count) {
    const mu_Chunk chunk = R->config->char_set[assert(cs < MU_DRAW_COUNT), cs];
    if (chunk == NULL || chunk[0] == 1) {
        char pad[MU_PADDING_BUF_SIZE];
        memset(pad, chunk ? chunk[0] : ' ', mu_min(sizeof(pad), count));
        while (count >= MU_PADDING_BUF_SIZE) {
            muX(muW_write(R, muD_slice(pad, sizeof(pad))));
            count -= MU_PADDING_BUF_SIZE;
        }
        if (count > 0) muX(muW_write(R, muD_slice(pad, count)));
    } else {
        int i;
        for (i = 0; i < count; ++i)
            muX(muW_write(R, muD_slice(chunk + 1, chunk[0])));
    }
    return MU_OK;
}

/* misc utils */

static mu_Col muM_col(unsigned pos, const mu_LineLabel *ll,
                      const mu_Line *line) {
    return ll->info->multi ? ll->col : pos - line->offset;
}

static int muM_contains(unsigned pos, const mu_Line *line) {
    return pos >= line->offset && pos < line->offset + line->len + 1;
}

static mu_Width muM_marginwidth(mu_Report *R) {
    size_t size = muA_size(R->cur_group->multi_labels);
    return (size ? size + 1 : 0) * (R->config->compact ? 1 : 2);
}

static int muM_line_in_label(const mu_Line *line, const mu_LabelInfo *li) {
    unsigned i, size;
    for (i = 0, size = muA_size(li); i < size; ++i)
        if (li[i].start_char < line->offset && li[i].end_char > line->offset)
            return 1;
    return 0;
}

static unsigned muM_bytes2chars(mu_Source *src, unsigned pos,
                                const mu_Line **line) {
    unsigned line_no = src->line_from_bytes(src, pos, line);
    mu_Slice s = src->get_line(src, line_no);
    return (*line)->offset + muD_count(s, pos - (*line)->byte_offset);
}

/* label cluster */

static void muC_collect_multi(mu_Report *R) {
    const mu_Line *line = R->cur_line;
    const mu_LabelInfo *multi_labels = R->cur_group->multi_labels;
    unsigned i, size, draw_msg;
    for (i = 0, size = muA_size(multi_labels); i < size; i++) {
        const mu_LabelInfo *li = &multi_labels[i];
        mu_LineLabel *ll;
        mu_Col col;
        if (muM_contains(li->start_char, line))
            col = li->start_char - line->offset, draw_msg = 0;
        else if (muM_contains(li->end_char, line))
            col = li->end_char - line->offset, draw_msg = 1;
        else continue;
        ll = muA_push(R, R->ll_cache);
        ll->info = li, ll->col = col, ll->draw_msg = draw_msg;
    }
}

static void muC_collect_inline(mu_Report *R) {
    const mu_Line *line = R->cur_line;
    const mu_LabelInfo *labels = R->cur_group->labels;
    unsigned i, size, pos;
    for (i = 0, size = muA_size(labels); i < size; i++) {
        const mu_LabelInfo *li = &labels[i];
        mu_LineLabel *ll;
        if (!(li->start_char >= line->offset
              && li->end_char <= line->offset + line->len + 1))
            continue;
        switch (R->config->label_attach) {
        case MU_ATTACH_START: pos = li->start_char; break;
        case MU_ATTACH_END:   pos = li->end_char; break;
        default:              pos = (li->start_char + li->end_char) / 2; break;
        }
        ll = muA_push(R, R->ll_cache);
        ll->info = li, ll->col = pos - line->offset, ll->draw_msg = 1;
    }
}

static int muC_cmp_ll(const void *lhf, const void *rhf) {
    const mu_LineLabel *l = (const mu_LineLabel *)lhf;
    const mu_LineLabel *r = (const mu_LineLabel *)rhf;
    int llen, rlen;
    if (l->info->label->order != r->info->label->order)
        return l->info->label->order - r->info->label->order;
    if (l->col != r->col) return l->col - r->col;
    llen = l->info->end_char - l->info->start_char;
    rlen = r->info->end_char - r->info->start_char;
    if (llen != rlen) return rlen - llen;
    return l - r;
}

static int muC_fill_llcache(mu_Report *R) {
    muA_reset(R, R->ll_cache);
    muC_collect_multi(R);
    muC_collect_inline(R);
    qsort(R->ll_cache, muA_size(R->ll_cache), sizeof(mu_LineLabel), muC_cmp_ll);
    return muA_size(R->ll_cache);
}

static void muC_fill_widthcache(mu_Report *R, size_t len, mu_Slice data) {
    int width = 0;
    muA_reset(R, R->width_cache);
    muA_reserve(R, R->width_cache, len + 1);
    while (data.p < data.e) {
        utfint ch = muD_decode(&data);
        *muA_push(R, R->width_cache) = width;
        width += muD_width(ch, R->config->ambiwidth);
    }
    *muA_push(R, R->width_cache) = width;
}

static mu_LabelCluster *muC_new_cluster(mu_Report *R) {
    mu_LabelCluster *lc = muA_push(R, R->clusters);
    memset(lc, 0, sizeof(mu_LabelCluster));
    lc->min_col = INT_MAX;
    lc->end_col = R->cur_line->len;
    return lc;
}

static void muC_fill_cluster(mu_Report *R) {
    const mu_LineLabel *lls = R->ll_cache;
    const mu_Line *line = R->cur_line;
    unsigned i, size, extra_arrow_len = R->config->compact ? 1 : 2;
    mu_Width min_start = INT_MAX, max_end = INT_MIN;
    mu_Width limited = R->config->limit_width;
    mu_LabelCluster *lc;
    muA_reset(R, R->clusters);
    if (limited > 0) limited -= R->line_no_width + 4 + muM_marginwidth(R);
    lc = muC_new_cluster(R);
    for (i = 0, size = muA_size(lls); i < size; i++) {
        const mu_LineLabel *ll = &lls[i];
        mu_Col start_col, end_col = muM_col(ll->info->end_char, ll, line);
        mu_Width label = ll->info->label->width;
        if (R->config->limit_width > 0) {
            mu_Width cur,
                start = R->width_cache[muM_col(ll->info->start_char, ll, line)];
            mu_Width end = R->width_cache[end_col];
            int is_empty =
                (!muA_size(lc->line_labels) && !lc->margin_label.info);
            min_start = mu_min(min_start, start);
            max_end = mu_max(max_end, end);
            cur = (max_end - min_start)
                + (ll->draw_msg && label ? extra_arrow_len + 1 + label : 0);
            if (cur > limited && !is_empty)
                min_start = INT_MAX, max_end = INT_MIN, lc = muC_new_cluster(R);
        }
        if (ll->info->multi) {
            int is_margin = 0;
            if (!lc->margin_label.info) lc->margin_label = *ll, is_margin = 1;
            if ((R->config->limit_width <= 0 || !is_margin) && ll->draw_msg)
                end_col = line->len + line->newline;
        }
        if (lc->margin_label.info != ll->info || (ll->draw_msg && label))
            *muA_push(R, lc->line_labels) = *ll;
        lc->arrow_len = mu_max(lc->arrow_len, end_col + extra_arrow_len);
        start_col = muM_col(ll->info->start_char, ll, line);
        lc->min_col = mu_min(lc->min_col, start_col);
        lc->max_msg_width = mu_max(lc->max_msg_width, label);
    }
}

static int muC_widthindex(mu_Report *R, mu_Width width, mu_Col l, mu_Col u) {
    mu_Width delta = R->width_cache[l];
    while (l < u) {
        int mid = l + ((u - l) >> 1);
        if ((R->width_cache[mid] - delta) < width) l = mid + 1;
        else u = mid;
    }
    return l;
}

static void muC_calc_colrange(mu_Report *R, mu_LabelCluster *lc) {
    int len = muA_size(R->width_cache) - 1;
    int line_part = mu_min(lc->arrow_len, len); /* arrow_len in line part */
    mu_Width essential, skip, balance = 0;
    mu_Width margin = muM_marginwidth(R);
    mu_Width fixed = R->line_no_width + 4 + margin; /* line_no+edge+margin */
    mu_Width limited = R->config->limit_width - fixed;
    mu_Width arrow = R->width_cache[line_part] + mu_max(0, lc->arrow_len - len);

    mu_Width edge = arrow + 1 + lc->max_msg_width; /* +1 for space */
    mu_Width line_width = R->width_cache[len];
    if (edge <= limited && line_width <= limited) return;

    essential = (arrow - R->width_cache[lc->min_col]);
    essential += 1 + lc->max_msg_width;
    if (essential + R->ellipsis_width >= limited) {
        lc->start_col = lc->min_col;
        lc->end_col = muC_widthindex(
            R, 1 + lc->max_msg_width - R->ellipsis_width, line_part, len);
        return;
    }
    skip = edge - limited + R->ellipsis_width + 1;
    if (skip <= 0) {
        lc->start_col = 0;
        lc->end_col = muC_widthindex(R, limited - arrow - R->ellipsis_width,
                                     line_part, len);
        return;
    }
    if (line_width > edge) {
        mu_Width avail = line_width - edge;
        mu_Width desired = (limited - essential) / 2;
        balance = desired + mu_max(0, desired - avail);
    }
    lc->start_col = muC_widthindex(R, skip + balance, 1, line_part) - 1;
    lc->end_col = muC_widthindex(
        R, 1 + lc->max_msg_width + balance - R->ellipsis_width, line_part, len);
}

static const mu_LabelInfo *muC_update_highlight(unsigned pos,
                                                const mu_LabelInfo *l,
                                                const mu_LabelInfo *r) {
    int llen, rlen;
    if (pos < r->start_char || pos > r->end_char + 1) return l;
    if (l == NULL) return r;
    if (l->label->priority != r->label->priority)
        return l->label->priority < r->label->priority ? r : l;
    llen = l->end_char - l->start_char;
    rlen = r->end_char - r->start_char;
    return rlen < llen ? r : l;
}

static const mu_LabelInfo *muC_get_highlight(mu_Report *R, mu_Col col) {
    const mu_Group *g = R->cur_group;
    const mu_LabelCluster *lc = R->cur_cluster;
    const mu_LabelInfo *r = NULL;
    unsigned i, size, pos = R->cur_line->offset + col;
    if (lc->margin_label.info)
        r = muC_update_highlight(pos, r, lc->margin_label.info);
    for (i = 0, size = muA_size(g->multi_labels); i < size; i++)
        r = muC_update_highlight(pos, r, &g->multi_labels[i]);
    for (i = 0, size = muA_size(lc->line_labels); i < size; i++)
        r = muC_update_highlight(pos, r, lc->line_labels[i].info);
    return r;
}

static const mu_LabelInfo *muC_get_vbar(mu_Report *R, int row, mu_Col col) {
    const mu_LabelCluster *lc = R->cur_cluster;
    unsigned i, size;
    for (i = 0, size = muA_size(lc->line_labels); i < size; i++) {
        const mu_LineLabel *ll = &lc->line_labels[i];
        if (((ll->info->label->width || ll->info->multi)
             && lc->margin_label.info != ll->info && ll->col == col
             && row <= i))
            return ll->info;
    }
    return NULL;
}

static const mu_LabelInfo *muC_get_underline(mu_Report *R, mu_Col col) {
    const mu_LabelCluster *lc = R->cur_cluster;
    unsigned pos = R->cur_line->offset + col;
    const mu_LabelInfo *r = NULL;
    unsigned i, size, rlen, lllen;
    int rp, llp;
    for (i = 0, size = muA_size(lc->line_labels); i < size; i++) {
        const mu_LineLabel *ll = &lc->line_labels[i];
        if (!(!ll->info->multi
              && mu_asc(ll->info->start_char, pos, ll->info->end_char - 1)))
            continue;
        lllen = ll->info->end_char - ll->info->start_char;
        llp = ll->info->label->priority;
        if (!r) r = ll->info;
        else if (llp > rp) r = ll->info;
        else if (llp == rp && lllen < rlen) r = ll->info;
        if (r == ll->info) rlen = lllen, rp = llp;
    }
    return r;
}

/* source group */

static void muG_add_info(mu_Report *R, unsigned i, mu_LabelInfo *li) {
    if (i == muA_size(R->groups)) {
        mu_Group *group = muA_push(R, R->groups);
        memset(group, 0, sizeof(mu_Group));
        group->src = &R->sources[li->label->src_id];
        group->start_char = li->start_char;
        group->end_char = li->end_char;
    } else {
        mu_Group *g = &R->groups[i];
        g->start_char = mu_min(g->start_char, li->start_char);
        g->end_char = mu_max(g->end_char, li->end_char);
    }
    if (li->multi) *muA_push(R, R->groups[i].multi_labels) = *li;
    else *muA_push(R, R->groups[i].labels) = *li;
}

static int muG_cmp_labelinfo(const void *lhf, const void *rhf) {
    const mu_LabelInfo *l = (const mu_LabelInfo *)lhf;
    const mu_LabelInfo *r = (const mu_LabelInfo *)rhf;
    int llen = l->end_char - l->start_char;
    int rlen = r->end_char - r->start_char;
    return rlen - llen;
}

static int muG_init_info(mu_Report *R, mu_Label *label, mu_LabelInfo *out) {
    unsigned start_char = label->start_pos, end_char = label->end_pos;
    const mu_Line *start_line, *end_line;
    mu_Source *src;
    if (label->src_id >= muA_size(R->sources)) return MU_ERRSRC;
    src = &R->sources[label->src_id];
    if (R->config->index_type == MU_INDEX_CHAR) {
        src->line_from_chars(src, start_char, &start_line);
        src->line_from_chars(src, end_char, &end_line);
        out->start_char = start_char, out->end_char = end_char;
    } else {
        out->start_char = muM_bytes2chars(src, start_char, &start_line);
        out->end_char = muM_bytes2chars(src, end_char, &end_line);
    }
    out->label = label;
    out->multi = (start_line != end_line);
    return MU_OK;
}

static int muG_make_groups(mu_Report *R) {
    unsigned i, llen, j, glen;
    muA_reset(R, R->groups);
    for (i = 0, llen = muA_size(R->labels); i < llen; i++) {
        mu_Label *label = &R->labels[i];
        mu_LabelInfo info;
        if (muG_init_info(R, label, &info) != MU_OK) continue;
        for (j = 0, glen = muA_size(R->groups); j < glen; j++)
            if (R->groups[j].src->id == label->src_id) break;
        muG_add_info(R, j, &info);
    }
    for (i = 0, glen = muA_size(R->groups); i < glen; i++) {
        mu_LabelInfo *li = R->groups[i].multi_labels;
        qsort(li, muA_size(li), sizeof(mu_LabelInfo), muG_cmp_labelinfo);
    }
    return MU_OK;
}

/* rendering */

typedef enum mu_Margin {
    MU_MARGIN_NONE,
    MU_MARGIN_LINE,
    MU_MARGIN_ARROW,
    MU_MARGIN_ELLIPSIS
} mu_Margin;

typedef struct muR_LocCtx {
    mu_Report *R;
    mu_Source *src;
    mu_Slice name, loc;
    int pos;
} muR_LocCtx;

static int muR_header(mu_Report *R) {
    switch (R->kind) {
    case MU_KIND_ERROR:   muX(muW_color(R, MU_COLOR_ERROR)); break;
    case MU_KIND_WARNING: muX(muW_color(R, MU_COLOR_WARNING)); break;
    default:              muX(muW_color(R, MU_COLOR_KIND)); break;
    }
    if (R->code.p) {
        muX(muW_draw(R, MU_DRAW_LBOX, 1));
        muX(muW_write(R, R->code));
        muX(muW_draw(R, MU_DRAW_RBOX, 1));
    }
    muX(muW_draw(R, MU_DRAW_SPACE, 1));
    muX(muW_write(R, R->kind_message));
    muX(muW_draw(R, MU_DRAW_COLON, 1));
    muX(muW_color(R, MU_COLOR_RESET));
    if (R->message.p) {
        muX(muW_draw(R, MU_DRAW_SPACE, 1));
        muX(muW_write(R, R->message));
    }
    return muW_draw(R, MU_DRAW_NEWLINE, 1);
}

static void muG_calc_location(muR_LocCtx *ctx, char *out, size_t size) {
    const mu_Group *g = ctx->R->cur_group;
    unsigned line_no = 0, col = 0;
    const mu_Line *line;
    assert(ctx->pos >= 0);
    if (ctx->src == g->src && ctx->R->config->index_type == MU_INDEX_BYTE)
        ctx->pos = muM_bytes2chars(ctx->src, ctx->pos, &line);
    else {
        if (ctx->src != g->src)
            ctx->pos = muA_size(g->labels) ? (int)g->labels[0].start_char : -1;
        line_no =
            ctx->src->line_from_chars(ctx->src, (unsigned)ctx->pos, &line);
    }
    col = ctx->pos - line->offset + 1;
    line_no += ctx->src->line_no_offset + 1;
    ctx->loc = muD_snprintf(out, size, "%u:%u", line_no, col);
}

static int muR_reference(mu_Report *R, unsigned gidx, int pos, mu_Id src_id) {
    muR_LocCtx ctx;
    int ellipsis = 0;
    char loc_buf[256];
    assert(src_id < muA_size(R->sources));
    assert(gidx < muA_size(R->groups));
    memset(&ctx, 0, sizeof(ctx));
    ctx.R = R, ctx.src = &R->sources[src_id], ctx.pos = pos;
    if (pos < 0) ctx.loc = muD_literal("?:?");
    else muG_calc_location(&ctx, loc_buf, sizeof(loc_buf));
    ctx.name = ctx.src->name;
    if (R->config->limit_width > 0) {
        mu_Width id_width = muD_strwidth(ctx.name, R->config->ambiwidth);
        mu_Width fixed = (int)muD_bytelen(ctx.loc) + R->line_no_width + 9;
        mu_Width line_width = R->config->limit_width;
        if (id_width + fixed > line_width) {
            mu_Width ambi = R->config->ambiwidth;
            mu_Width avail = line_width - fixed - R->ellipsis_width;
            avail = mu_max(avail, MU_MIN_FILENAME_WIDTH);
            ellipsis = muD_widthlimit(&ctx.name, -avail, ambi) + 1;
        }
    }
    muX(muW_draw(R, MU_DRAW_SPACE, R->line_no_width + 2));
    muX(muW_color(R, MU_COLOR_MARGIN));
    muX(muW_draw(R, gidx ? MU_DRAW_VBAR : MU_DRAW_LTOP, 1));
    muX(muW_draw(R, MU_DRAW_HBAR, 1));
    muX(muW_draw(R, MU_DRAW_LBOX, 1));
    muX(muW_color(R, MU_COLOR_RESET));
    muX(muW_draw(R, MU_DRAW_SPACE, 1));
    if (ellipsis) {
        muX(muW_draw(R, MU_DRAW_SPACE, ellipsis - 1));
        muX(muW_draw(R, MU_DRAW_ELLIPSIS, 1));
    }
    muX(muW_write(R, ctx.name));
    muX(muW_draw(R, MU_DRAW_COLON, 1));
    muX(muW_write(R, ctx.loc));
    muX(muW_draw(R, MU_DRAW_SPACE, 1));
    muX(muW_color(R, MU_COLOR_MARGIN));
    muX(muW_draw(R, MU_DRAW_RBOX, 1));
    muX(muW_color(R, MU_COLOR_RESET));
    return MU_OK;
}

static int muR_empty_line(mu_Report *R) {
    if (R->config->compact) return MU_OK;
    muX(muW_draw(R, MU_DRAW_SPACE, R->line_no_width + 2));
    muW_color(R, MU_COLOR_MARGIN);
    muX(muW_draw(R, MU_DRAW_VBAR, 1));
    muW_color(R, MU_COLOR_RESET);
    return muW_draw(R, MU_DRAW_NEWLINE, 1);
}

static int muR_lineno(mu_Report *R, unsigned line_no, int is_ellipsis) {
    char buf[32];
    mu_Slice ln;
    if (line_no && is_ellipsis) {
        line_no += R->cur_group->src->line_no_offset;
        ln = muD_snprintf(buf, sizeof(buf), "%u", line_no);
        muX(muW_draw(R, MU_DRAW_SPACE, R->line_no_width - muD_bytelen(ln)));
        muX(muW_color(R, MU_COLOR_MARGIN));
        muX(muW_write(R, ln));
        muX(muW_draw(R, MU_DRAW_SPACE, 1));
        muX(muW_draw(R, MU_DRAW_VBAR, 1));
    } else {
        muX(muW_draw(R, MU_DRAW_SPACE, R->line_no_width + 2));
        muX(muW_color(R, MU_COLOR_SKIPPED_MARGIN));
        muX(muW_draw(R, is_ellipsis ? MU_DRAW_VBAR_GAP : MU_DRAW_VBAR, 1));
    }
    muX(muW_color(R, MU_COLOR_RESET));
    return R->config->compact ? MU_OK : muW_draw(R, MU_DRAW_SPACE, 1);
}

static int muR_margin(mu_Report *R, const mu_LineLabel *report, mu_Margin t) {
    const mu_Group *g = R->cur_group;
    const mu_Line *line = R->cur_line;
    const mu_LabelCluster *lc = R->cur_cluster;
    unsigned i, size = muA_size(g->multi_labels);
    unsigned start_char = line->offset + (lc ? lc->min_col : 0);
    unsigned end_char = line->offset + (lc ? lc->end_col : line->len);
    const mu_LabelInfo *hbar = NULL, *ptr = NULL;
    int ptr_is_start = 0;
    if (size == 0) return MU_OK;
    for (i = 0; i < size; ++i) {
        const mu_LabelInfo *li = &g->multi_labels[i];
        const mu_LabelInfo *vbar = NULL, *corner = NULL;
        int is_start = mu_asc(start_char, li->start_char, end_char);
        if (li->end_char >= start_char && li->start_char <= end_char) {
            int is_margin = lc && lc->margin_label.info == li;
            int is_end = mu_asc(start_char, li->end_char, end_char);
            if (is_margin && t == MU_MARGIN_LINE)
                ptr = li, ptr_is_start = is_start;
            else if (!is_start && (!is_end || t == MU_MARGIN_LINE)) vbar = li;
            else if (report && report->info == li) {
                if (t != MU_MARGIN_ARROW && !is_start) vbar = li;
                else if (is_margin) vbar = lc->margin_label.info;
                if (t == MU_MARGIN_ARROW && (!is_margin || !is_start))
                    hbar = li, corner = li;
            } else if (report) {
                unsigned j, llen = muA_size(lc->line_labels);
                int info_is_below = 0;
                if (!is_margin) {
                    for (j = 0; j < llen; ++j) {
                        mu_LineLabel *ll = &lc->line_labels[j];
                        if (ll->info == li) break;
                        if ((info_is_below = (ll == report))) break;
                    }
                }
                if ((is_start != info_is_below
                     && (is_start || !is_margin || li->label->width)))
                    vbar = li;
            }
        }
        if (!hbar && ptr && t == MU_MARGIN_LINE && li != ptr) hbar = ptr;

        if (corner) {
            muX(muW_use_color(R, corner->label, MU_COLOR_LABEL));
            muX(muW_draw(R, is_start ? MU_DRAW_LTOP : MU_DRAW_LBOT, 1));
            if (!R->config->compact) muX(muW_draw(R, MU_DRAW_HBAR, 1));
        } else if (vbar && hbar && !R->config->cross_gap) {
            muX(muW_use_color(R, vbar->label, MU_COLOR_LABEL));
            muX(muW_draw(R, MU_DRAW_XBAR, 1));
            if (!R->config->compact) muX(muW_draw(R, MU_DRAW_HBAR, 1));
        } else if (hbar) {
            muX(muW_use_color(R, hbar->label, MU_COLOR_LABEL));
            if (!R->config->compact) muX(muW_draw(R, MU_DRAW_HBAR, 1));
        } else if (vbar) {
            mu_CharSet draw =
                t == MU_MARGIN_ELLIPSIS ? MU_DRAW_VBAR_GAP : MU_DRAW_VBAR;
            muX(muW_use_color(R, vbar->label, MU_COLOR_LABEL));
            muX(muW_draw(R, draw, 1));
            if (!R->config->compact) muX(muW_draw(R, MU_DRAW_SPACE, 1));
        } else if (ptr && t == MU_MARGIN_LINE) {
            mu_CharSet draw = MU_DRAW_HBAR;
            muX(muW_use_color(R, ptr->label, MU_COLOR_LABEL));
            if (li == ptr) {
                if (ptr_is_start) draw = MU_DRAW_LTOP;
                else if (!li->label->width) draw = MU_DRAW_LBOT;
                else draw = MU_DRAW_LCROSS;
            }
            muX(muW_draw(R, draw, 1));
            if (!R->config->compact) muX(muW_draw(R, MU_DRAW_HBAR, 1));
        } else {
            muX(muW_use_color(R, NULL, MU_COLOR_RESET));
            muX(muW_draw(R, MU_DRAW_SPACE, R->config->compact ? 1 : 2));
        }
    }

    if (hbar && (t != MU_MARGIN_LINE || hbar != ptr)) {
        muX(muW_use_color(R, hbar->label, MU_COLOR_LABEL));
        muX(muW_draw(R, MU_DRAW_HBAR, 1));
        if (!R->config->compact) muX(muW_draw(R, MU_DRAW_HBAR, 1));
    } else if (ptr && t == MU_MARGIN_LINE) {
        muX(muW_use_color(R, ptr->label, MU_COLOR_LABEL));
        muX(muW_draw(R, MU_DRAW_RARROW, 1));
        if (!R->config->compact) muX(muW_draw(R, MU_DRAW_SPACE, 1));
    } else {
        muX(muW_use_color(R, NULL, MU_COLOR_RESET));
        muX(muW_draw(R, MU_DRAW_SPACE, R->config->compact ? 1 : 2));
    }
    muX(muW_use_color(R, NULL, MU_COLOR_RESET));
    return MU_OK;
}

static int muR_line(mu_Report *R, mu_Slice data) {
    const mu_LabelCluster *lc = R->cur_cluster;
    const mu_LabelInfo *color = NULL;
    int tw = R->config->tab_width;
    const char *s;
    unsigned i;
    for (i = 0; i < lc->start_col; ++i) muD_advance(&data);
    for (s = data.p; i < lc->end_col && data.p < data.e; ++i) {
        const mu_LabelInfo *hl = muC_get_highlight(R, i);
        const char *p = data.p;
        utfint ch = muD_decode(&data);
        if (hl != color || ch == '\t') {
            int repeat = (ch == '\t' ? tw - (i % tw) : 1);
            if (color) muX(muW_use_color(R, color->label, MU_COLOR_LABEL));
            else muX(muW_use_color(R, NULL, MU_COLOR_UNIMPORTANT));
            if (s < p) muX(muW_write(R, muD_slice(s, p - s)));
            if (ch == '\t') muX(muW_draw(R, MU_DRAW_SPACE, repeat));
            color = hl, s = p + (ch == '\t');
        }
    }
    if (color) muX(muW_use_color(R, color->label, MU_COLOR_LABEL));
    else muX(muW_use_color(R, NULL, MU_COLOR_UNIMPORTANT));
    if (s < data.p) muX(muW_write(R, muD_slice(s, data.p - s)));
    return muW_use_color(R, NULL, MU_COLOR_RESET);
}

static int muR_arrows(mu_Report *R) {
    const mu_LabelCluster *lc = R->cur_cluster;
    const int *wc = R->width_cache;
    unsigned row, row_len = muA_size(lc->line_labels);
    int first = 1, col_max = R->cur_line->len;
    for (row = 0; row < row_len; ++row) {
        int has_ul = (first && R->config->underlines);
        const mu_LineLabel *ll = &lc->line_labels[row];
        mu_Col col;
        if (!(ll->info->label->width
              || (ll->info->multi && lc->margin_label.info != ll->info)))
            continue;
        if (!R->config->compact) {
            muX(muR_lineno(R, 0, false));
            muX(muR_margin(R, ll, MU_MARGIN_NONE));
            if (lc->start_col > 0)
                muX(muW_draw(R, MU_DRAW_SPACE, R->ellipsis_width));
            for (col = lc->start_col; col < lc->arrow_len; ++col) {
                int w = (col < col_max ? (wc[col + 1] - wc[col]) : 1);
                const mu_LabelInfo *vbar = muC_get_vbar(R, row, col);
                const mu_LabelInfo *underline =
                    has_ul ? muC_get_underline(R, col) : NULL;
                if (vbar && underline) {
                    muX(muW_use_color(R, vbar->label, MU_COLOR_LABEL));
                    muX(muW_draw(R, MU_DRAW_UNDERBAR, 1));
                    muX(muW_draw(R, MU_DRAW_UNDERLINE, w - 1));
                } else if (vbar) {
                    int uarrow =
                        (vbar->multi && first && R->config->multiline_arrows);
                    muX(muW_use_color(R, vbar->label, MU_COLOR_LABEL));
                    muX(muW_draw(R, uarrow ? MU_DRAW_UARROW : MU_DRAW_VBAR, w));
                } else if (underline) {
                    muX(muW_use_color(R, underline->label, MU_COLOR_LABEL));
                    muX(muW_draw(R, MU_DRAW_UNDERLINE, w));
                } else {
                    muX(muW_use_color(R, NULL, MU_COLOR_RESET));
                    muX(muW_draw(R, MU_DRAW_SPACE, w));
                }
            }
            muX(muW_use_color(R, NULL, MU_COLOR_RESET));
            muX(muW_draw(R, MU_DRAW_NEWLINE, 1));
        }
        muX(muR_lineno(R, 0, false));
        muX(muR_margin(R, ll, MU_MARGIN_ARROW));
        if (lc->start_col > 0) {
            int e = (ll->info == lc->margin_label.info || !ll->draw_msg);
            muX(muW_color(R, e ? MU_COLOR_UNIMPORTANT : MU_COLOR_RESET));
            if (e) muX(muW_draw(R, MU_DRAW_ELLIPSIS, 1));
            else muX(muW_draw(R, MU_DRAW_SPACE, R->ellipsis_width));
        }
        for (col = lc->start_col; col < lc->arrow_len; ++col) {
            int w = (col < col_max ? (wc[col + 1] - wc[col]) : 1);
            int lw = ll->info->label->width;
            int is_hbar = (col > ll->col) != ll->info->multi
                       || (ll->draw_msg && lw && col > ll->col);
            const mu_LabelInfo *vbar = muC_get_vbar(R, row, col);
            if (col == ll->col && lc->margin_label.info != ll->info) {
                mu_CharSet draw = MU_DRAW_RBOT;
                if (!ll->info->multi) draw = MU_DRAW_LBOT;
                else if (ll->draw_msg)
                    draw = (lw ? MU_DRAW_MBOT : MU_DRAW_RBOT);
                muX(muW_use_color(R, ll->info->label, MU_COLOR_LABEL));
                muX(muW_draw(R, draw, w));
                muX(muW_draw(R, MU_DRAW_HBAR, w - 1));
            } else if (vbar && col != ll->col) {
                mu_CharSet draw = MU_DRAW_VBAR, pad = MU_DRAW_SPACE;
                if (is_hbar) {
                    draw = MU_DRAW_XBAR;
                    if (R->config->cross_gap) draw = pad = MU_DRAW_HBAR;
                } else if (vbar->multi && first && R->config->compact)
                    draw = MU_DRAW_UARROW;
                muX(muW_use_color(R, vbar->label, MU_COLOR_LABEL));
                muX(muW_draw(R, draw, 1));
                muX(muW_draw(R, pad, w - 1));
            } else if (is_hbar) {
                muX(muW_use_color(R, ll->info->label, MU_COLOR_LABEL));
                muX(muW_draw(R, MU_DRAW_HBAR, w));
            } else {
                muX(muW_use_color(R, NULL, MU_COLOR_RESET));
                muX(muW_draw(R, MU_DRAW_SPACE, w));
            }
        }
        first = 0;
        muX(muW_use_color(R, NULL, MU_COLOR_RESET));
        if (ll->draw_msg) {
            muX(muW_draw(R, MU_DRAW_SPACE, 1));
            muX(muW_write(R, ll->info->label->message));
        }
        muX(muW_draw(R, MU_DRAW_NEWLINE, 1));
    }
    return MU_OK;
}

static int muR_cluster(mu_Report *R, unsigned line_no, mu_Slice data) {
    const mu_LabelCluster *lc = R->cur_cluster;
    muX(muR_lineno(R, line_no, 0));
    muX(muR_margin(R, NULL, MU_MARGIN_LINE));
    if (lc->start_col > 0) {
        muX(muW_color(R, MU_COLOR_UNIMPORTANT));
        muX(muW_draw(R, MU_DRAW_ELLIPSIS, 1));
        muX(muW_color(R, MU_COLOR_RESET));
    }
    muX(muR_line(R, data));
    if (lc->end_col < R->cur_line->len) {
        muX(muW_color(R, MU_COLOR_UNIMPORTANT));
        muX(muW_draw(R, MU_DRAW_ELLIPSIS, 1));
        muX(muW_color(R, MU_COLOR_RESET));
    }
    muX(muW_draw(R, MU_DRAW_NEWLINE, 1));
    return muR_arrows(R);
}

static int muR_lines(mu_Report *R) {
    int is_ellipsis = 0;
    const mu_Group *g = R->cur_group;
    unsigned line_start = g->src->line_from_chars(g->src, g->start_char, NULL);
    unsigned line_end = g->src->line_from_chars(g->src, g->end_char, NULL);
    unsigned line_no;
    for (line_no = line_start; line_no <= line_end; ++line_no) {
        const mu_Line *line = g->src->get_line_info(g->src, line_no);
        R->cur_line = line;
        if (muC_fill_llcache(R)) {
            unsigned i, size;
            mu_Slice data = g->src->get_line(g->src, line_no);
            if (R->config->limit_width > 0)
                muC_fill_widthcache(R, line->len, data);
            muC_fill_cluster(R);
            for (i = 0, size = muA_size(R->clusters); i < size; i++) {
                mu_LabelCluster *lc = &R->clusters[i];
                R->cur_cluster = lc;
                if (R->config->limit_width > 0) muC_calc_colrange(R, lc);
                muX(muR_cluster(R, line_no, data));
            }
        } else if (!is_ellipsis && muM_line_in_label(line, g->multi_labels)) {
            muX(muR_lineno(R, 0, 0));
            R->cur_cluster = NULL;
            muX(muR_margin(R, NULL, MU_MARGIN_ELLIPSIS));
            muX(muW_draw(R, MU_DRAW_NEWLINE, 1));
        } else if (!is_ellipsis && !R->config->compact) {
            muX(muR_lineno(R, 0, 0));
            muX(muW_draw(R, MU_DRAW_NEWLINE, 1));
        }
        is_ellipsis = (muA_size(R->clusters) == 0);
    }
    return MU_OK;
}

static int muR_help_or_note(mu_Report *R, int is_help, mu_Slice *msgs) {
    const mu_Slice st = is_help ? muD_literal("Help") : muD_literal("Note");
    char buf[32];
    unsigned i, size;
    for (i = 0, size = muA_size(msgs); i < size; ++i) {
        mu_Slice t = st, msg;
        if (size > 1) t = muD_snprintf(buf, sizeof(buf), "%s %u", st.p, i + 1);
        if (!R->config->compact) {
            muX(muR_lineno(R, 0, false));
            muX(muW_draw(R, MU_DRAW_NEWLINE, 1));
        }
        for (msg = msgs[i];; msg.p = msg.e + 1) {
            if (!(msg.e = strchr(msg.p, '\n'))) msg.e = msgs[i].e;
            muX(muR_lineno(R, 0, false));
            muX(muW_color(R, MU_COLOR_NOTE));
            if (msg.p > msgs[i].p)
                muX(muW_draw(R, MU_DRAW_SPACE, muD_bytelen(t)));
            else {
                muX(muW_write(R, t));
                muX(muW_draw(R, MU_DRAW_COLON, 1));
                muX(muW_draw(R, MU_DRAW_SPACE, 1));
            }
            muX(muW_write(R, msg));
            muX(muW_color(R, MU_COLOR_RESET));
            muX(muW_draw(R, MU_DRAW_NEWLINE, 1));
            if (msg.e >= msgs[i].e) break;
        }
    }
    return MU_OK;
}

static int muR_footer(mu_Report *R) {
    muX(muR_help_or_note(R, 1, R->helps));
    muX(muR_help_or_note(R, 0, R->notes));
    if (muA_size(R->groups) > 0 && !R->config->compact) {
        muX(muW_color(R, MU_COLOR_MARGIN));
        muX(muW_draw(R, MU_DRAW_HBAR, R->line_no_width + 2));
        muX(muW_draw(R, MU_DRAW_RBOT, 1));
        muX(muW_color(R, MU_COLOR_RESET));
        muX(muW_draw(R, MU_DRAW_NEWLINE, 1));
    }
    return MU_OK;
}

static int muR_report(mu_Report *R, int pos, mu_Id src_id) {
    unsigned i, size;
    muX(muG_make_groups(R));
    muX(muR_header(R));
    for (i = 0, size = muA_size(R->groups); i < size; i++) {
        R->cur_group = &R->groups[i];
        muX(muR_reference(R, i, pos, src_id));
        muX(muR_empty_line(R));
        muX(muR_lines(R));
        if (i != size - 1) muX(muR_empty_line(R));
    }
    muX(muR_footer(R));
    return MU_OK;
}

/* API */

MU_API int mu_render(mu_Report *R, int pos, mu_Id src_id) {
    int r = muR_report(R, pos, src_id);
    /* cleanup report */
    muA_delete(R, R->sources);
    muA_delete(R, R->labels);
    muA_delete(R, R->helps);
    muA_delete(R, R->notes);
    return r;
}

MU_NS_END

#endif /* MU_IMPLEMENTATION */
