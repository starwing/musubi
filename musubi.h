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

#define MU_VERSION_MAJOR 0
#define MU_VERSION_MINOR 1
#define MU_VERSION_PATCH 0

#define MU_S(x) #x
#define MU_VERSION \
    MU_S(MU_VERSION_MAJOR) "." MU_S(MU_VERSION_MINOR) "." MU_S(MU_VERSION_PATCH)

#define MU_CHUNK_MAX_SIZE  63
#define MU_COLOR_CODE_SIZE 32

#define MU_OK       (0)  /* No error */
#define MU_ERRPARAM (-1) /* invalid parameter */
#define MU_ERRSRC   (-2) /* source ID out of range */
#define MU_ERRFILE  (-3) /* errors in file source */

MU_NS_BEGIN

typedef enum mu_Level { MU_ERROR, MU_WARNING, MU_CUSTOM_LEVEL } mu_Level;

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

typedef enum mu_Draw {
    MU_DRAW_SPACE,
    MU_DRAW_NEWLINE,
    MU_DRAW_LBOX,
    MU_DRAW_RBOX,
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
    MU_DRAW_LCROSS,
    MU_DRAW_RCROSS,
    MU_DRAW_UNDERBAR,
    MU_DRAW_UNDERLINE,
    MU_DRAW_ELLIPSIS,
    MU_DRAW_COUNT
} mu_Draw;

typedef unsigned    mu_Id;
typedef const char *mu_Chunk; /* first char is length */

typedef struct mu_Report     mu_Report;
typedef struct mu_Config     mu_Config;
typedef struct mu_ColorGen   mu_ColorGen;
typedef struct mu_Source     mu_Source;
typedef struct mu_BareSource mu_BareSource;
typedef struct mu_Line       mu_Line;
typedef struct mu_Slice      mu_Slice;

typedef void    *mu_Allocf(void *ud, void *p, size_t nsize, size_t osize);
typedef mu_Chunk mu_Color(void *ud, mu_ColorKind kind);
typedef int      mu_Writer(void *ud, const char *data, size_t len);

/* report construction and configuration */

MU_API mu_Report *mu_new(mu_Allocf *allocf, void *ud);
MU_API void       mu_reset(mu_Report *R);
MU_API void       mu_delete(mu_Report *R);

MU_API int mu_config(mu_Report *R, const mu_Config *config);
MU_API int mu_label(mu_Report *R, size_t start, size_t end, mu_Id src_id);
MU_API int mu_message(mu_Report *R, const char *msg, int width);
MU_API int mu_color(mu_Report *R, mu_Color *color, void *ud);
MU_API int mu_order(mu_Report *R, int order);
MU_API int mu_priority(mu_Report *R, int priority);

MU_API int mu_title(mu_Report *R, mu_Level l, const char *cl, const char *msg);
MU_API int mu_code(mu_Report *R, const char *code);
MU_API int mu_help(mu_Report *R, const char *help_msg);
MU_API int mu_note(mu_Report *R, const char *note_msg);

/* rendering */

MU_API int mu_source(mu_Report *R, mu_Source *src);
MU_API int mu_writer(mu_Report *R, mu_Writer *writer, void *ud);
MU_API int mu_render(mu_Report *R, ssize_t pos, mu_Id src_id);

/* custom configuration */

typedef mu_Chunk mu_Charset[MU_DRAW_COUNT];

MU_API const mu_Charset *mu_ansi(void);
MU_API const mu_Charset *mu_unicode(void);

MU_API mu_Chunk mu_default_color(void *ud, mu_ColorKind kind);

MU_API void mu_initconfig(mu_Config *config);

struct mu_Config {
    int cross_gap;        /* show crossing gaps in cross arrows */
    int compact;          /* whether to use compact mode */
    int underlines;       /* whether to draw underlines for labels */
    int multiline_arrows; /* whether to draw multiline arrows */
    int tab_width;        /* number of spaces per tab */
    int limit_width;      /* maximum line width, or 0 for no limit */
    int ambiwidth;        /* how to treat ambiguous width characters */

    mu_LabelAttach label_attach; /* where to attach inline labels */
    mu_IndexType   index_type;   /* index type for label positions */

    mu_Color *color;    /* a color function or NULL for no color */
    void     *color_ud; /* user data for the color function */

    const mu_Charset *char_set; /* character set to use */
};

/* color generator */

typedef char mu_ColorCode[MU_COLOR_CODE_SIZE];

MU_API void mu_initcolorgen(mu_ColorGen *cg, float min_brightness);
MU_API void mu_gencolor(mu_ColorGen *cg, mu_ColorCode *out);

MU_API mu_Chunk mu_fromcolorcode(void *ud, mu_ColorKind kind);

struct mu_ColorGen {
    unsigned short state[3];       /* internal state */
    float          min_brightness; /* minimum brightness */
};

/* source */

#define mu_source_offset(src, offset) ((src)->line_no_offset = (offset))

MU_API mu_Source *mu_newsource(mu_Report *R, size_t size, const char *name);

MU_API mu_Source *mu_memory_source(mu_Report *R, const char *data, size_t len,
                                   const char *name);

#if !MU_NO_STDIO
MU_API mu_Source *mu_file_source(mu_Report *R, FILE *fp, const char *name);
#endif /* !MU_NO_STDIO */

#if !MU_NO_BARE_VTABLE /* clang-format off */
/* all routines below requires `src` is `mu_BareSource` */
MU_API void mu_updatelines(mu_Source *src, mu_Slice data);
MU_API void mu_freesource(mu_Source *src);
MU_API const mu_Line *mu_getline(mu_Source *src, unsigned line_no);
MU_API unsigned mu_lineforchars(mu_Source *src, size_t char_pos, const mu_Line **out);
MU_API unsigned mu_lineforbytes(mu_Source *src, size_t byte_pos, const mu_Line **out);
#endif /* !MU_NO_BARE_VTABLE *//* clang-format on */

struct mu_Slice {
    const char *p, *e;
};

struct mu_Source {
    void    *ud;             /* user data for this source */
    mu_Slice name;           /* source name slice */
    int      line_no_offset; /* line number offset for this source */
    mu_Id    id;   /* source id, written by `mu_source()`, start from 0 */
    int      gidx; /* group index, -1 for "should call free", -2 for no use */

    int (*init)(mu_Source *src);
    void (*free)(mu_Source *src);

    mu_Slice (*get_line)(mu_Source *src, unsigned line_no);
    const mu_Line *(*get_line_info)(mu_Source *src, unsigned line_no);
    unsigned (*line_for_chars)(mu_Source *src, size_t char_pos,
                               const mu_Line **out);
    unsigned (*line_for_bytes)(mu_Source *src, size_t byte_pos,
                               const mu_Line **out);
};

struct mu_BareSource {
    mu_Source  src;   /* base source */
    size_t     size;  /* size of bare source object */
    mu_Report *R;     /* report associated with this source */
    mu_Line   *lines; /* line cache */
};

struct mu_Line {
    size_t   offset; /* character offset of this line in the original source */
    size_t   byte_offset; /* byte offset of this line in the original source */
    unsigned len; /* character length of this line in the original source */
    unsigned byte_len; /* byte length of this line in the original source */
    unsigned newline;  /* extra length (usually a newline) after this line */
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
#define MU_MIN_FILENAME_WIDTH 12
#endif /* MU_MIN_FILENAME_WIDTH */

#define mu_min(a, b)    ((a) < (b) ? (a) : (b))
#define mu_max(a, b)    ((a) > (b) ? (a) : (b))
#define mu_asc(a, b, c) ((a) <= (b) && (b) <= (c))

#if !MU_NO_DEBUG
#define LOG(fmt, ...) (fprintf(stderr, fmt "\n", ##__VA_ARGS__))
#else
#define LOG(...) ((void)0)
#endif /* !MU_NO_DEBUG */

#define muX(code)                                                           \
    do {                                                                    \
        int r = (code);                                                     \
        if (r != MU_OK)                                                     \
            return LOG("muX: error %d at %s:%d", r, __FILE__, __LINE__), r; \
    } while (0)

MU_NS_BEGIN

typedef int      mu_Width;
typedef unsigned mu_Col;

typedef struct mu_Label {
    void     *ud;        /* user data for the color function */
    mu_Color *color;     /* the color for this label */
    mu_Slice  message;   /* the message to display for this label */
    size_t    start_pos; /* start position in the source */
    size_t    end_pos;   /* end position in the source */
    mu_Width  width;     /* display width of the message, must >= 0 */
    mu_Id     src_id;    /* source id this label belongs to */
    int       order;     /* order of this label in vertical sorting */
    int priority; /* priority of this label when merging overlapping labels */
} mu_Label;

typedef struct mu_LabelInfo {
    mu_Label *label;      /* label associated with this info */
    int       multi;      /* whether this label spans multiple lines */
    size_t    start_char; /* start character position of this label */
    size_t    end_char;   /* end character position of this label */
} mu_LabelInfo;

typedef struct mu_Group {
    mu_Source    *src;          /* source of this group */
    mu_LabelInfo *labels;       /* labels in this group */
    mu_LabelInfo *multi_labels; /* multi-line labels in this group */
    size_t        first_char;   /* first char position of this group */
    size_t        last_char;    /* last char position of this group */
} mu_Group;

typedef struct mu_LineLabel {
    const mu_LabelInfo *info; /* label info associated with this label */

    /* draw_msg is 0 only if the label is multi and this line is the start */
    int    draw_msg; /* whether to draw the message in this line */
    mu_Col col;      /* column position in this line */
} mu_LineLabel;

typedef struct mu_Cluster {
    const mu_Line *line;         /* line the cluster represents */
    mu_LineLabel   margin_label; /* margin label for this line */
    mu_LineLabel  *line_labels;  /* labels in this line */

    unsigned arrow_len;     /* length of the arrows line */
    mu_Col   min_col;       /* first column of labels in this line */
    mu_Col   start_col;     /* start column of this cluster */
    mu_Col   end_col;       /* end column of this cluster */
    mu_Width max_msg_width; /* maximum message width in this line */
} mu_Cluster;

typedef struct mu_Data {
    mu_Slice s;   /* data slice */
    char    *buf; /* data buffer (a char array) */
} mu_Data;

struct mu_Report {
    void            *ud;     /* userdata for allocf */
    mu_Allocf       *allocf; /* custom allocation function */
    const mu_Config *config; /* configuration */

