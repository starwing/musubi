#ifndef musubi_h
#define musubi_h 1

#ifndef MU_NS_BEGIN
#ifdef __cplusplus
#define MU_NS_BEGIN extern "C" {
#define MU_NS_END }
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

#define MU_CHUNK_MAX_SIZE 63

#define MU_OK 0      /* No error */
#define MU_ERR -1    /* failture */
#define MU_ERRSRC -2 /* source ID out of range */

MU_NS_BEGIN

typedef enum mu_Kind {
    MU_KIND_ERROR,
    MU_KIND_WARNING,
    MU_KIND_CUSTOM,
} mu_Kind;

typedef enum mu_IndexType {
    MU_INDEX_BYTE,
    MU_INDEX_CHAR,
} mu_IndexType;

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
    MU_DRAW_COUNT,
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

typedef char mu_ColorCode[32];

struct mu_Config {
    int cross_gap;        /* show crossing gaps in cross arrows */
    int compact;          /* whether to use compact mode */
    int underlines;       /* whether to draw underlines for labels */
    int multiline_arrows; /* whether to draw multiline arrows */
    unsigned tab_width;   /* number of spaces per tab */
    unsigned line_width;  /* maximum line width, or 0 for no limit */
    unsigned ambiwidth;   /* how to treat ambiguous width characters */

    mu_LabelAttach label_attach; /* where to attach inline labels */
    mu_IndexType index_type;     /* index type for label positions */

    mu_Color *color; /* a color function or NULL for no color */
    void *color_ud;  /* user data for the color function */

    mu_ColorCode color_code; /* color code storage for the color function */
    mu_Chunk char_set[MU_DRAW_COUNT]; /* character set to use */
};

/* color generator */

MU_API void mu_colorgen_init(mu_ColorGen *cg, float min_brightness);
MU_API void mu_colorgen_next(mu_ColorGen *cg, mu_ColorCode *out);
MU_API mu_Chunk mu_colorgen_color(void *ud, mu_ColorKind kind);

struct mu_ColorGen {
    int state[3];         /* internal state */
    float min_brightness; /* minimum brightness */
};

/* source */

#define mu_source_offset(src, offset) ((src)->line_no_offset = (offset))

MU_API int mu_source(mu_Report *R, mu_Source *src);
MU_API int mu_memory_source(mu_Source *src, const char *name, const char *data,
                            size_t len);

#if !MU_NO_STDIO
MU_API int mu_file_source(mu_Source *src, const char *filename, FILE *fp);
#endif /* !MU_NO_STDIO */

struct mu_Line {
    unsigned offset; /* character offset of this line in the original source */
    unsigned len;    /* character length of this line in the original source */
    unsigned byte_offset; /* byte offset of this line in the original source */
    unsigned byte_len;    /* byte length of this line in the original source */
    unsigned newline;     /* extra length (usually a newline) after this line */
};

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
    unsigned (*line_from_chars)(mu_Source *src, unsigned char_pos,
                                const mu_Line **out);
    unsigned (*line_from_bytes)(mu_Source *src, unsigned byte_pos,
                                const mu_Line **out);
};

MU_NS_END

#endif /* musubi_h */

#if !defined(mu_implementation) && defined(MU_IMPLEMENTATION)
#define mu_implementation 1

#include <assert.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

#ifndef MU_MIN_FILENAME_WIDTH
#define MU_MIN_FILENAME_WIDTH 8
#endif /* MU_MIN_FILENAME_WIDTH */

