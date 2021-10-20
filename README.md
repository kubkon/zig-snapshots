# zig-snapshots

A tool allowing you to preview a series of snapshots of Zig's incremental linker.

## Usage

You will need to build Zig's stage2/self-hosted compiler with `-Dsnapshots` flag on:

```
$ zig build -Dsnapshot
```

Then, you can run the compiler either in a fire-and-forget or watch-for-updates manner
and it will automatically generate a snapshot of the linker's state per incremental update,
all saved in the same JSON output file:

```
$ zig build-exe hello.zig --watch
> update-and-run
> update-and-run
> exit

$ file snapshots.json
snapshots.json: JSON data
```

You should then feed the output JSON file to `zig-snapshots` which will generate an
HTML file with the linker's state per each incremental update that you can interative with:

```
$ zig-out/bin/zig-snapshots snapshots.json
$ file snapshots.html
snapshots.html: HTML document text, ASCII text
```

