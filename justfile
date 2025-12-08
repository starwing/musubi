lua:
    luarocks make misc/musubi-dev-1.rockspec

[windows]
lua:
    cl /nologo /W3 /MT /GS- /GL /Gy /Oy- /O2 /Oi \
    /DNDEBUG /DLUA_BUILD_AS_DLL \
    /I C:\Devel\Lua54\include C:\Devel\Lua54\lib\lua54.lib \
    /LD musubi.c /Felua-utf8.dll

t *args:
    gcc -shared -fPIC -ggdb -Wall -undefined dynamic_lookup \
        -o musubi.so musubi.c
    lua tests/test.lua {{args}}

test: lua
    lua tests/test.lua

coverage:
    rm -f *.gc*
    CFLAGS="--coverage -ggdb" LDFLAGS=--coverage \
        luarocks make misc/musubi-dev-1.rockspec
    lua tests/test.lua
    lcov --capture --directory . --exclude musubi.c --output-file lcov.info
    lcov --capture --directory . --output-file lcov.info
    genhtml --output-directory coverages lcov.info

svg:
    lua examples/demo.lua | \
        ansisvg --grid --colorscheme "iTerm2 Solarized Dark" \
        --fontfile ~/Library/Fonts/MapleMono-NF-Regular.ttf > misc/demo.svg
