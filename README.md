# zig-build-gen

This is the code generator used to genereate the metal api bindings found at
https://github.com/dmbfm/zig-metal.

The generator uses libclang to parse the Metal API's objective-c headers and
generate the zig bindings. Currently the path to libclang is hard-coded in the
`build.zig` file, so you shoud replace the line:
```zig
    exe.addLibraryPath(.{ .path = "/opt/homebrew/opt/llvm/lib" });
```
to whatever path makes sense for you.

Running `zig build run` will output the contents of the binding, i.e., `zig
build run > out.zig` will create a `out.zig` file with usable bindgins.

