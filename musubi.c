#ifdef _MSC_VER
#define _CRT_SECURE_NO_DEPRECATE 1
#define _CRT_SECURE_NO_WARNINGS  1
#endif

#define LUA_LIB
#include <lauxlib.h>
#include <lua.h>

#define MU_STATIC_API
#include "musubi.h"

#ifdef _MSC_VER
#pragma execution_character_set("utf-8")
#define strcasecmp _stricmp
#endif

#define LMU_REPORT_TYPE    "musubi.Report"
#define LMU_CONFIG_TYPE    "musubi.Config"
#define LMU_COLORGEN_TYPE  "musubi.ColorGenerator"
#define LMU_COLORCODE_TYPE "musubi.ColorCode"

/* color generator */

static int Lmu_colorgen_new(lua_State *L) {
    float        min_brightness = (float)luaL_optnumber(L, 1, 0.5);
    mu_ColorGen *cg = (mu_ColorGen *)lua_newuserdata(L, sizeof(mu_ColorGen));
    mu_initcolorgen(cg, min_brightness);
    luaL_setmetatable(L, LMU_COLORGEN_TYPE);
    return 1;
}

static int Lmu_colorgen_libcall(lua_State *L) {
    lua_remove(L, 1);
    return Lmu_colorgen_new(L);
}

static int Lmu_colorgen_next(lua_State *L) {
    mu_ColorGen  *cg = (mu_ColorGen *)luaL_checkudata(L, 1, LMU_COLORGEN_TYPE);
    mu_ColorCode *code =
        (mu_ColorCode *)lua_newuserdata(L, sizeof(mu_ColorCode));
    mu_gencolor(cg, code);
    luaL_setmetatable(L, LMU_COLORCODE_TYPE);
    return 1;
}

static void lmu_opencolorgen(lua_State *L) {
    luaL_Reg libs[] = {
        {"new", Lmu_colorgen_new},
        {"next", Lmu_colorgen_next},
        {NULL, NULL},
    };
    luaL_newmetatable(L, LMU_COLORCODE_TYPE);
    lua_pop(L, 1);
    if (luaL_newmetatable(L, LMU_COLORGEN_TYPE)) {
        luaL_setfuncs(L, libs, 0);
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        lua_createtable(L, 0, 1);
        lua_pushcfunction(L, Lmu_colorgen_libcall);
        lua_setfield(L, -2, "__call");
        lua_setmetatable(L, -2);
    }
}

/* config */

static mu_Config *lmu_checkconfig(lua_State *L, int idx) {
    return (mu_Config *)luaL_checkudata(L, idx, LMU_CONFIG_TYPE);
}

