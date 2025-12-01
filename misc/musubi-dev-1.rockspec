package = "musubi"
version = "dev-1"
source = {
   url = "git+https://github.com/starwing/musubi"
}
description = {
   summary = "A beautiful diagnostics renderer for compiler errors and warnings",
   detailed = "A beautiful diagnostics renderer for compiler errors and warnings",
   homepage = "https://github.com/starwing/musubi",
   license = "MIT License"
}
build = {
   type = "builtin",
   modules = {
      musubi = {
         sources = "musubi.c"
      }
   },
}