#if !defined(MU_IMPLEMENTATION)
#define MU_IMPLEMENTATION
#endif /* MU_IMPLEMENTATION */
#include <stdio.h>
#include <string.h>

#include "musubi.h"

static int stdout_writer(void *ud, const char *data, size_t len) {
    fwrite(data, 1, len, stdout);
    return 0; /* Success */
}

int main(void) {
    mu_Report   *R;
    mu_Cache    *C = NULL;
    mu_ColorGen  cg;
    mu_ColorCode color1;

    /* Initialize color generator */
    mu_initcolorgen(&cg, 0.5f);
    mu_gencolor(&cg, &color1);

    /* Create Cache and add a source */
    mu_addmemory(&C, mu_literal("local x = 10 + 'hello'"),
                 mu_literal("example.lua"));

    /* Create Report and configure */
    R = mu_new(NULL, NULL); /* NULL, NULL = use default malloc */
    mu_title(R, MU_ERROR, mu_literal(""), mu_literal("Type mismatch"));
    mu_code(R, mu_literal("E001"));
    mu_location(R, 14, 0); /* Position 14 in source 0 for header display */

    /* Add a label with message and color */
    mu_label(R, 15, 22, 0);
    mu_message(R, mu_literal("expected number, got string"), 0);
    mu_color(R, mu_fromcolorcode, &color1);

    /* Render to stdout */
    mu_writer(R, stdout_writer, NULL);
    mu_render(R, C);

    /* Cleanup */
    mu_delete(R);
    mu_delcache(C);
    return 0;
}