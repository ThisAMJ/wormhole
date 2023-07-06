//! This contains all references and links to the tier0 library. As a special
//! case, tier0 is not a part of the main Wormhole state, instead containing its
//! own global state. This is because tier0 is required for core logging
//! behavior, so must always be initialized first so that further errors can
//! trigger log output.
//!
//! tier0 functions should not be used directly. Instead, use `std.log`, whose
//! logging function is implemented in log.zig.

const std = @import("std");
const sdk = @import("sdk");

pub fn init() !void {
    var lib = try std.DynLib.open(names.lib);
    defer lib.close();

    inline for (comptime std.meta.fieldNames(@TypeOf(names))) |field| {
        if (comptime std.mem.eql(u8, field, "lib")) continue;
        const func = &@field(@This(), field);
        const name = @field(names, field);
        func.* = lib.lookup(@TypeOf(func.*), name) orelse return error.SymbolNotFound;
    }

    ready = true;

    std.log.debug("Initialized tier0", .{});
}

const FmtFn = *const fn (fmt: [*:0]const u8, ...) callconv(.C) void;
pub var msg: FmtFn = undefined;
pub var warning: FmtFn = undefined;
pub var colorMsg: *const fn (color: *const sdk.Color, fmt: [*:0]const u8, ...) callconv(.C) void = undefined;
pub var devMsg: FmtFn = undefined;
pub var devWarning: FmtFn = undefined;
pub var ready: bool = false;

const names = switch (@import("builtin").os.tag) {
    .windows => .{
        .lib = "tier0.dll",
        .msg = "Msg",
        .warning = "Warning",
        .colorMsg = "?ConColorMsg@@YAXABVColor@@PBDZZ",
        .devMsg = "?DevMsg@@YAXPBDZZ",
        .devWarning = "?DevWarning@@YAXPBDZZ",
    },
    .linux => .{
        .lib = "libtier0.so",
        .msg = "Msg",
        .warning = "Warning",
        .colorMsg = "_Z11ConColorMsgRK5ColorPKcz",
        .devMsg = "_Z6DevMsgPKcz",
        .devWarning = "_Z10DevWarningPKcz",
    },
    .macos => .{
        .lib = "libtier0.dylib",
        .msg = "Msg",
        .warning = "Warning",
        .colorMsg = "_Z11ConColorMsgRK5ColorPKcz",
        .devMsg = "_Z6DevMsgPKcz",
        .devWarning = "_Z10DevWarningPKcz",
    },
    else => @compileError("Unsupported OS"),
};