    /* rendering context */
    void           *writer_ud;
    mu_Writer      *writer;
    const mu_Label *cur_color_label; /* current color label */
    mu_ColorKind    cur_color_kind;  /* current color kind */
    mu_Group       *groups;          /* groups of sources */
    mu_Cluster     *clusters;        /* current label clusters for rendering */
    mu_LineLabel   *ll_cache;      /* line label cache used in `muC_assemble` */
    mu_Width       *width_cache;   /* current line width cache */
    mu_Width        line_no_width; /* maximum width of line number */
    mu_Width        ellipsis_width; /* display width of ellipsis */

    const mu_Group   *cur_group;   /* current group being rendered */
    const mu_Cluster *cur_cluster; /* current cluster being rendered */
    const mu_Line    *cur_line;    /* current line being rendered */

    /* report details */
    mu_Level    level;        /* predefined report level */
    mu_Slice    code;         /* code message shown in header */
    mu_Slice    custom_level; /* custom level shown in header */
    mu_Slice    title;        /* main title shown in header */
    mu_Source **sources;      /* sources involved in the report */
    mu_Label   *labels;       /* labels involved in the report */
    mu_Slice   *helps;        /* help messages shown in footer */
    mu_Slice   *notes;        /* note messages shown in footer */
};

/* array */

#define MU_MIN_CAPACITY 8
#define MU_MAX_CAPACITY (1u << 30)

#define muA_rawH(A)          (assert(A), ((mu_ArrayHeader *)A - 1))
#define muA_size(A)          ((A) ? muA_rawH(A)->size : 0)
#define muA_addsize(R, A, N) (muA_rawH(A)->size += (N))
#define muA_last(A)          ((A) ? &(A)[muA_rawH(A)->size - 1] : NULL)
#define muA_reset(R, A)      ((void)((A) && (muA_rawH(A)->size = 0)))

#define muA_delete(R, A) (muA_delete_(R, (void *)(A), sizeof(*(A))), (A) = NULL)
#define muA_push(R, A) \
    (muA_reserve_(R, (void **)&(A), sizeof(*(A)), 1), &(A)[muA_rawH(A)->size++])
#define muA_reserve(R, A, N) \
    (muA_reserve_(R, (void **)&(A), sizeof(*(A)), (N)), &(A)[muA_rawH(A)->size])

typedef struct mu_ArrayHeader {
    unsigned size, capacity;
} mu_ArrayHeader;

static void muA_delete_(mu_Report *R, void *A, size_t esize) {
    mu_ArrayHeader *h = A ? muA_rawH((void **)A) : NULL;
    if (h == NULL) return;
    R->allocf(R->ud, h, 0, sizeof(mu_ArrayHeader) + h->capacity * esize);
}

static void muA_reserve_(mu_Report *R, void **A, size_t esize, unsigned n) {
    mu_ArrayHeader *nh, *h = *A ? muA_rawH((void **)*A) : NULL;
    unsigned        desired = n + (h ? h->size : 0);
    if (desired > MU_MAX_CAPACITY) return (void)abort();
    if (h == NULL || desired > h->capacity) {
        size_t old_size = h ? sizeof(mu_ArrayHeader) + h->capacity * esize : 0;
        unsigned newcapa = MU_MIN_CAPACITY;
        while ((newcapa += newcapa >> 1) < desired) {}
        nh = (mu_ArrayHeader *)R->allocf(
            R->ud, h, sizeof(mu_ArrayHeader) + newcapa * esize, old_size);
        if (nh == NULL) return (void)abort();
        if (h == NULL) nh->size = 0;
        nh->capacity = newcapa;
        *A = (void *)(nh + 1);
    }
}

/* data & slice & unicode utils */

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
    int     n;
    va_start(args, fmt);
    n = vsnprintf(buf, bufsize, fmt, args);
    va_end(args);
    return muD_slice(buf, n > 0 ? mu_min((size_t)n, bufsize - 1) : 0);
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

static size_t muD_checkend(mu_Slice s) {
    const char *e = s.e;
    utfint      c;
    while (s.p < e && ((*--e & 0xC0) == 0x80)) continue;
    if ((s.p == e || (c = *e & 0xFF) < 0x80
         || ((c & 0xE0) == 0xC0 && e + 1 < s.e)
         || ((c & 0xF0) == 0xE0 && e + 2 < s.e)
         || ((c & 0xF8) == 0xF0 && e + 3 < s.e)))
        return 0;
    return (size_t)(s.e - e);
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
    return !muD_find(zerowidth_table, muD_tablesize(zerowidth_table), ch);
}

static mu_Width muD_strwidth(mu_Slice s, mu_Width ambi) {
    mu_Width w = 0;
    while (s.p < s.e) w += muD_width(muD_decode(&s), ambi);
    return w;
}

static mu_Width muD_widthlimit(mu_Slice *s, mu_Width width, mu_Width ambi) {
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
            cw = muD_width(muD_rdecode(s), ambi);
            if (-width < cw) break;
            prev = s->e;
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
    float mb, code = 16.f;
    int   i, n;
    if (!cg || !out) return;
    for (i = 0; i < 3; ++i)
        cg->state[i] += (unsigned short)(40503 * (i * 4 + 1130));
    mb = cg->min_brightness;
    code += ((float)cg->state[2] / 65535 * (1 - mb) + mb) * 5.0f;
    code += ((float)cg->state[1] / 65535 * (1 - mb) + mb) * 30.0f;
    code += ((float)cg->state[0] / 65535 * (1 - mb) + mb) * 180.0f;
    n = snprintf(*out + 1, sizeof(mu_ColorCode) - 1, "\x1b[38;5;%dm",
                 (int)code);
    (*out)[0] = (assert(n <= sizeof(mu_ColorCode) - 1), (char)n);
}

MU_API mu_Chunk mu_fromcolorcode(void *ud, mu_ColorKind k) {
    mu_Chunk *code = (mu_Chunk *)ud;
    if (k == MU_COLOR_RESET) return (mu_Chunk) "\x04\x1b[0m";
    return (mu_Chunk)ud;
}

/* writer */

/* clang-format off */
static int muW_write(mu_Report *R, mu_Slice s)
{ return (assert(R->writer), R->writer(R->writer_ud, s.p, muD_bytelen(s))); }
/* clang-format on */

static int muW_replace(mu_Report *R, mu_Slice s, char oldc, char newc) {
    while (s.p < s.e) {
        const char *p = (const char *)memchr(s.p, oldc, muD_bytelen(s));
        if (p == NULL) break;
        muX(muW_write(R, muD_slice(s.p, (size_t)(p - s.p))));
        muX(muW_write(R, muD_slice(&newc, 1)));
        s.p = p + 1;
    }
    return s.p < s.e ? muW_write(R, s) : MU_OK;
}

static int muW_color(mu_Report *R, mu_ColorKind k) {
    mu_Color *color = R->config->color;
    void     *ud = R->config->color_ud;
    if (R->cur_color_label && R->cur_color_label->color)
        color = R->cur_color_label->color, ud = R->cur_color_label->ud;
    if (color) {
        mu_Chunk code;
        if (R->cur_color_kind && k != R->cur_color_kind) {
            code = color(ud, MU_COLOR_RESET);
            muX(muW_write(R, muD_slice(code + 1, (size_t)*code)));
        }
        if (k && k != R->cur_color_kind) {
            code = color(ud, k);
            muX(muW_write(R, muD_slice(code + 1, (size_t)*code)));
        }
    }
    if (k == MU_COLOR_RESET) R->cur_color_label = NULL;
    return (R->cur_color_kind = k), MU_OK;
}

static int muW_use_color(mu_Report *R, const mu_Label *label, mu_ColorKind k) {
    if (R->cur_color_kind != MU_COLOR_RESET && R->cur_color_label != label)
        muX(muW_color(R, MU_COLOR_RESET));
    R->cur_color_label = label;
    return muW_color(R, k);
}

static int muW_draw(mu_Report *R, mu_Draw cs, int count) {
    const mu_Chunk chunk = (*R->config->char_set)[cs];
    if (chunk[0] == 1) {
        enum { MU_PADDING_BUF_SIZE = 80 };
        char pad[MU_PADDING_BUF_SIZE];
        memset(pad, chunk[1], mu_min(sizeof(pad), count));
        while (count >= (int)sizeof(pad)) {
            muX(muW_write(R, muD_slice(pad, sizeof(pad))));
            count -= sizeof(pad);
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

/* clang-format off */
static size_t muM_lineend(const mu_Line *line)
{ return line->offset + line->len; }

static mu_Col muM_col(size_t pos, const mu_LineLabel *ll, const mu_Line *line)
{ return ll->info->multi ? ll->col : pos - line->offset; }

static int muM_contains(size_t pos, const mu_Line *line)
{ return pos >= line->offset && pos < muM_lineend(line) + 1; }

static size_t muM_lastchar(const mu_LabelInfo *li)
{ return li->end_char - (li->end_char > li->start_char); }
/* clang-format on */

static mu_Width muM_marginwidth(mu_Report *R) {
    unsigned size = muA_size(R->cur_group->multi_labels);
    return (size ? size + 1 : 0) * (R->config->compact ? 1 : 2);
}

static int muM_line_in_label(const mu_Line *line, const mu_LabelInfo *li) {
    unsigned i, size;
    size_t   check = line->offset;
    for (i = 0, size = muA_size(li); i < size; ++i)
        if (mu_asc(li[i].start_char, check, muM_lastchar(&li[i]))) return 1;
    return 0;
}

static size_t muM_bytes2chars(mu_Source *src, size_t pos,
                              const mu_Line **line) {
    unsigned line_no = src->line_for_bytes(src, pos, line);
    mu_Slice s = src->get_line(src, line_no);
    size_t   r = (*line)->byte_offset;
    while (s.p < s.e && pos > 0) {
        const char *p = s.p;
        r += 1, muD_advance(&s), pos -= (size_t)(s.p - p);
    }
    return r + pos;
}

static void muM_calc_linenowidth(mu_Report *R) {
    unsigned i, size;
    mu_Width max_width = 0;
    for (i = 0, size = muA_size(R->groups); i < size; i++) {
        mu_Group      *g = &R->groups[i];
        const mu_Line *line;
        unsigned line_no = g->src->line_for_chars(g->src, g->last_char, &line);
        unsigned w = 0, max = 1;
        line_no += g->src->line_no_offset + 1;
        while (line_no >= max) {
            if (max * 10 < max) break; /* overflow */
            w++, max *= 10;
        }
        max_width = mu_max(max_width, w);
    }
    R->line_no_width = max_width;
}

/* label cluster */

/* clang-format off */
static void muC_cleanup(mu_Report *R, mu_Cluster *c)
{ muA_delete(R, c->line_labels); }
/* clang-format on */

static void muC_collect_multi(mu_Report *R) {
    const mu_LabelInfo *multi_labels = R->cur_group->multi_labels;
    const mu_Line      *line = R->cur_line;

    unsigned i, size, draw_msg;
    for (i = 0, size = muA_size(multi_labels); i < size; i++) {
        const mu_LabelInfo *li = &multi_labels[i];
        mu_LineLabel       *ll;

        mu_Col col;
        size_t last;
        if (muM_contains(li->start_char, line))
            col = li->start_char - line->offset, draw_msg = 0;
        else if (muM_contains((last = muM_lastchar(li)), line))
            col = last - line->offset, draw_msg = 1;
        else continue;
        ll = muA_push(R, R->ll_cache);
        ll->info = li, ll->col = col, ll->draw_msg = draw_msg;
    }
}

static void muC_collect_inline(mu_Report *R) {
    const mu_LabelInfo *labels = R->cur_group->labels;
    const mu_Line      *line = R->cur_line;

    unsigned i, size;
    for (i = 0, size = muA_size(labels); i < size; i++) {
        const mu_LabelInfo *li = &labels[i];

        mu_LineLabel *ll;
        size_t        pos;
        if (!(li->start_char >= line->offset
              && muM_lastchar(li) < muM_lineend(line) + 1))
            continue;
        switch (R->config->label_attach) {
        case MU_ATTACH_START: pos = li->start_char; break;
        case MU_ATTACH_END:   pos = muM_lastchar(li); break;
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
    if (llen != rlen) return llen - rlen;
    return l->info->label - r->info->label;
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
        width += ch == '\t' ?
                     (R->config->tab_width - (width % R->config->tab_width)) :
                     muD_width(ch, R->config->ambiwidth);
    }
    *muA_push(R, R->width_cache) = width;
    while (muA_size(R->width_cache) < len + 1)
        *muA_push(R, R->width_cache) = width;
}

static mu_Cluster *muC_new_cluster(mu_Report *R) {
    mu_Cluster *c = muA_push(R, R->clusters);
    memset(c, 0, sizeof(mu_Cluster));
    c->min_col = UINT_MAX;
    c->end_col = (mu_Col)R->cur_line->len;
    return c;
}

static void muC_fill_cluster(mu_Report *R) {
    const mu_LineLabel *lls = R->ll_cache;
    const mu_Line      *line = R->cur_line;

    unsigned i, size, extra_arrow_len = R->config->compact ? 1 : 2;
    mu_Width min_start = INT_MAX, max_end = INT_MIN;
    mu_Width limited = R->config->limit_width;

    mu_Cluster *c;
    muA_reset(R, R->clusters);
    if (limited > 0) limited -= R->line_no_width + 4 + muM_marginwidth(R);
    c = muC_new_cluster(R);
    for (i = 0, size = muA_size(lls); i < size; i++) {
        const mu_LineLabel *ll = &lls[i];

        mu_Col   start_col = ll->col, end_col = ll->col + 1;
        mu_Width label = ll->info->label->width;
        if (!ll->info->multi) {
            start_col = muM_col(ll->info->start_char, ll, line);
            end_col = muM_col(ll->info->end_char, ll, line);
        }
        if (R->config->limit_width > 0) {
            mu_Width cur,
                start = R->width_cache[muM_col(ll->info->start_char, ll, line)];
            mu_Width end = R->width_cache[end_col];
            int is_empty = (!muA_size(c->line_labels) && !c->margin_label.info);
            min_start = mu_min(min_start, start);
            max_end = mu_max(max_end, end);
            cur = (max_end - min_start)
                + (ll->draw_msg && label ? extra_arrow_len + 1 + label : 0);
            if (cur > limited && !is_empty)
                min_start = INT_MAX, max_end = INT_MIN, c = muC_new_cluster(R);
        }
        if (ll->info->multi) {
            int is_margin = 0;
            if (!c->margin_label.info) c->margin_label = *ll, is_margin = 1;
            if ((R->config->limit_width <= 0 || !is_margin) && ll->draw_msg)
                end_col = line->len + line->newline;
        }
        if (c->margin_label.info != ll->info || (ll->draw_msg && label))
            *muA_push(R, c->line_labels) = *ll;
        c->arrow_len = mu_max(c->arrow_len, end_col + extra_arrow_len);
        c->min_col = mu_min(c->min_col, start_col);
        c->max_msg_width = mu_max(c->max_msg_width, label);
    }
}

static int muC_widthindex(mu_Report *R, mu_Width width, mu_Col l, mu_Col u) {
    mu_Width delta = R->width_cache[l];
    while (l < u) {
        int m = l + ((u - l) >> 1);
        if ((R->width_cache[m] - delta) < width) l = m + 1;
        else u = m;
    }
    return l - (R->width_cache[l] - delta > width);
}

static void muC_calc_colrange(mu_Report *R, mu_Cluster *c) {
    int len = muA_size(R->width_cache) - 1;
    int line_part = mu_min(c->arrow_len, len); /* arrow_len in line part */

    mu_Width essential, skip, balance = 0;
    mu_Width margin = muM_marginwidth(R);
    mu_Width fixed = R->line_no_width + 4 + margin; /* line_no+edge+margin */
    mu_Width limited = R->config->limit_width - fixed;
    mu_Width arrow =
        R->width_cache[line_part] + mu_max(0, (int)c->arrow_len - len);

    mu_Width edge = arrow + 1 + c->max_msg_width; /* +1 for space */
    mu_Width line_width = R->width_cache[len];
    if (edge <= limited && line_width <= limited) return;

    essential = (arrow - R->width_cache[c->min_col]);
    essential += 1 + c->max_msg_width;
    if (essential + R->ellipsis_width >= limited) {
        c->start_col = c->min_col;
        c->end_col = muC_widthindex(R, 1 + c->max_msg_width - R->ellipsis_width,
                                    line_part, len);
        return;
    }
    skip = edge - limited + R->ellipsis_width;
    if (skip <= 0) {
        c->start_col = 0;
        c->end_col = muC_widthindex(R, limited - arrow - R->ellipsis_width,
                                    line_part, len);
        return;
    }
    if (line_width > edge) {
        mu_Width avail = line_width - edge;
        mu_Width desired = (limited - essential) / 2;
        balance = desired + mu_max(0, desired - avail);
    }
    c->start_col = muC_widthindex(R, skip + balance, 1, line_part) - 1;
    c->end_col = muC_widthindex(
        R, 1 + c->max_msg_width + balance - R->ellipsis_width, line_part, len);
}

static const mu_LabelInfo *muC_update_highlight(size_t              pos,
                                                const mu_LabelInfo *l,
                                                const mu_LabelInfo *r) {
    int llen, rlen;
    if (pos < r->start_char || pos >= r->end_char) return l;
    if (l == NULL) return r;
    if (l->label->priority != r->label->priority)
        return l->label->priority < r->label->priority ? r : l;
    llen = l->end_char - l->start_char;
    rlen = r->end_char - r->start_char;
    return rlen < llen ? r : l;
}

static const mu_LabelInfo *muC_get_highlight(mu_Report *R, mu_Col col) {
    const mu_Group     *g = R->cur_group;
    const mu_Cluster   *c = R->cur_cluster;
    const mu_LabelInfo *r = NULL;

    size_t   pos = R->cur_line->offset + col;
    unsigned i, size;
    if (c->margin_label.info)
        r = muC_update_highlight(pos, r, c->margin_label.info);
    for (i = 0, size = muA_size(g->multi_labels); i < size; i++)
        r = muC_update_highlight(pos, r, &g->multi_labels[i]);
    for (i = 0, size = muA_size(c->line_labels); i < size; i++)
        r = muC_update_highlight(pos, r, c->line_labels[i].info);
    return r;
}

static const mu_LabelInfo *muC_get_vbar(mu_Report *R, int row, mu_Col col) {
    const mu_Cluster *c = R->cur_cluster;

    unsigned i, size;
    for (i = 0, size = muA_size(c->line_labels); i < size; i++) {
        const mu_LineLabel *ll = &c->line_labels[i];
        if (((ll->info->label->width || ll->info->multi)
             && c->margin_label.info != ll->info && ll->col == col && row <= i))
            return ll->info;
    }
    return NULL;
}

static const mu_LabelInfo *muC_get_underline(mu_Report *R, mu_Col col) {
    const mu_Cluster   *c = R->cur_cluster;
    const mu_LabelInfo *r = NULL;

    size_t   pos = R->cur_line->offset + col;
    unsigned i, size, rlen, lllen;
    int      rp, llp;
    for (i = 0, size = muA_size(c->line_labels); i < size; i++) {
        const mu_LineLabel *ll = &c->line_labels[i];
        if (!(!ll->info->multi
              && mu_asc(ll->info->start_char, pos, muM_lastchar(ll->info))))
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

#define MU_SRC_INITED (-1)
#define MU_SRC_UNUSED (-2)

/* clang-format off */
static void muG_cleanup(mu_Report *R, mu_Group *g)
{ muA_delete(R, g->multi_labels); muA_delete(R, g->labels); }
/* clang-format on */

typedef struct mu_LocCtx {
    mu_Report *R;
    char       buff[256];
} mu_LocCtx;

static mu_Slice muG_calc_location(mu_LocCtx *ctx, mu_Source *src, ssize_t pos) {
    const mu_Group *g = ctx->R->cur_group;
    unsigned        line_no = 0, col = 0;
    const mu_Line  *line;
    if (src == g->src && ctx->R->config->index_type == MU_INDEX_BYTE)
        pos = muM_bytes2chars(src, pos, &line);
    else {
        if (src != g->src)
            pos = muA_size(g->labels) ? (int)g->labels[0].start_char : 0;
        line_no = src->line_for_chars(src, pos, &line);
    }
    if (pos > muM_lineend(line)) return muD_literal("?:?");
    col = pos - line->offset + 1;
    line_no += src->line_no_offset + 1;
    return muD_snprintf(ctx->buff, sizeof(ctx->buff), "%u:%u", line_no, col);
}

static int muG_trim_name(mu_Report *R, mu_Slice *name, mu_Slice loc) {
    int ellipsis = 0;
    if (R->config->limit_width > 0) {
        mu_Width id_width = muD_strwidth(*name, R->config->ambiwidth);
        mu_Width fixed = (int)muD_bytelen(loc) + R->line_no_width + 9;
        mu_Width line_width = R->config->limit_width;
        if (id_width + fixed > line_width) {
            mu_Width ambi = R->config->ambiwidth;
            mu_Width avail = line_width - fixed - R->ellipsis_width;
            avail = mu_max(avail, MU_MIN_FILENAME_WIDTH);
            if (avail < id_width)
                ellipsis = muD_widthlimit(name, -avail, ambi) + 1;
        }
    }
    return ellipsis;
}

static mu_Group *muG_init(mu_Report *R, mu_Id src_id) {
    mu_Group *g = NULL;
    if (R->sources[src_id]->gidx < 0) {
        unsigned size = muA_size(R->groups);
        int      old_gidx = R->sources[src_id]->gidx;
        g = muA_push(R, R->groups);
        memset(g, 0, sizeof(mu_Group));
        g->src = R->sources[src_id];
        g->src->gidx = (assert(size < INT_MAX), (int)size);
        if (old_gidx != MU_SRC_INITED && g->src->init) g->src->init(g->src);
    }
    return g;
}

static void muG_init_info(mu_Report *R, mu_Label *label, mu_LabelInfo *out) {
    size_t         start_pos = label->start_pos, end_pos = label->end_pos;
    const mu_Line *start_line, *end_line;
    mu_Source     *src;
    src = R->sources[label->src_id];
    if (R->config->index_type == MU_INDEX_CHAR) {
        src->line_for_chars(src, start_pos, &start_line);
        out->start_char = start_pos;
        if (start_pos >= end_pos)
            end_line = start_line, out->end_char = start_pos;
        else {
            out->end_char = end_pos;
            src->line_for_chars(src, end_pos - 1, &end_line);
        }
    } else {
        out->start_char = muM_bytes2chars(src, start_pos, &start_line);
        if (start_pos >= end_pos)
            end_line = start_line, out->end_char = out->start_char;
        else out->end_char = muM_bytes2chars(src, end_pos, &end_line);
    }
    out->start_char =
        mu_min(out->start_char, muM_lineend(start_line) + start_line->newline);
    out->end_char =
        mu_min(out->end_char, muM_lineend(end_line) + end_line->newline);
    out->label = label;
    out->multi = (start_line != end_line);
}

static int muG_cmp_li(const void *lhf, const void *rhf) {
    const mu_LabelInfo *l = (const mu_LabelInfo *)lhf;
    const mu_LabelInfo *r = (const mu_LabelInfo *)rhf;

    int llen = l->end_char - l->start_char;
    int rlen = r->end_char - r->start_char;
    return rlen - llen;
}

static int muG_make_groups(mu_Report *R) {
    unsigned i, len;
    muA_reset(R, R->groups);
    for (i = 0, len = muA_size(R->sources); i < len; i++)
        if (R->sources[i]->gidx >= 0) R->sources[i]->gidx = MU_SRC_INITED;
    for (i = 0, len = muA_size(R->labels); i < len; i++) {
        mu_Label    *label = &R->labels[i];
        mu_LabelInfo li, **labels;
        mu_Group    *g;
        if (label->src_id >= muA_size(R->sources)) return MU_ERRSRC;
        g = muG_init(R, label->src_id);
        muG_init_info(R, label, &li);
        if (g) g->first_char = li.start_char, g->last_char = muM_lastchar(&li);
        else {
            g = &R->groups[R->sources[label->src_id]->gidx];
            g->first_char = mu_min(g->first_char, li.start_char);
            g->last_char = mu_max(g->last_char, muM_lastchar(&li));
        }
        labels = li.multi ? &g->multi_labels : &g->labels;
        *muA_push(R, *labels) = li;
    }
    for (i = 0, len = muA_size(R->groups); i < len; i++) {
        mu_LabelInfo *li = R->groups[i].multi_labels;
        qsort(li, muA_size(li), sizeof(mu_LabelInfo), muG_cmp_li);
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

static int muR_header(mu_Report *R) {
    switch (R->level) {
    case MU_ERROR:   muX(muW_color(R, MU_COLOR_ERROR)); break;
    case MU_WARNING: muX(muW_color(R, MU_COLOR_WARNING)); break;
    default:         muX(muW_color(R, MU_COLOR_KIND)); break;
    }
    if (R->code.p) {
        muX(muW_draw(R, MU_DRAW_LBOX, 1));
        muX(muW_write(R, R->code));
        muX(muW_draw(R, MU_DRAW_RBOX, 1));
        muX(muW_draw(R, MU_DRAW_SPACE, 1));
    }
    switch (R->level) {
    case MU_ERROR:   muX(muW_write(R, muD_literal("Error"))); break;
    case MU_WARNING: muX(muW_write(R, muD_literal("Warning"))); break;
    default:         muX(muW_write(R, R->custom_level)); break;
    }
    muX(muW_draw(R, MU_DRAW_COLON, 1));
    muX(muW_color(R, MU_COLOR_RESET));
    if (R->title.p) {
        muX(muW_draw(R, MU_DRAW_SPACE, 1));
        muX(muW_write(R, R->title));
    }
    return muW_draw(R, MU_DRAW_NEWLINE, 1);
}

static int muR_reference(mu_Report *R, unsigned i, ssize_t pos, mu_Id src_id) {
    mu_Source *src = R->sources[src_id];
    mu_LocCtx  ctx;
    mu_Slice   name = R->cur_group->src->name;
    mu_Slice   loc = (ctx.R = R, muG_calc_location(&ctx, src, pos));

    int ellipsis = muG_trim_name(R, &name, loc);
    muX(muW_draw(R, MU_DRAW_SPACE, R->line_no_width + 2));
    muX(muW_color(R, MU_COLOR_MARGIN));
    muX(muW_draw(R, i ? MU_DRAW_VBAR : MU_DRAW_LTOP, 1));
    muX(muW_draw(R, MU_DRAW_HBAR, 1));
    muX(muW_draw(R, MU_DRAW_LBOX, 1));
    muX(muW_color(R, MU_COLOR_RESET));
    muX(muW_draw(R, MU_DRAW_SPACE, 1));
    if (ellipsis) {
        muX(muW_draw(R, MU_DRAW_SPACE, ellipsis - 1));
        muX(muW_draw(R, MU_DRAW_ELLIPSIS, 1));
    }
    muX(muW_replace(R, name, '\t', ' '));
    muX(muW_draw(R, MU_DRAW_COLON, 1));
    muX(muW_write(R, loc));
    muX(muW_draw(R, MU_DRAW_SPACE, 1));
    muX(muW_color(R, MU_COLOR_MARGIN));
    muX(muW_draw(R, MU_DRAW_RBOX, 1));
    muX(muW_color(R, MU_COLOR_RESET));
    return muW_draw(R, MU_DRAW_NEWLINE, 1);
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
    char     buf[32];
    mu_Slice ln;
    if (line_no && !is_ellipsis) {
        line_no += R->cur_group->src->line_no_offset;
        ln = muD_snprintf(buf, sizeof(buf), "%u", line_no);
        muX(muW_draw(R, MU_DRAW_SPACE, R->line_no_width - muD_bytelen(ln) + 1));
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
    const mu_Group   *g = R->cur_group;
    const mu_Line    *line = R->cur_line;
    const mu_Cluster *c = R->cur_cluster;

    unsigned i, size = muA_size(g->multi_labels);
    size_t   first_char = line->offset + (c ? c->min_col : 0);
    size_t   last_char = line->offset + (c ? c->end_col : line->len);
    int      ptr_is_start = 0;

    const mu_LabelInfo *hbar = NULL, *ptr = NULL;
    if (size == 0) return MU_OK;
    for (i = 0; i < size; ++i) {
        const mu_LabelInfo *li = &g->multi_labels[i];
        const mu_LabelInfo *vbar = NULL, *corner = NULL;
        int is_start = mu_asc(first_char, li->start_char, last_char);
        if (muM_lastchar(li) >= first_char && li->start_char <= last_char) {
            int is_margin = c && c->margin_label.info == li;
            int is_end = mu_asc(first_char, muM_lastchar(li), last_char);
            if (is_margin && t == MU_MARGIN_LINE)
                ptr = li, ptr_is_start = is_start;
            else if (!is_start && (!is_end || t == MU_MARGIN_LINE)) vbar = li;
            else if (report && report->info == li) {
                if (t != MU_MARGIN_ARROW && !is_start) vbar = li;
                else if (is_margin) vbar = c->margin_label.info;
                if (t == MU_MARGIN_ARROW && (!is_margin || !is_start))
                    hbar = li, corner = li;
            } else if (report) {
                unsigned j, llen = muA_size(c->line_labels);
                int      info_is_below = 0;
                if (!is_margin) {
                    for (j = 0; j < llen; ++j) {
                        mu_LineLabel *ll = &c->line_labels[j];
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
            muX(muW_draw(R, MU_DRAW_HBAR, R->config->compact ? 1 : 2));
        } else if (vbar) {
            mu_Draw draw =
                t == MU_MARGIN_ELLIPSIS ? MU_DRAW_VBAR_GAP : MU_DRAW_VBAR;
            muX(muW_use_color(R, vbar->label, MU_COLOR_LABEL));
            muX(muW_draw(R, draw, 1));
            if (!R->config->compact) muX(muW_draw(R, MU_DRAW_SPACE, 1));
        } else if (ptr && t == MU_MARGIN_LINE) {
            mu_Draw draw = MU_DRAW_HBAR;
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
    /* don't reset here, to connect lines of arrows */
    return MU_OK;
}

static int muR_line(mu_Report *R, mu_Slice data) {
    const mu_Cluster   *c = R->cur_cluster;
    const mu_Width     *wc = R->width_cache;
    const mu_LabelInfo *color = NULL, *hl;

    const char *s;
    unsigned    i;
    for (i = 0; i < c->start_col; ++i) muD_advance(&data);
    for (s = data.p; i < c->end_col && data.p < data.e; ++i) {
        const char *p = data.p;
        hl = muC_get_highlight(R, i);
        muD_advance(&data);
        if (hl != color || *p == '\t') {
            if (s < p) {
                if (color) muX(muW_use_color(R, color->label, MU_COLOR_LABEL));
                else muX(muW_use_color(R, NULL, MU_COLOR_UNIMPORTANT));
                muX(muW_write(R, muD_slice(s, p - s)));
            }
            if (*p == '\t') muX(muW_draw(R, MU_DRAW_SPACE, wc[i + 1] - wc[i]));
            color = hl, s = p + (*p == '\t');
        }
    }
    if (s < data.p) {
        if (color) muX(muW_use_color(R, color->label, MU_COLOR_LABEL));
        else muX(muW_use_color(R, NULL, MU_COLOR_UNIMPORTANT));
        muX(muW_write(R, muD_slice(s, data.p - s)));
    }
    return muW_use_color(R, NULL, MU_COLOR_RESET);
}

static int muR_underline(mu_Report *R, int row, int draw_underline) {
    const mu_Width     *wc = R->width_cache;
    const mu_Cluster   *c = R->cur_cluster;
    const mu_LineLabel *ll = &c->line_labels[row];

    int    has_ul = (draw_underline && R->config->underlines);
    mu_Col col, col_max = R->cur_line->len;
    muX(muR_lineno(R, 0, 0));
    muX(muR_margin(R, ll, MU_MARGIN_NONE));
    if (c->start_col > 0) muX(muW_draw(R, MU_DRAW_SPACE, R->ellipsis_width));
    for (col = c->start_col; col < c->arrow_len; ++col) {
        const mu_LabelInfo *vbar = muC_get_vbar(R, row, col);
        const mu_LabelInfo *underline =
            has_ul ? muC_get_underline(R, col) : NULL;

        int w = (col < col_max ? (wc[col + 1] - wc[col]) : 1);
        if (vbar && underline) {
            muX(muW_use_color(R, vbar->label, MU_COLOR_LABEL));
            muX(muW_draw(R, MU_DRAW_UNDERBAR, 1));
            muX(muW_draw(R, MU_DRAW_UNDERLINE, w - 1));
        } else if (vbar) {
            int uarrow =
                (vbar->multi && draw_underline && R->config->multiline_arrows);
            muX(muW_use_color(R, vbar->label, MU_COLOR_LABEL));
            muX(muW_draw(R, uarrow ? MU_DRAW_UARROW : MU_DRAW_VBAR, 1));
            muX(muW_draw(R, MU_DRAW_SPACE, w - 1));
        } else if (underline) {
            muX(muW_use_color(R, underline->label, MU_COLOR_LABEL));
            muX(muW_draw(R, MU_DRAW_UNDERLINE, w));
        } else {
            muX(muW_use_color(R, NULL, MU_COLOR_RESET));
            muX(muW_draw(R, MU_DRAW_SPACE, w));
        }
    }
    muX(muW_use_color(R, NULL, MU_COLOR_RESET));
    return muW_draw(R, MU_DRAW_NEWLINE, 1);
}

static int muR_arrow(mu_Report *R, int row, int draw_underline) {
    const mu_Width     *wc = R->width_cache;
    const mu_Cluster   *c = R->cur_cluster;
    const mu_LineLabel *ll = &c->line_labels[row];

    mu_Col col, col_max = R->cur_line->len;
    muX(muR_lineno(R, 0, 0));
    muX(muR_margin(R, ll, MU_MARGIN_ARROW));
    if (c->start_col > 0) {
        int e = (ll->info == c->margin_label.info || !ll->draw_msg);
        muX(muW_color(R, e ? MU_COLOR_UNIMPORTANT : MU_COLOR_RESET));
        muX(muW_draw(R, e ? MU_DRAW_HBAR : MU_DRAW_SPACE, R->ellipsis_width));
    }
    for (col = c->start_col; col < c->arrow_len; ++col) {
        int w = (col < col_max ? (wc[col + 1] - wc[col]) : 1);
        int lw = ll->info->label->width;
        int is_hbar = (col > ll->col) != ll->info->multi
                   || (ll->draw_msg && lw && col > ll->col);
        const mu_LabelInfo *vbar = muC_get_vbar(R, row, col);
        if (col == ll->col && c->margin_label.info != ll->info) {
            mu_Draw draw = MU_DRAW_RBOT;
            if (!ll->info->multi) draw = MU_DRAW_LBOT;
            else if (ll->draw_msg) draw = (lw ? MU_DRAW_MBOT : MU_DRAW_RBOT);
            muX(muW_use_color(R, ll->info->label, MU_COLOR_LABEL));
            muX(muW_draw(R, draw, 1));
            muX(muW_draw(R, MU_DRAW_HBAR, w - 1));
        } else if (vbar && col != ll->col) {
            mu_Draw draw = MU_DRAW_VBAR, pad = MU_DRAW_SPACE;
            if (is_hbar) {
                draw = MU_DRAW_XBAR;
                if (R->config->cross_gap) draw = pad = MU_DRAW_HBAR;
            } else if (vbar->multi && draw_underline) draw = MU_DRAW_UARROW;
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
    muX(muW_use_color(R, NULL, MU_COLOR_RESET));
    if (ll->draw_msg) {
        muX(muW_draw(R, MU_DRAW_SPACE, 1));
        muX(muW_write(R, ll->info->label->message));
    }
    return muW_draw(R, MU_DRAW_NEWLINE, 1);
}

static int muR_cluster(mu_Report *R, unsigned line_no, mu_Slice data) {
    const mu_Cluster *c = R->cur_cluster;

    unsigned row, row_len = muA_size(c->line_labels);
    int      draw_underline = 1;
    muX(muR_lineno(R, line_no + 1, 0));
    muX(muR_margin(R, NULL, MU_MARGIN_LINE));
    if (c->start_col > 0) {
        muX(muW_color(R, MU_COLOR_UNIMPORTANT));
        muX(muW_draw(R, MU_DRAW_ELLIPSIS, 1));
        muX(muW_color(R, MU_COLOR_RESET));
    }
    muX(muR_line(R, data));
    if (c->end_col < R->cur_line->len) {
        muX(muW_color(R, MU_COLOR_UNIMPORTANT));
        muX(muW_draw(R, MU_DRAW_ELLIPSIS, 1));
        muX(muW_color(R, MU_COLOR_RESET));
    }
    muX(muW_draw(R, MU_DRAW_NEWLINE, 1));
    for (row = 0; row < row_len; ++row) {
        const mu_LineLabel *ll = &c->line_labels[row];

        int draw_arrow =
            (ll->info->label->width
             || (ll->info->multi && c->margin_label.info != ll->info));
        if ((draw_underline || draw_arrow) && !R->config->compact) {
            muX(muR_underline(R, row, draw_underline));
            draw_underline = 0;
        }
        if (draw_arrow) muX(muR_arrow(R, row, draw_underline));
    }
    return MU_OK;
}

static int muR_lines(mu_Report *R) {
    const mu_Group *g = R->cur_group;
    unsigned line_start = g->src->line_for_chars(g->src, g->first_char, NULL);
    unsigned line_end = g->src->line_for_chars(g->src, g->last_char, NULL);
    unsigned line_no;

    int is_ellipsis = 0;
    for (line_no = line_start; line_no <= line_end; ++line_no) {
        const mu_Line *line = g->src->get_line_info(g->src, line_no);
        R->cur_line = line;
        if (muC_fill_llcache(R)) {
            unsigned i, size;
            mu_Slice data = g->src->get_line(g->src, line_no);
            muC_fill_widthcache(R, line->len, data);
            muC_fill_cluster(R);
            for (i = 0, size = muA_size(R->clusters); i < size; i++) {
                mu_Cluster *c = &R->clusters[i];
                R->cur_cluster = c;
                if (R->config->limit_width > 0) muC_calc_colrange(R, c);
                muX(muR_cluster(R, line_no, data));
            }
        } else if (!is_ellipsis && muM_line_in_label(line, g->multi_labels)) {
            muX(muR_lineno(R, 0, 1));
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

static int muR_help_or_note(mu_Report *R, int is_help, const mu_Slice *msgs) {
    const mu_Slice st = is_help ? muD_literal("Help") : muD_literal("Note");

    char     buf[32];
    unsigned i, size;
    for (i = 0, size = muA_size(msgs); i < size; ++i) {
        mu_Slice t = st, msg;
        if (size > 1) t = muD_snprintf(buf, sizeof(buf), "%s %u", st.p, i + 1);
        if (!R->config->compact) {
            muX(muR_lineno(R, 0, 0));
            muX(muW_draw(R, MU_DRAW_NEWLINE, 1));
        }
        for (msg = msgs[i];; msg.p = msg.e + 1) {
            if (!(msg.e = strchr(msg.p, '\n'))) msg.e = msgs[i].e;
            muX(muR_lineno(R, 0, 0));
            muX(muW_color(R, MU_COLOR_NOTE));
            if (msg.p > msgs[i].p)
                muX(muW_draw(R, MU_DRAW_SPACE, muD_bytelen(t) + 2));
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

static int muR_report(mu_Report *R, ssize_t pos, mu_Id src_id) {
    unsigned i, size;
    muX(muG_make_groups(R));
    muM_calc_linenowidth(R);
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

/* source */

MU_API void mu_updatelines(mu_Source *src, mu_Slice data) {
    mu_BareSource *bsrc = (mu_BareSource *)src;

    mu_Report *R = bsrc->R;
    mu_Line   *next, *current = muA_last(bsrc->lines);
    if (current == NULL) {
        current = muA_push(R, bsrc->lines);
        memset(current, 0, sizeof(mu_Line));
    }
    while (data.p < data.e) {
        const char *start = data.p;

        int is_newline = (*data.p == '\n');
        if (is_newline) {
            size_t offset = muM_lineend(current) + 1;
            size_t byte_offset = current->byte_offset + current->byte_len + 1;
            current->newline = 1;
            next = muA_push(R, bsrc->lines);
            memset(next, 0, sizeof(mu_Line));
            next->offset = offset, next->byte_offset = byte_offset;
            current = next;
        }
        muD_advance(&data);
        if (!is_newline)
            current->len += 1, current->byte_len += (size_t)(data.p - start);
    }
}

MU_API mu_Source *mu_newsource(mu_Report *R, size_t size, const char *name) {
    mu_BareSource *bsrc = (mu_BareSource *)R->allocf(R->ud, NULL, size, 0);
    if (!bsrc) return NULL;
    memset(bsrc, 0, size);
    bsrc->R = R;
    bsrc->size = size;
    name = name ? name : "<unknown>";
    bsrc->src.name = muD_slice(name, strlen(name));
    bsrc->src.free = (void (*)(mu_Source *))mu_freesource;
    bsrc->src.get_line_info = mu_getline;
    bsrc->src.line_for_chars = mu_lineforchars;
    bsrc->src.line_for_bytes = mu_lineforbytes;
    return (mu_Source *)bsrc;
}

MU_API void mu_freesource(mu_Source *src) {
    mu_BareSource *bsrc = (mu_BareSource *)src;

    mu_Report *R = bsrc->R;
    muA_delete(R, bsrc->lines);
    R->allocf(R->ud, bsrc, 0, bsrc->size);
}

MU_API const mu_Line *mu_getline(mu_Source *src, unsigned line_no) {
    mu_BareSource *bsrc = (mu_BareSource *)src;

    size_t size = muA_size(bsrc->lines);
    return &bsrc->lines[line_no < size ? line_no : size - 1];
}

MU_API unsigned mu_lineforchars(mu_Source *src, size_t char_pos,
                                const mu_Line **out) {
    mu_BareSource *bsrc = (mu_BareSource *)src;

    unsigned l = 0, u = muA_size(bsrc->lines);
    while (l < u) {
        unsigned m = l + ((u - l) >> 1);
        if (bsrc->lines[m].offset <= char_pos) l = m + 1;
        else u = m;
    }
    if (out) *out = mu_getline(src, l - 1);
    return l - 1;
}

MU_API unsigned mu_lineforbytes(mu_Source *src, size_t byte_pos,
                                const mu_Line **out) {
    mu_BareSource *bsrc = (mu_BareSource *)src;

    unsigned l = 0, u = muA_size(bsrc->lines);
    while (l < u) {
        unsigned m = l + ((u - l) >> 1);
        if (bsrc->lines[m].byte_offset < byte_pos) l = m + 1;
        else u = m;
    }
    if (out) *out = mu_getline(src, l - 1);
    return l - 1;
}

typedef struct mu_MemorySource {
    mu_BareSource base;
    mu_Slice      data;
} mu_MemorySource;

static int muS_memory_init(mu_Source *src) {
    mu_MemorySource *msrc = (mu_MemorySource *)src;
    mu_updatelines(src, msrc->data);
    return MU_OK;
}

static mu_Slice muS_memory_get_line(mu_Source *src, unsigned line_no) {
    mu_MemorySource *msrc = (mu_MemorySource *)src;

    const mu_Line *line = mu_getline(src, line_no);
    return muD_slice(msrc->data.p + line->byte_offset, line->byte_len);
}

MU_API mu_Source *mu_memory_source(mu_Report *R, const char *data, size_t len,
                                   const char *name) {
    mu_MemorySource *msrc =
        (mu_MemorySource *)mu_newsource(R, sizeof(mu_MemorySource), name);
    if (!msrc) return NULL;
    msrc->data = muD_slice(data, len);
    msrc->base.src.init = muS_memory_init;
    msrc->base.src.get_line = muS_memory_get_line;
    return &msrc->base.src;
}

#if !MU_NO_STDIO

typedef struct mu_FileSource {
    mu_BareSource base;

    FILE *fp;
    char  own_fp;
    char *buff;
} mu_FileSource;

static int muS_file_init(mu_Source *src) {
    mu_FileSource *fsrc = (mu_FileSource *)src;

    char   buff[BUFSIZ];
    size_t trim = 0;
    if (fsrc->fp == NULL) {
        fsrc->fp = fopen(src->name.p, "r");
        if (fsrc->fp == NULL) return MU_ERRFILE;
        fsrc->own_fp = 1;
    }
    while (!feof(fsrc->fp)) {
        size_t   n = fread(buff + trim, 1, sizeof(buff) - trim, fsrc->fp);
        mu_Slice data = muD_slice(buff, n += trim);
        data.e -= (trim = muD_checkend(data));
        mu_updatelines(src, data);
        if (ferror(fsrc->fp)) {
            if (fsrc->own_fp) fclose(fsrc->fp);
            fsrc->fp = NULL;
            return MU_ERRFILE;
        }
        memmove(buff, buff + n - trim, trim);
    }
    if (trim) mu_updatelines(src, muD_slice(buff, trim));
    return MU_OK;
}

static void muS_file_free(mu_Source *src) {
    mu_FileSource *fsrc = (mu_FileSource *)src;
    if (fsrc->own_fp && fsrc->fp) fclose(fsrc->fp);
    mu_freesource(src);
}

static mu_Slice muS_file_get_line(mu_Source *src, unsigned line_no) {
    mu_FileSource *fsrc = (mu_FileSource *)src;

    mu_Report     *R = fsrc->base.R;
    const mu_Line *line = mu_getline(src, line_no);

    char  *p = muA_reserve(R, fsrc->buff, line->byte_len);
    int    seek;
    size_t n;
#if defined(__APPLE__) || defined(_POSIX_C_SOURCE) && _POSIX_C_SOURCE >= 200112L
    seek = fseeko(fsrc->fp, line->byte_offset, SEEK_SET);
#elif defined(_WIN32)
    seek = _fseeki64(fsrc->fp, line->byte_offset, SEEK_SET);
#else
    if (line->byte_offset > LONG_MAX) return muD_slice(p, 0);
    seek = fseek(fsrc->fp, (long)line->byte_offset, SEEK_SET);
#endif
    n = (seek == 0 ? fread(p, 1, line->byte_len, fsrc->fp) : 0);
    return muD_slice(p, n);
}

MU_API mu_Source *mu_file_source(mu_Report *R, FILE *fp, const char *name) {
    mu_FileSource *fsrc;

    int own_fp = 0;
    if (fp == NULL) {
        fp = fopen(name, "r");
        if (fp == NULL) return NULL;
        own_fp = 1;
    }
    fsrc = (mu_FileSource *)mu_newsource(R, sizeof(mu_FileSource), name);
    if (!fsrc) return (void)(own_fp && fclose(fp)), (mu_Source *)NULL;
    fsrc->fp = fp;
    fsrc->own_fp = own_fp;
    fsrc->base.src.free = muS_file_free;
    fsrc->base.src.get_line = muS_file_get_line;
    return &fsrc->base.src;
}

#endif /* !MU_NO_STDIO */

/* config */

static mu_Chunk muM_ansi_charset[MU_DRAW_COUNT] = {
    /* MU_DRAW_SPACE      */ "\x01 ",
    /* MU_DRAW_NEWLINE    */ "\x01\n",
    /* MU_DRAW_LBOX       */ "\x01[",
    /* MU_DRAW_RBOX       */ "\x01]",
    /* MU_DRAW_COLON      */ "\x01:",
    /* MU_DRAW_HBAR       */ "\x01-",
    /* MU_DRAW_VBAR       */ "\x01|",
    /* MU_DRAW_XBAR       */ "\x01+",
    /* MU_DRAW_VBAR_BREAK */ "\x01*",
    /* MU_DRAW_VBAR_GAP   */ "\x01:",
    /* MU_DRAW_UARROW     */ "\x01^",
    /* MU_DRAW_RARROW     */ "\x01>",
    /* MU_DRAW_LTOP       */ "\x01,",
    /* MU_DRAW_MTOP       */ "\x01v",
    /* MU_DRAW_RTOP       */ "\x01.",
    /* MU_DRAW_LBOT       */ "\x01`",
    /* MU_DRAW_MBOT       */ "\x01^",
    /* MU_DRAW_RBOT       */ "\x01'",
    /* MU_DRAW_LCROSS     */ "\x01|",
    /* MU_DRAW_RCROSS     */ "\x01|",
    /* MU_DRAW_UNDERBAR   */ "\x01|",
    /* MU_DRAW_UNDERLINE  */ "\x01^",
    /* MU_DRAW_ELLIPSIS   */ "\x03...",
};

static mu_Chunk muM_unicode_charset[MU_DRAW_COUNT] = {
    /* MU_DRAW_SPACE      */ "\x01 ",
    /* MU_DRAW_NEWLINE    */ "\x01\n",
    /* MU_DRAW_LBOX       */ "\x01[",
    /* MU_DRAW_RBOX       */ "\x01]",
    /* MU_DRAW_COLON      */ "\x01:",
    /* MU_DRAW_HBAR       */ "\x03─",
    /* MU_DRAW_VBAR       */ "\x03│",
    /* MU_DRAW_XBAR       */ "\x03┼",
    /* MU_DRAW_VBAR_BREAK */ "\x03┆",
    /* MU_DRAW_VBAR_GAP   */ "\x03┊",
    /* MU_DRAW_UARROW     */ "\x03▲",
    /* MU_DRAW_RARROW     */ "\x03▶",
    /* MU_DRAW_LTOP       */ "\x03╭",
    /* MU_DRAW_MTOP       */ "\x03┬",
    /* MU_DRAW_RTOP       */ "\x03╮",
    /* MU_DRAW_LBOT       */ "\x03╰",
    /* MU_DRAW_MBOT       */ "\x03┴",
    /* MU_DRAW_RBOT       */ "\x03╯",
    /* MU_DRAW_LCROSS     */ "\x03├",
    /* MU_DRAW_RCROSS     */ "\x03┤",
    /* MU_DRAW_UNDERBAR   */ "\x03┬",
    /* MU_DRAW_UNDERLINE  */ "\x03─",
    /* MU_DRAW_ELLIPSIS   */ "\x03…",
};

MU_API const mu_Charset *mu_ansi(void) { return &muM_ansi_charset; }
MU_API const mu_Charset *mu_unicode(void) { return &muM_unicode_charset; }

MU_API mu_Chunk mu_default_color(void *ud, mu_ColorKind kind) {
    switch (kind) {
    case MU_COLOR_RESET:          return "\x04\x1b[0m";
    case MU_COLOR_ERROR:          return "\x05\x1b[31m";
    case MU_COLOR_WARNING:        return "\x05\x1b[33m";
    case MU_COLOR_KIND:           return "\x0b\x1b[38;5;147m";
    case MU_COLOR_MARGIN:         return "\x0b\x1b[38;5;246m";
    case MU_COLOR_SKIPPED_MARGIN: return "\x0b\x1b[38;5;240m";
    case MU_COLOR_UNIMPORTANT:    return "\x0b\x1b[38;5;249m";
    case MU_COLOR_NOTE:           return "\x0b\x1b[38;5;115m";
    case MU_COLOR_LABEL:          /* FALLTHROUGH */
    default:                      return "\x05\x1b[39m";
    }
}

static mu_Config muM_default = {
    /* .cross_gap        = */ 1,
    /* .compact          = */ 0,
    /* .underlines       = */ 1,
    /* .multiline_arrows = */ 1,
    /* .tab_width        = */ 4,
    /* .limit_width      = */ 0,
    /* .ambiwidth        = */ 1,
    /* .label_attach     = */ MU_ATTACH_MIDDLE,
    /* .index_type       = */ MU_INDEX_CHAR,
    /* .color            = */ mu_default_color,
    /* .color_ud         = */ NULL,
    /* .char_set         = */ &muM_unicode_charset,
};

/* clang-format off */
MU_API void mu_initconfig(mu_Config *config)
{ memcpy(config, &muM_default, sizeof(mu_Config)); }
/* clang-format on */

/* API */

static void muR_cleanup(mu_Report *R) {
    unsigned i, size;
    if (!R) return;
    R->cur_color_label = NULL;
    R->cur_color_kind = MU_COLOR_RESET;
    for (i = 0, size = muA_size(R->groups); i < size; i++)
        muG_cleanup(R, &R->groups[i]);
    muA_reset(R, R->groups);
    for (i = 0, size = muA_size(R->clusters); i < size; i++)
        muC_cleanup(R, &R->clusters[i]);
    muA_reset(R, R->clusters);
    muA_reset(R, R->ll_cache);
    muA_reset(R, R->width_cache);
}

MU_API int mu_source(mu_Report *R, mu_Source *src) {
    if (!R || !src) return MU_ERRPARAM;
    *muA_push(R, R->sources) = src;
    src->id = (mu_Id)(muA_size(R->sources) - 1);
    src->gidx = MU_SRC_UNUSED;
    return MU_OK;
}

MU_API int mu_writer(mu_Report *R, mu_Writer *writer, void *ud) {
    if (!R) return MU_ERRPARAM;
    return R->writer = writer, R->writer_ud = ud, MU_OK;
}

MU_API int mu_render(mu_Report *R, ssize_t pos, mu_Id src_id) {
    mu_Chunk ellipsis;
    if (!R || src_id >= muA_size(R->sources)) return MU_ERRPARAM;
    if (R->writer == NULL) return MU_OK;
    muR_cleanup(R);
    ellipsis = (*R->config->char_set)[MU_DRAW_ELLIPSIS];
    R->ellipsis_width =
        muD_strwidth(muD_slice(ellipsis + 1, *ellipsis), R->config->ambiwidth);
    return muR_report(R, pos, src_id);
}

static void *muM_allocf(void *ud, void *p, size_t nsize, size_t osize) {
    if (p && nsize == 0) return free(p), (void *)NULL;
    return realloc(p, nsize);
}

MU_API mu_Report *mu_new(mu_Allocf *allocf, void *ud) {
    mu_Report *R;
    if (allocf == NULL) allocf = muM_allocf;
    R = (mu_Report *)allocf(ud, NULL, sizeof(mu_Report), 0);
    if (!R) return NULL;
    memset(R, 0, sizeof(mu_Report));
    R->allocf = allocf;
    R->ud = ud;
    R->config = &muM_default;
    return R;
}

MU_API void mu_reset(mu_Report *R) {
    unsigned i, size;
    if (!R) return;
    muR_cleanup(R);
    for (i = 0, size = muA_size(R->sources); i < size; i++)
        if (R->sources[i]->free) R->sources[i]->free(R->sources[i]);
    muA_reset(R, R->sources);
    muA_reset(R, R->labels);
    muA_reset(R, R->helps);
    muA_reset(R, R->notes);
}

MU_API void mu_delete(mu_Report *R) {
    if (!R) return;
    mu_reset(R);
    muA_delete(R, R->groups);
    muA_delete(R, R->clusters);
    muA_delete(R, R->ll_cache);
    muA_delete(R, R->width_cache);
    muA_delete(R, R->sources);
    muA_delete(R, R->labels);
    muA_delete(R, R->helps);
    muA_delete(R, R->notes);
    R->allocf(R->ud, R, 0, sizeof(mu_Report));
}

MU_API int mu_config(mu_Report *R, const mu_Config *config) {
    if (!R || !config || muA_size(R->labels) > 0) return MU_ERRPARAM;
    R->config = config;
    return MU_OK;
}

MU_API int mu_title(mu_Report *R, mu_Level l, const char *cl, const char *msg) {
    if (!R) return MU_ERRPARAM;
    R->level = l;
    R->custom_level = muD_slice(cl, cl ? strlen(cl) : 0);
    R->title = muD_slice(msg, msg ? strlen(msg) : 0);
    return MU_OK;
}

MU_API int mu_code(mu_Report *R, const char *code) {
    if (!R) return MU_ERRPARAM;
    return R->code = muD_slice(code, code ? strlen(code) : 0), MU_OK;
}

MU_API int mu_label(mu_Report *R, size_t start, size_t end, mu_Id src_id) {
    mu_Label *label;
    if (!R) return MU_ERRPARAM;
    label = muA_push(R, R->labels);
    memset(label, 0, sizeof(mu_Label));
    label->start_pos = start;
    label->end_pos = end;
    label->src_id = src_id;
    return MU_OK;
}

static mu_Label *muM_checklabel(mu_Report *R) {
    size_t size;
    if (!R || (size = muA_size(R->labels)) == 0) return NULL;
    return &R->labels[size - 1];
}

MU_API int mu_message(mu_Report *R, const char *msg, int width) {
    mu_Label *label = muM_checklabel(R);
    if (!label || !msg) return MU_ERRPARAM;
    label->message = muD_slice(msg, msg ? strlen(msg) : 0);
    if (width > 0) label->width = width;
    else label->width = muD_strwidth(label->message, R->config->ambiwidth);
    return MU_OK;
}

MU_API int mu_color(mu_Report *R, mu_Color *color, void *ud) {
    mu_Label *label = muM_checklabel(R);
    if (!label) return MU_ERRPARAM;
    return label->color = color, label->ud = ud, MU_OK;
}

MU_API int mu_order(mu_Report *R, int order) {
    mu_Label *label = muM_checklabel(R);
    if (!label) return MU_ERRPARAM;
    return label->order = order, MU_OK;
}

MU_API int mu_priority(mu_Report *R, int priority) {
    mu_Label *label = muM_checklabel(R);
    if (!label) return MU_ERRPARAM;
    return label->priority = priority, MU_OK;
}

MU_API int mu_help(mu_Report *R, const char *help_msg) {
    mu_Slice *msg;
    if (!R || !help_msg) return MU_ERRPARAM;
    msg = muA_push(R, R->helps);
    return *msg = muD_slice(help_msg, (help_msg ? strlen(help_msg) : 0)), MU_OK;
}

MU_API int mu_note(mu_Report *R, const char *note_msg) {
    mu_Slice *msg;
    if (!R || !note_msg) return MU_ERRPARAM;
    msg = muA_push(R, R->notes);
    return *msg = muD_slice(note_msg, (note_msg ? strlen(note_msg) : 0)), MU_OK;
}

MU_NS_END

#endif /* MU_IMPLEMENTATION */
