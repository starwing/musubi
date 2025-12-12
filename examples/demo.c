#define MU_STATIC_API
#include "musubi.h"

typedef struct buff {
    size_t n;
    char   s[4096];
} buff;

static int writer(void *ud, const char *data, size_t len) {
    buff *b = (buff *)ud;
    if (b->n + len >= sizeof(b->s)) return 1;
    memcpy(b->s + b->n, data, len);
    b->n += len;
    return 0;
}

int main(void) {
    mu_Report  *R = mu_new(NULL, NULL);
    mu_ColorGen cg;
    const char *code;

    buff b;
    mu_initcolorgen(&cg, 0.5f);
    mu_ColorCode label1, label2, label3, label4, label5;
    mu_gencolor(&cg, &label1);
    mu_gencolor(&cg, &label2);
    mu_gencolor(&cg, &label3);
    mu_gencolor(&cg, &label4);
    mu_gencolor(&cg, &label5);

    mu_code(R, mu_literal("3"));
    mu_title(R, MU_ERROR, mu_literal(""), mu_literal("Incompatible types"));
    mu_location(R, 11, 0);
    mu_label(R, 32, 33, 0);
    mu_message(R, mu_literal("This is of type Nat"), 0);
    mu_color(R, mu_fromcolorcode, &label1);
    mu_label(R, 42, 45, 0);
    mu_message(R, mu_literal("This is of type Str"), 0);
    mu_color(R, mu_fromcolorcode, &label2);
    mu_label(R, 11, 48, 0);
    mu_message(
        R, mu_literal("This values are outputs of this match expression"), 0);
    mu_color(R, mu_fromcolorcode, &label3);
    mu_label(R, 0, 48, 0);
    mu_message(R, mu_literal("The definition has a problem"), 0);
    mu_color(R, mu_fromcolorcode, &label4);
    mu_label(R, 50, 76, 0);
    mu_message(R, mu_literal("Usage of definition here"), 0);
    mu_color(R, mu_fromcolorcode, &label5);
    mu_note(R,
            mu_literal(
                "Outputs of match expressions must coerce to the same type"));

    code =
        "def five = match () in {\n"
        "\t() => 5,\n"
        "\t() => \"5\",\n"
        "}\n"
        "\n"
        "def six =\n"
        "    five\n"
        "    + 1\n";
    b.n = 0;
    mu_writer(R, writer, &b);
    mu_render(
        R,
        &mu_addmemory(NULL, mu_slice(code), mu_literal("sample.tao"))->cache);
    mu_delete(R);
    b.s[b.n] = '\0';
    printf("length: %zu\n", b.n);
    printf("%s", b.s);
    return 0;
}