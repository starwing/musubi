#define LUA_LIB
#include <lauxlib.h>
#include <lua.h>

#define MU_STATIC_API
#include "musubi.h"

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

static void lmu_openconfig(lua_State *L) {
    luaL_Reg libs[] = {
        {"__index", NULL},
        {"new", NULL},
        {NULL, NULL},
    };
    if (luaL_newmetatable(L, LMU_CONFIG_TYPE)) {
        luaL_setfuncs(L, libs, 0);
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    }
}

/* source */

static void lmu_opensource(lua_State *L) {
    luaL_Reg libs[] = {
        {"memory", NULL},
        {"file", NULL},
        {NULL, NULL},
    };
    luaL_newlib(L, libs);
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
    size_t      pos = (size_t)luaL_optinteger(L, 1, 0);
    mu_Id       src_id = (mu_Id)luaL_optinteger(L, 2, 0);
    lmu_Report *lr = (lmu_Report *)lua_newuserdata(L, sizeof(lmu_Report));
    memset(lr, 0, sizeof(lmu_Report));
    lua_createtable(L, 8, 0);
    lua_setuservalue(L, -2);
    lr->R = mu_new(NULL, NULL);
    lr->pos = pos;
    lr->src_id = src_id;
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
    case MU_ERRPARAM: luaL_error(L, "musubi error: invalid parameter"); break;
    case MU_ERRSRC:   luaL_error(L, "musubi error: source out of range"); break;
    default:          luaL_error(L, "musubi error: unknown error: %d", err); break;
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
    const char *custom_level = luaL_optstring(L, 2, NULL);
    const char *msg = luaL_optstring(L, 3, NULL);
    mu_Level    level = MU_CUSTOM_LEVEL;
    if (strcasecmp(custom_level, "error") == 0) level = MU_ERROR;
    else if (strcasecmp(custom_level, "warning") == 0) level = MU_WARNING;
    lmu_checkerror(L, mu_title(lr->R, level, custom_level, msg));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    lmu_register(L, &lr->custom_level_ref);
    lua_pushvalue(L, 3);
    lmu_register(L, &lr->msg_ref);
    return lua_settop(L, 1), 1;
}

static int Lmu_report_code(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    const char *code = luaL_checkstring(L, 2);
    lmu_checkerror(L, mu_code(lr->R, code));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    lmu_register(L, &lr->code_ref);
    return lua_settop(L, 1), 1;
}

static int Lmu_report_label(lua_State *L) {
    mu_Report *R = lmu_checkreport(L, 1)->R;
    size_t     start = (size_t)luaL_checkinteger(L, 2);
    size_t     end = (size_t)luaL_optinteger(L, 3, start - 1);
    mu_Id      src_id = (mu_Id)luaL_optinteger(L, 4, 0);
    lmu_checkerror(L, mu_label(R, start - 1, end, src_id));
    return lua_settop(L, 1), 1;
}

static int Lmu_report_message(lua_State *L) {
    mu_Report  *R = lmu_checkreport(L, 1)->R;
    const char *msg = luaL_checkstring(L, 2);
    int         width = (int)luaL_optinteger(L, 3, 0);
    lmu_checkerror(L, mu_message(R, msg, width));
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

static mu_Chunk lmu_color_func(void *ud, mu_ColorKind kind) {
    lmu_Report *lr = (lmu_Report *)ud;
    lua_State  *L = lr->L;
    size_t      len;
    const char *s;

    lua_rawgeti(L, 3, lr->color_ref);
    lmu_pushcolorkind(L, kind);
    lua_call(L, 1, 1);
    s = luaL_checklstring(L, -1, &len);
    len = (len < MU_COLOR_CODE_SIZE - 1) ? len : MU_COLOR_CODE_SIZE - 1;
    lr->chunk_buf[0] = len;
    memcpy(lr->chunk_buf + 1, s, len);
    lua_pop(L, 1);
    return lr->chunk_buf;
}

static int Lmu_report_color(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    int         ty = lua_type(L, 2);
    if (ty == LUA_TUSERDATA) {
        mu_ColorCode *code =
            (mu_ColorCode *)luaL_checkudata(L, 2, LMU_COLORCODE_TYPE);
        lmu_checkerror(L, mu_color(lr->R, mu_fromcolorcode, code));
    } else {
        luaL_checktype(L, 2, LUA_TFUNCTION);
        lmu_checkerror(L, mu_color(lr->R, lmu_color_func, lr));
    }
    lua_getuservalue(L, 1);
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
    const char *help = luaL_checkstring(L, 2);
    lmu_checkerror(L, mu_help(lr->R, help));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    luaL_ref(L, -2); /* store the help string */
    return lua_settop(L, 1), 1;
}

static int Lmu_report_note(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    const char *note = luaL_checkstring(L, 2);
    lmu_checkerror(L, mu_note(lr->R, note));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    luaL_ref(L, -2); /* store the note string */
    return lua_settop(L, 1), 1;
}

static int Lmu_report_source(lua_State *L) {
    lmu_Report *lr = lmu_checkreport(L, 1);
    size_t      len;
    const char *s = luaL_checklstring(L, 2, &len);
    const char *name = luaL_optstring(L, 3, "<unknown>");
    mu_Source  *src = mu_memory_source(lr->R, s, len, name);
    lmu_checkerror(L, mu_source(lr->R, src));
    lua_getuservalue(L, 1);
    lua_pushvalue(L, 2);
    luaL_ref(L, -2); /* store the source string */
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
    lua_getmetatable(L, 1);
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
    lmu_opensource(L);
    lua_setfield(L, -2, "source");
    lmu_openreport(L);
    lua_setfield(L, -2, "report");
    lua_pushliteral(L, MU_VERSION);
    lua_setfield(L, -2, "version");
    return 1;
}