typedef struct mu_Label {
    void *ud;           /* user data for the color function */
    mu_Color *color;    /* the color for this label */
    mu_Slice message;   /* the message to display for this label */
    unsigned start_pos; /* start position in the source */
    unsigned end_pos;   /* end position in the source */
    unsigned width;     /* display width of the message */
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

typedef struct mu_SourceGroup {
    mu_Source *src;             /* source of this group */
    mu_LabelInfo *labels;       /* labels in this group */
    mu_LabelInfo *multi_labels; /* multi-line labels in this group */
    unsigned start_char;        /* start char position of this group */
    unsigned end_char;          /* end char position of this group */
} mu_SourceGroup;

typedef struct mu_LineLabel {
    mu_LabelInfo *info; /* label info associated with this label */
    unsigned col;       /* column position in this line */
    int draw_msg;       /* whether to draw the message in this line */
} mu_LineLabel;

typedef struct mu_LabelCluster {
    mu_Line line;               /* line the cluster represents */
    mu_LineLabel *margin_label; /* margin label for this line */
    mu_LineLabel *line_labels;  /* labels in this line */
    int arrow_len;              /* length of the arrows line */
    int min_col;                /* first column of labels in this line */
    int max_msg_width;          /* maximum message width in this line */
    int start_col;              /* start column of this cluster */
    int end_col;                /* end column of this cluster */
} mu_LabelCluster;

struct mu_Report {
    void *ud;
    mu_Allocf *allocf;
    mu_Config *config;

    /* rendering context */
    void *writer_ud;
    mu_Writer *writer;
    mu_Label *cur_color_label;   /* current color label */
    mu_ColorKind cur_color_kind; /* current color kind */
    mu_SourceGroup *groups;      /* groups of sources */
    mu_LabelCluster *clusters;   /* current label clusters for rendering */
    int line_no_width;           /* maximum width of line number */
    int ellipsis_width;          /* display width of ellipsis */

    /* report details */
    mu_Kind kind;
    mu_Source *sources;
    mu_Label *labels;
    mu_Slice code;
    mu_Slice kind_message;
    mu_Slice message;
    mu_Slice *helps;
    mu_Slice *notes;
};

#define mu_min(a, b) ((a) < (b) ? (a) : (b))
#define mu_max(a, b) ((a) > (b) ? (a) : (b))

/* array */

#define MU_MIN_CAPACITY 8
#define MU_MAX_CAPACITY (1u << 30)

#define muA_rawH(A) (assert(A), (mu_ArrayHeader *)((A) - 1))
#define muA_size(A) ((A) ? muA_rawH(A)->size : 0)
#define muA_delete(R, A) (muA_delete_(R, (void *)(A), sizeof(*(A))), (A) = NULL)
#define muA_push(R, A) \
    (muA_reserve_(R, (void **)&(A), sizeof(*(A)), 1), &(A)[muA_rawH(A)->size++])
#define muA_reserve(R, A, N) \
    (muA_reserve_(R, (void **)&(A), sizeof(*(A)), (N)), &(A)[muA_rawH(A)->size])
#define muA_addsize(R, A, N) (muA_rawH(A)->size += (N))
#define muA_reset(R, A) (muA_rawH(A)->size = 0)

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

#define muU_tablesize(t) (sizeof(t) / sizeof((t)[0]))
#define muU_literal(lit) muU_slice("" lit, sizeof(lit) - 1)

/* clang-format off */
static size_t muU_bytelen(mu_Slice s) { return (size_t)(s.e - s.p); }

static mu_Slice muU_slice(const char *p, size_t len)
{ mu_Slice s; s.p = p, s.e = p + len; return s; }
/* clang-format on */

static mu_Slice muU_snprintf(char *buf, size_t bufsize, const char *fmt, ...) {
    va_list args;
    int n;
    va_start(args, fmt);
    n = vsnprintf(buf, bufsize, fmt, args);
    va_end(args);
    return muU_slice(buf, n > 0 ? mu_min((size_t)n, bufsize - 1) : 0);
}

static unsigned muU_count(mu_Slice s, size_t byte_pos) {
    size_t i = 0, len = muU_bytelen(s);
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

static utfint muU_decode(mu_Slice *s) {
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

static utfint muU_rdecode(mu_Slice *s) {
    mu_Slice ns = *s;
    while (s->p < s->e && ((s->e[-1] & 0xC0) == 0x80)) --s->e;
    s->e = s->p < s->e ? s->e - 1 : s->p;
    return ns.p = s->e, muU_decode(&ns);
}

static int muU_find(range_table *t, size_t size, utfint ch) {
    size_t begin = 0, end = size;
    while (begin < end) {
        size_t mid = (begin + end) / 2;
        if (t[mid].last < ch) begin = mid + 1;
        else if (t[mid].first > ch) end = mid;
        else return (ch - t[mid].first) % t[mid].step == 0;
    }
    return 0;
}

static int muU_width(utfint ch, int ambiwidth) {
    if (muU_find(doublewidth_table, muU_tablesize(doublewidth_table), ch))
        return 2;
    if (muU_find(ambiwidth_table, muU_tablesize(ambiwidth_table), ch))
        return ambiwidth;
    if (muU_find(compose_table, muU_tablesize(compose_table), ch)) return 0;
    if (muU_find(unprintable_table, muU_tablesize(unprintable_table), ch))
        return 0;
    return 1;
}

static int muU_strwidth(mu_Slice s, int ambiwidth) {
    int width = 0;
    while (s.p < s.e) width += muU_width(muU_decode(&s), ambiwidth);
    return width;
}

static int muU_widthlimit(mu_Slice *s, int width, int ambiwidth) {
    mu_Slice o = *s;
    int w;
    if (width >= 0) {
        const char *start = s->p, *prev = s->p;
        for (; s->p < s->e && width != 0; width -= w) {
            w = muU_width(muU_decode((prev = s->p, s)), ambiwidth);
            if (width < w) break;
        }
        return *s = muU_slice(start, prev - start), width;
    } else {
        const char *end = s->e, *prev = s->e;
        for (; s->p < s->e && width != 0; width += w) {
            w = muU_width(muU_rdecode((prev = s->e, s)), ambiwidth);
            if (-width < w) break;
        }
        return *s = muU_slice(prev, end - prev), width;
    }
}

/* color generator */

MU_API void mu_colorgen_init(mu_ColorGen *cg, float min_brightness) {
    cg->state[0] = 30000, cg->state[1] = 15000, cg->state[2] = 35000;
    cg->min_brightness = min_brightness;
}

MU_API void mu_colorgen_next(mu_ColorGen *cg, mu_ColorCode *out) {
    int i, code = 16, len;
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
    len = snprintf(*out + 1, sizeof(mu_ColorCode) - 1, "\x1b[38;5;%dm", code);
    (*out)[0] = (assert(len <= sizeof(mu_ColorCode) - 1), (char)len);
}

MU_API mu_Chunk mu_colorgen_color(void *ud, mu_ColorKind k) {
    mu_Chunk *code = (mu_Chunk *)ud;
    if (k == MU_COLOR_RESET) return (mu_Chunk) "4\x1b[0m";
    return (mu_Chunk)ud;
}

/* writer */

#define MU_PADDING_BUF_SIZE 64

#define muC(code)                 \
    do {                          \
        int r = (code);           \
        if (r != MU_OK) return r; \
    } while (0)

#define muW_literal(R, str) muW_write(R, muU_literal(str))

/* clang-format off */
static int muW_write(mu_Report *R, mu_Slice s)
{ return (assert(R->writer), R->writer(R->writer_ud, s.p, muU_bytelen(s))); }
/* clang-format on */

static int muW_color(mu_Report *R, mu_ColorKind kind) {
    mu_Color *color = R->config->color;
    void *ud = R->config->color_ud;
    if (R->cur_color_label && R->cur_color_label->color)
        color = R->cur_color_label->color, ud = R->cur_color_label->ud;
    if (color) {
        mu_Chunk code;
        if (kind != R->cur_color_kind) {
            code = color(ud, MU_COLOR_RESET);
            muC(muW_write(R, muU_slice(code + 1, (size_t)*code)));
        }
        if (kind != MU_COLOR_RESET) {
            code = color(ud, kind);
            return muW_write(R, muU_slice(code + 1, (size_t)*code));
        }
    }
    return R->cur_color_kind = kind, MU_OK;
}

static void muW_usecolor(mu_Report *R, mu_Label *label) {
    if (R->cur_color_label != label) muW_color(R, MU_COLOR_RESET);
    R->cur_color_label = label;
}

static int muW_padding(mu_Report *R, int count, mu_Chunk chunk) {
    if (chunk == NULL || chunk[0] == 1) {
        char pad[MU_PADDING_BUF_SIZE];
        memset(pad, chunk ? chunk[0] : ' ', mu_min(sizeof(pad), count));
        while (count >= MU_PADDING_BUF_SIZE) {
            muC(muW_write(R, muU_slice(pad, sizeof(pad))));
            count -= MU_PADDING_BUF_SIZE;
        }
        if (count > 0) muC(muW_write(R, muU_slice(pad, count)));
    } else {
        int i;
        for (i = 0; i < count; ++i)
            muC(muW_write(R, muU_slice(chunk + 1, chunk[0])));
    }
    return MU_OK;
}

static int muW_draw(mu_Report *R, mu_CharSet cs, unsigned count) {
    assert(cs < MU_DRAW_COUNT);
    return muW_padding(R, count, R->config->char_set[cs]);
}

/* label info */

static unsigned muI_bytes_to_chars(mu_Report *R, mu_Source *src, unsigned pos) {
    const mu_Line *line;
    unsigned line_no = src->line_from_bytes(src, pos, &line);
    mu_Slice s = src->get_line(src, line_no);
    return line->offset + muU_count(s, pos - line->byte_offset);
}

static int muI_init(mu_Report *R, mu_Label *label, mu_LabelInfo *out) {
    unsigned start = label->start_pos, end = label->end_pos;
    const mu_Line *start_line, *end_line;
    mu_Source *src;
    if (label->src_id >= muA_size(R->sources)) return MU_ERRSRC;
    src = &R->sources[label->src_id];
    if (R->config->index_type == MU_INDEX_CHAR)
        out->start_char = start, out->end_char = end;
    else {
        out->start_char = muI_bytes_to_chars(R, src, start);
        out->end_char = muI_bytes_to_chars(R, src, end);
    }
    return MU_OK;
}

/* source group */

static void muG_addinfo(mu_Report *R, unsigned i, mu_LabelInfo *li) {
    if (i == muA_size(R->groups)) {
        mu_SourceGroup *group = muA_push(R, R->groups);
        memset(group, 0, sizeof(mu_SourceGroup));
        group->src = &R->sources[li->label->src_id];
        group->start_char = li->start_char;
        group->end_char = li->end_char;
    } else {
        mu_SourceGroup *g = &R->groups[i];
        g->start_char = mu_min(g->start_char, li->start_char);
        g->end_char = mu_max(g->end_char, li->end_char);
    }
    if (li->multi) *muA_push(R, R->groups[i].multi_labels) = *li;
    else *muA_push(R, R->groups[i].labels) = *li;
}

static int muI_cmp(const void *lhf, const void *rhf) {
    const mu_LabelInfo *l = (const mu_LabelInfo *)lhf;
    const mu_LabelInfo *r = (const mu_LabelInfo *)rhf;
    int llen = l->end_char - l->start_char;
    int rlen = r->end_char - r->start_char;
    return rlen - llen;
}

static int muG_makegroups(mu_Report *R, int pos, mu_Id src_id) {
    unsigned i, len, j, glen;
    muA_reset(R, R->groups);
    for (i = 0, len = muA_size(R->labels); i < len; i++) {
        mu_Label *label = &R->labels[i];
        mu_LabelInfo info;
        if (muI_init(R, label, &info) != MU_OK) continue;
        for (j = 0, glen = muA_size(R->groups); j < glen; j++)
            if (R->groups[j].src->id == label->src_id) break;
        muG_addinfo(R, j, &info);
    }
    for (i = 0, len = muA_size(R->groups); i < len; i++) {
        mu_LabelInfo *li = R->groups[i].multi_labels;
        qsort(li, muA_size(li), sizeof(mu_LabelInfo), muI_cmp);
    }
    return MU_OK;
}

/* rendering */

static int muR_header(mu_Report *R) {
    switch (R->kind) {
    case MU_KIND_ERROR:   muC(muW_color(R, MU_COLOR_ERROR)); break;
    case MU_KIND_WARNING: muC(muW_color(R, MU_COLOR_WARNING)); break;
    default:              muC(muW_color(R, MU_COLOR_KIND)); break;
    }
    if (R->code.p) {
        muC(muW_literal(R, "["));
        muC(muW_write(R, R->code));
        muC(muW_literal(R, "]"));
    }
    muC(muW_write(R, R->kind_message));
    muC(muW_literal(R, ": "));
    muC(muW_color(R, MU_COLOR_RESET));
    if (R->message.p) {
        muC(muW_literal(R, " "));
        muC(muW_write(R, R->message));
    }
    return muW_literal(R, "\n");
}

typedef struct muR_refCtx {
    mu_Report *R;
    mu_Source *src;
    mu_Slice name, loc;
    unsigned gidx;
    int ellipsis;
} muR_refCtx;

static void muG_calclocation(muR_refCtx *ctx, int pos, char *out, size_t size) {
    mu_SourceGroup *g = &ctx->R->groups[ctx->gidx];
    unsigned line_no = 0, col = 0;
    const mu_Line *line;
    assert(pos >= 0);
    if (ctx->src == g->src && ctx->R->config->index_type == MU_INDEX_BYTE)
        pos = muI_bytes_to_chars(ctx->R, ctx->src, (unsigned)pos);
    else {
        if (ctx->src != g->src)
            pos = muA_size(g->labels) ? (int)g->labels[0].start_char : -1;
        line_no = ctx->src->line_from_chars(ctx->src, (unsigned)pos, &line);
    }
    col = pos - line->offset + 1;
    line_no += ctx->src->line_no_offset + 1;
    ctx->loc = muU_snprintf(out, size, "%u:%u", line_no, col);
}

static int muR_reference_aux(mu_Report *R, const muR_refCtx *ctx) {
    muC(muW_padding(R, R->line_no_width + 2, NULL));
    muC(muW_color(R, MU_COLOR_MARGIN));
    muC(muW_draw(R, ctx->gidx ? MU_DRAW_VBAR : MU_DRAW_LTOP, 1));
    muC(muW_draw(R, MU_DRAW_HBAR, 1));
    muC(muW_draw(R, MU_DRAW_LBOX, 1));
    muC(muW_color(R, MU_COLOR_RESET));
    muC(muW_literal(R, " "));
    if (ctx->ellipsis) {
        muC(muW_padding(R, ctx->ellipsis - 1, NULL));
        muC(muW_draw(R, MU_DRAW_ELLIPSIS, 1));
    }
    muC(muW_write(R, ctx->name));
    muC(muW_literal(R, ":"));
    muC(muW_write(R, ctx->loc));
    muC(muW_literal(R, " "));
    muC(muW_color(R, MU_COLOR_MARGIN));
    muC(muW_draw(R, MU_DRAW_RBOX, 1));
    muC(muW_color(R, MU_COLOR_RESET));
    return MU_OK;
}

static int muR_reference(mu_Report *R, unsigned gidx, int pos, mu_Id src_id) {
    muR_refCtx ctx;
    char loc_buf[256];
    assert(src_id < muA_size(R->sources));
    assert(gidx < muA_size(R->groups));
    memset(&ctx, 0, sizeof(ctx));
    ctx.R = R, ctx.src = &R->sources[src_id], ctx.gidx = gidx;
    if (pos < 0) ctx.loc = muU_literal("?:?");
    else muG_calclocation(&ctx, pos, loc_buf, sizeof(loc_buf));
    ctx.name = ctx.src->name;
    if (R->config->line_width) {
        int id_width = muU_strwidth(ctx.name, R->config->ambiwidth);
        int fixed = (int)muU_bytelen(ctx.loc) + R->line_no_width + 9;
        int line_width = (int)R->config->line_width;
        if (id_width + fixed > line_width) {
            unsigned ambiwidth = R->config->ambiwidth;
            int avail = line_width - fixed - R->ellipsis_width;
            avail = mu_max(avail, MU_MIN_FILENAME_WIDTH);
            ctx.ellipsis = muU_widthlimit(&ctx.name, -avail, ambiwidth) + 1;
        }
    }
    return muR_reference_aux(R, &ctx);
}

static int muR_empty_line(mu_Report *R) {
    if (R->config->compact) return MU_OK;
    muW_padding(R, R->line_no_width + 2, NULL);
    muW_color(R, MU_COLOR_MARGIN);
    muC(muW_draw(R, MU_DRAW_VBAR, 1));
    muW_color(R, MU_COLOR_RESET);
    return muW_literal(R, "\n");
}

static int muR_lineno(mu_Report *R, unsigned line_no, int is_ellipsis) {
    if (line_no && is_ellipsis) {
        char buf[32];
        mu_Slice ln = muU_snprintf(buf, sizeof(buf), "%u", line_no);
        muC(muW_padding(R, R->line_no_width - muU_bytelen(ln), NULL));
        muC(muW_color(R, MU_COLOR_MARGIN));
        muC(muW_write(R, ln));
        muC(muW_literal(R, " "));
        muC(muW_draw(R, MU_DRAW_VBAR, 1));
    } else {
        muC(muW_padding(R, R->line_no_width + 2, NULL));
        muC(muW_color(R, MU_COLOR_SKIPPED_MARGIN));
        muC(muW_draw(R, is_ellipsis ? MU_DRAW_VBAR_GAP : MU_DRAW_VBAR, 1));
    }
    muC(muW_color(R, MU_COLOR_RESET));
    return R->config->compact ? MU_OK : muW_literal(R, " ");
}

static int muR_lines(mu_Report *R, mu_SourceGroup *group) {}

static int muR_help_or_note(mu_Report *R, int is_help, mu_Slice *msgs) {
    const mu_Slice st = is_help ? muU_literal("Help") : muU_literal("Note");
    char buf[32];
    unsigned i, len;
    for (i = 0, len = muA_size(msgs); i < len; ++i) {
        mu_Slice t = st, msg;
        if (len > 1) t = muU_snprintf(buf, sizeof(buf), "%s %u", st.p, i + 1);
        if (!R->config->compact) {
            muC(muR_lineno(R, 0, false));
            muC(muW_literal(R, "\n"));
        }
        for (msg = msgs[i];; msg.p = msg.e + 1) {
            if (!(msg.e = strchr(msg.p, '\n'))) msg.e = msgs[i].e;
            muC(muR_lineno(R, 0, false));
            muC(muW_color(R, MU_COLOR_NOTE));
            if (msg.p > msgs[i].p) muC(muW_padding(R, muU_bytelen(t), NULL));
            else {
                muC(muW_write(R, t));
                muC(muW_literal(R, ": "));
            }
            muC(muW_write(R, msg));
            muC(muW_color(R, MU_COLOR_RESET));
            muC(muW_literal(R, "\n"));
            if (msg.e >= msgs[i].e) break;
        }
    }
    return MU_OK;
}

static int muR_footer(mu_Report *R) {
    muC(muR_help_or_note(R, 1, R->helps));
    muC(muR_help_or_note(R, 0, R->notes));
    if (muA_size(R->groups) > 0 && !R->config->compact) {
        muC(muW_color(R, MU_COLOR_MARGIN));
        muC(muW_draw(R, MU_DRAW_HBAR, R->line_no_width + 2));
        muC(muW_draw(R, MU_DRAW_RBOT, 1));
        muC(muW_color(R, MU_COLOR_RESET));
        muC(muW_literal(R, "\n"));
    }
    return MU_OK;
}

static int muR_report(mu_Report *R, int pos, mu_Id src_id) {
    unsigned i, len;
    muC(muG_makegroups(R, pos, src_id));
    muC(muR_header(R));
    for (i = 0, len = muA_size(R->groups); i < len; i++) {
        muC(muR_reference(R, i, pos, src_id));
        muC(muR_empty_line(R));
        muC(muR_lines(R, &R->groups[i]));
        if (i != len - 1) muC(muR_empty_line(R));
    }
    muC(muR_footer(R));
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

#endif /* MU_IMPLEMENTATION */