static int Lmu_config_new(lua_State *L) {
    int ty = lua_type(L, 1);

    mu_Config *config = (mu_Config *)lua_newuserdata(L, sizeof(mu_Config));
    mu_initconfig(config);
    luaL_getmetatable(L, LMU_CONFIG_TYPE);
    lua_pushvalue(L, -1);
    lua_setmetatable(L, -3);
    if (ty == LUA_TTABLE) {
        lua_pushnil(L);
        while (lua_next(L, 1)) { /* o mt k v */
            lua_pushvalue(L, -4);
            lua_pushvalue(L, -3);
            if (lua_gettable(L, -5) == LUA_TNIL)
                luaL_error(L, "invalid config field '%s'", lua_tostring(L, -4));
            lua_insert(L, -2); /* o mt k v f o */
            lua_pushvalue(L, -3);
            lua_call(L, 2, 0); /* o mt k v */
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
    return 1;
}

static int Lmu_config_libcall(lua_State *L) {
    lua_remove(L, 1);
    return Lmu_config_new(L);
}

static int Lmu_config_cross_gap(lua_State *L) {
    mu_Config *config = lmu_checkconfig(L, 1);
    config->cross_gap = lua_toboolean(L, 2);
    return lua_settop(L, 1), 1;
}

static int Lmu_config_compact(lua_State *L) {
    mu_Config *config = lmu_checkconfig(L, 1);
    config->compact = lua_toboolean(L, 2);
    return lua_settop(L, 1), 1;
}

static int Lmu_config_underlines(lua_State *L) {
    mu_Config *config = lmu_checkconfig(L, 1);
    config->underlines = lua_toboolean(L, 2);
    return lua_settop(L, 1), 1;
}

static int Lmu_config_multiline_arrows(lua_State *L) {
    mu_Config *config = lmu_checkconfig(L, 1);
    config->multiline_arrows = lua_toboolean(L, 2);
    return lua_settop(L, 1), 1;
}

static int Lmu_config_tab_width(lua_State *L) {
    mu_Config *config = lmu_checkconfig(L, 1);
    config->tab_width = (int)luaL_checkinteger(L, 2);
    return lua_settop(L, 1), 1;
}

static int Lmu_config_limit_width(lua_State *L) {
    mu_Config *config = lmu_checkconfig(L, 1);
    config->limit_width = (int)luaL_optinteger(L, 2, 0);
    return lua_settop(L, 1), 1;
}

static int Lmu_config_ambiwidth(lua_State *L) {
    mu_Config *config = lmu_checkconfig(L, 1);
    config->ambiwidth = (int)luaL_checkinteger(L, 2);
    return lua_settop(L, 1), 1;
}

static int Lmu_config_label_attach(lua_State *L) {
    const char *opts[] = {"middle", "start", "end", NULL};
    mu_Config  *config = lmu_checkconfig(L, 1);
    config->label_attach = luaL_checkoption(L, 2, "middle", opts);
    return lua_settop(L, 1), 1;
}

static int Lmu_config_index_type(lua_State *L) {
    const char *opts[] = {"byte", "char", NULL};
    mu_Config  *config = lmu_checkconfig(L, 1);
    config->index_type = luaL_checkoption(L, 2, "char", opts);
    return lua_settop(L, 1), 1;
}

static int Lmu_config_color(lua_State *L) {
    mu_Config *config = lmu_checkconfig(L, 1);
    if (lua_toboolean(L, 2)) config->color = mu_default_color;
    else config->color = NULL;
    return lua_settop(L, 1), 1;
}

static int Lmu_config_char_set(lua_State *L) {
    mu_Config  *config = lmu_checkconfig(L, 1);
    const char *opts[] = {"ascii", "unicode", NULL};
    int         opt = luaL_checkoption(L, 2, "unicode", opts);
    if (opt == 0) config->char_set = mu_ascii();
    else config->char_set = mu_unicode();
    return lua_settop(L, 1), 1;
}

static void lmu_openconfig(lua_State *L) {
    luaL_Reg libs[] = {
        {"__index", NULL},
#define ENTRY(name) {#name, Lmu_config_##name}
        ENTRY(new),
        ENTRY(cross_gap),
        ENTRY(compact),
        ENTRY(underlines),
        ENTRY(multiline_arrows),
        ENTRY(tab_width),
        ENTRY(limit_width),
        ENTRY(ambiwidth),
        ENTRY(label_attach),
        ENTRY(index_type),
        ENTRY(color),
        ENTRY(char_set),
#undef ENTRY
        {NULL, NULL},
    };
    if (luaL_newmetatable(L, LMU_CONFIG_TYPE)) {
        luaL_setfuncs(L, libs, 0);
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        lua_createtable(L, 0, 1);
        lua_pushcfunction(L, Lmu_config_libcall);
        lua_setfield(L, -2, "__call");
        lua_setmetatable(L, -2);
    }
}

/* report */

typedef struct lmu_Report {
    mu_Report *R;
    lua_State *L;

    size_t pos;
    mu_Id  src_id;
    int    config_ref;
    int    custom_level_ref;
    int    msg_ref;
    int    code_ref;
    int    color_ref;

    mu_ColorCode chunk_buf;
} lmu_Report;

static void lmu_initrefs(lmu_Report *lr) {
    lr->config_ref = LUA_NOREF;
    lr->custom_level_ref = LUA_NOREF;
    lr->msg_ref = LUA_NOREF;
    lr->code_ref = LUA_NOREF;
    lr->color_ref = LUA_NOREF;
}

static int Lmu_report_new(lua_State *L) {
    size_t      pos = (size_t)luaL_optinteger(L, 1, 1);
    mu_Id       src_id = (mu_Id)luaL_optinteger(L, 2, 1);
    lmu_Report *lr = (lmu_Report *)lua_newuserdata(L, sizeof(lmu_Report));
    memset(lr, 0, sizeof(lmu_Report));
    lua_createtable(L, 8, 0);
    lua_setuservalue(L, -2);
    lr->R = mu_new(NULL, NULL);
    lr->pos = pos - 1;
    lr->src_id = src_id - 1;
    lmu_initrefs(lr);
    luaL_setmetatable(L, LMU_REPORT_TYPE);
    return 1;
}

static int Lmu_report_libcall(lua_State *L) {
    lua_remove(L, 1);
    return Lmu_report_new(L);
}

static int Lmu_report_delete(lua_State *L) {
    lmu_Report *lr = (lmu_Report *)luaL_checkudata(L, 1, LMU_REPORT_TYPE);
    if (lr && lr->R) mu_delete(lr->R), lr->R = NULL;
    return 0;
}

static lmu_Report *lmu_checkreport(lua_State *L, int idx) {
    lmu_Report *lr = (lmu_Report *)luaL_checkudata(L, idx, LMU_REPORT_TYPE);
    if (!lr || !lr->R)
        return luaL_error(L, "invalid Report"), (lmu_Report *)NULL;
    return lr;
}

static void lmu_checkerror(lua_State *L, int err) {
    switch (err) {
    case MU_OK:       return;
    case MU_ERRPARAM: luaL_error(L, "musubi: invalid parameter"); break;
    case MU_ERRSRC:   luaL_error(L, "musubi: source out of range"); break;
    case MU_ERRFILE:  luaL_error(L, "musubi: file operation failed"); break;
    default:          luaL_error(L, "musubi: unknown error(%d)", err); break;
    }
}

static int Lmu_report_reset(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    lua_createtable(L, 8, 0); /* clean the uservalue table */
    lua_setuservalue(L, 1);
    lmu_initrefs(lr);
    mu_reset(lr->R);
    return lua_settop(L, 1), 1;
}

static void lmu_register(lua_State *L, int *ref) {
    if (*ref != LUA_NOREF) lua_rawseti(L, -2, *ref);
    else *ref = luaL_ref(L, -2);
}

static int Lmu_report_config(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    mu_Config  *config = lmu_checkconfig(L, 2);
    lmu_checkerror(L, mu_config(lr->R, config));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    lmu_register(L, &lr->config_ref);
    return lua_settop(L, 1), 1;
}

static int Lmu_report_title(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    size_t      cllen, msglen;
    const char *custom_level = luaL_optlstring(L, 2, NULL, &cllen);
    const char *msg = luaL_optlstring(L, 3, NULL, &msglen);
    mu_Level    level = MU_CUSTOM_LEVEL;
    if (strcasecmp(custom_level, "error") == 0) level = MU_ERROR;
    else if (strcasecmp(custom_level, "warning") == 0) level = MU_WARNING;
    lmu_checkerror(L, mu_title(lr->R, level, mu_lslice(custom_level, cllen),
                               mu_lslice(msg, msglen)));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    lmu_register(L, &lr->custom_level_ref);
    lua_pushvalue(L, 3);
    lmu_register(L, &lr->msg_ref);
    return lua_settop(L, 1), 1;
}

static int Lmu_report_code(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    size_t      len;
    const char *code = luaL_checklstring(L, 2, &len);
    lmu_checkerror(L, mu_code(lr->R, mu_lslice(code, len)));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    lmu_register(L, &lr->code_ref);
    return lua_settop(L, 1), 1;
}

static int Lmu_report_label(lua_State *L) {
    mu_Report *R = lmu_checkreport(L, 1)->R;
    size_t     start = (size_t)luaL_checkinteger(L, 2);
    size_t     end = (size_t)luaL_optinteger(L, 3, start - 1);
    mu_Id      src_id = (mu_Id)luaL_optinteger(L, 4, 1);
    lmu_checkerror(L, mu_label(R, start - 1, end, src_id - 1));
    return lua_settop(L, 1), 1;
}

static int Lmu_report_message(lua_State *L) {
    mu_Report  *R = lmu_checkreport(L, 1)->R;
    size_t      len;
    const char *msg = luaL_checklstring(L, 2, &len);
    int         width = (int)luaL_optinteger(L, 3, 0);
    lmu_checkerror(L, mu_message(R, mu_lslice(msg, len), width));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    luaL_ref(L, -2); /* store the message string */
    return lua_settop(L, 1), 1;
}

static void lmu_pushcolorkind(lua_State *L, mu_ColorKind kind) {
    switch (kind) {
    case MU_COLOR_RESET:          lua_pushliteral(L, "reset"); break;
    case MU_COLOR_ERROR:          lua_pushliteral(L, "error"); break;
    case MU_COLOR_WARNING:        lua_pushliteral(L, "warning"); break;
    case MU_COLOR_KIND:           lua_pushliteral(L, "kind"); break;
    case MU_COLOR_MARGIN:         lua_pushliteral(L, "margin"); break;
    case MU_COLOR_SKIPPED_MARGIN: lua_pushliteral(L, "skipped_margin"); break;
    case MU_COLOR_UNIMPORTANT:    lua_pushliteral(L, "unimportant"); break;
    case MU_COLOR_NOTE:           lua_pushliteral(L, "note"); break;
    case MU_COLOR_LABEL:          lua_pushliteral(L, "label"); break;
    default:                      lua_pushliteral(L, "unknown"); break;
    }
}

typedef struct lmu_ColorFunc {
    lmu_Report *lr;
    int         func_ref;
} lmu_ColorFunc;

static mu_Chunk lmu_color_func(void *ud, mu_ColorKind kind) {
    lmu_ColorFunc *cf = (lmu_ColorFunc *)ud;

    lua_State  *L = cf->lr->L;
    size_t      len;
    const char *s;
    lua_rawgeti(L, 3, cf->func_ref);
    lmu_pushcolorkind(L, kind);
    lua_call(L, 1, 1);
    s = luaL_checklstring(L, -1, &len);
    len = (len < MU_COLOR_CODE_SIZE - 1) ? len : MU_COLOR_CODE_SIZE - 1;
    cf->lr->chunk_buf[0] = (char)len;
    memcpy(cf->lr->chunk_buf + 1, s, len);
    lua_pop(L, 1);
    return cf->lr->chunk_buf;
}

static int Lmu_report_color(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    int         ty = lua_type(L, 2);
    lua_getuservalue(L, 1);
    if (ty == LUA_TUSERDATA) {
        mu_ColorCode *code =
            (mu_ColorCode *)luaL_checkudata(L, 2, LMU_COLORCODE_TYPE);
        lmu_checkerror(L, mu_color(lr->R, mu_fromcolorcode, code));
    } else {
        lmu_ColorFunc *cf;
        luaL_checktype(L, 2, LUA_TFUNCTION);
        cf = (lmu_ColorFunc *)lua_newuserdata(L, sizeof(lmu_ColorFunc));
        lmu_checkerror(L, mu_color(lr->R, lmu_color_func, cf));
        lua_pushvalue(L, 2);
        cf->lr = lr, cf->func_ref = luaL_ref(L, -3);
        lua_replace(L, 2);
    }
    lua_pushvalue(L, 2);
    lmu_register(L, &lr->color_ref);
    return lua_settop(L, 1), 1;
}

static int Lmu_report_order(lua_State *L) {
    mu_Report *R = lmu_checkreport(L, 1)->R;
    int        order = (int)luaL_checkinteger(L, 2);
    lmu_checkerror(L, mu_order(R, order));
    return lua_settop(L, 1), 1;
}

static int Lmu_report_priority(lua_State *L) {
    mu_Report *R = lmu_checkreport(L, 1)->R;
    int        priority = (int)luaL_checkinteger(L, 2);
    lmu_checkerror(L, mu_priority(R, priority));
    return lua_settop(L, 1), 1;
}

static int Lmu_report_help(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    size_t      len;
    const char *help = luaL_checklstring(L, 2, &len);
    lmu_checkerror(L, mu_help(lr->R, mu_lslice(help, len)));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    luaL_ref(L, -2); /* store the help string */
    return lua_settop(L, 1), 1;
}

static int Lmu_report_note(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    size_t      len;
    const char *note = luaL_checklstring(L, 2, &len);
    lmu_checkerror(L, mu_note(lr->R, mu_lslice(note, len)));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    luaL_ref(L, -2); /* store the note string */
    return lua_settop(L, 1), 1;
}

static int Lmu_report_source(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    mu_Source  *src;
    int         ty = lua_type(L, 2);
    size_t      namelen;
    const char *name = luaL_optlstring(L, 3, "<unknown>", &namelen);
    int         offset = (int)luaL_optinteger(L, 4, 0);
    luaL_argcheck(L, ty == LUA_TSTRING || ty == LUA_TUSERDATA, 2,
                  "string/file* expected");
    if (ty == LUA_TUSERDATA) {
        FILE **fp = (FILE **)luaL_checkudata(L, 2, "FILE*");
        src = mu_file_source(lr->R, *fp, mu_lslice(name, namelen));
    } else {
        size_t      len;
        const char *s = luaL_checklstring(L, 2, &len);
        src = mu_memory_source(lr->R, mu_lslice(s, len),
                               mu_lslice(name, namelen));
    }
    src->line_no_offset = offset;
    lmu_checkerror(L, mu_source(lr->R, src));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    luaL_ref(L, -2); /* store the source string/file */
    lua_pushvalue(L, 3);
    luaL_ref(L, -2); /* store the source name */
    return lua_settop(L, 1), 1;
}

static int Lmu_report_file(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    size_t      namelen;
    const char *name = luaL_optlstring(L, 2, "<unknown>", &namelen);
    int         offset = (int)luaL_optinteger(L, 3, 0);
    mu_Source  *src = mu_file_source(lr->R, NULL, mu_lslice(name, namelen));
    luaL_argcheck(L, src != NULL, 2, "file source creation failed");
    src->line_no_offset = offset;
    lmu_checkerror(L, mu_source(lr->R, src));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 3);
    luaL_ref(L, -2); /* store the source name */
    return lua_settop(L, 1), 1;
}

static int lmu_func_writer(void *ud, const char *data, size_t len) {
    lmu_Report *lr = (lmu_Report *)ud;
    lua_State  *L = lr->L;

    int ret;
    lua_pushvalue(L, 2);
    lua_pushlstring(L, data, len);
    lua_call(L, 1, 1);
    ret = (int)luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);
    return ret;
}

static int lmu_string_writer(void *ud, const char *data, size_t len) {
    luaL_Buffer *B = (luaL_Buffer *)ud;
    luaL_addlstring(B, data, len);
    return 0;
}

static int Lmu_report_render(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    int         ty = lua_type(L, 2);
    lr->L = L;
    luaL_argcheck(L, ty == LUA_TFUNCTION || ty == LUA_TNONE, 2,
                  "optional function 'writer' expected");
    lua_settop(L, 2);
    lua_getuservalue(L, 1);
    if (ty == LUA_TFUNCTION) {
        lmu_checkerror(L, mu_writer(lr->R, lmu_func_writer, lr));
        lmu_checkerror(L, mu_render(lr->R, lr->pos, lr->src_id));
        return lua_settop(L, 1), 1;
    } else {
        luaL_Buffer B;
        luaL_buffinit(L, &B);
        lmu_checkerror(L, mu_writer(lr->R, lmu_string_writer, &B));
        lmu_checkerror(L, mu_render(lr->R, lr->pos, lr->src_id));
        return luaL_pushresult(&B), 1;
    }
}

static void lmu_openreport(lua_State *L) {
    luaL_Reg libs[] = {
        {"__index", NULL},
        {"__gc", Lmu_report_delete},
        {"__call", Lmu_report_libcall},
#define ENTRY(name) {#name, Lmu_report_##name}
        ENTRY(new),
        ENTRY(reset),
        ENTRY(delete),
        ENTRY(config),
        ENTRY(title),
        ENTRY(code),
        ENTRY(label),
        ENTRY(message),
        ENTRY(color),
        ENTRY(order),
        ENTRY(priority),
        ENTRY(source),
        ENTRY(file),
        ENTRY(render),
        ENTRY(help),
        ENTRY(note),
#undef ENTRY
        {NULL, NULL},
    };
    if (luaL_newmetatable(L, LMU_REPORT_TYPE)) {
        luaL_setfuncs(L, libs, 0);
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        lua_createtable(L, 0, 1);
        lua_pushcfunction(L, Lmu_report_libcall);
        lua_setfield(L, -2, "__call");
        lua_setmetatable(L, -2);
    }
}

LUAMOD_API int luaopen_musubi(lua_State *L) {
    lua_createtable(L, 0, 5);
    lmu_opencolorgen(L);
    lua_setfield(L, -2, "colorgen");
    lmu_openconfig(L);
    lua_setfield(L, -2, "config");
    lmu_openreport(L);
    lua_setfield(L, -2, "report");
    lua_pushliteral(L, MU_VERSION);
    lua_setfield(L, -2, "version");
    return 1;
}
