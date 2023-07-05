const std = @import("std");
const sdk = @import("sdk");
const tier0 = @import("tier0.zig");
const interface = @import("interface.zig");
const mods = @import("mods.zig");
const surface = @import("surface.zig");
const thud = @import("thud.zig");
const render_manager = @import("render_manager.zig");

comptime {
    _ = @import("api.zig");
}

pub const std_options = struct {
    pub const log_level: std.log.Level = .debug;
    pub const logFn = @import("log.zig").log;
};

var gpa: std.heap.GeneralPurposeAllocator(.{
    .stack_trace_frames = 8,
}) = undefined;

/// This is a random value created when Wormhole loads and persisted throughout the game's lifetime.
/// Named resources such as textures should incorporate this value into their names. This prevents
/// instances of Wormhole from fighting with each other across unloads/reloads.
pub var wh_resource_prefix: u32 = undefined;

fn init() !void {
    gpa = .{};
    errdefer _ = gpa.deinit();

    std.os.getrandom(std.mem.asBytes(&wh_resource_prefix)) catch return error.RandomInitFailed;

    const version = try @import("version.zig").getVersion(gpa.allocator());
    // TODO: load offsets etc
    _ = version;

    // Always init tier0 first so we have logging
    try tier0.init();

    if (!sdk.init()) return error.SdkInitError;

    try interface.init(gpa.allocator());
    errdefer interface.deinit();

    surface.init(gpa.allocator());

    try mods.init(gpa.allocator());
    errdefer mods.deinit();

    try thud.init(gpa.allocator());
    errdefer thud.deinit();

    try render_manager.init(gpa.allocator());
    errdefer render_manager.deinit();
}

fn deinit() void {
    render_manager.deinit();
    thud.deinit();
    mods.deinit();
    interface.deinit();
    _ = gpa.deinit();
}

// Plugin callbacks below

const Method = switch (@import("builtin").os.tag) {
    .windows => std.builtin.CallingConvention.Thiscall,
    else => std.builtin.CallingConvention.C,
};

// For some reason the game calls 'unload' if 'load' fails. We really don't
// want this, so we just ignore calls to 'unload' unless we're fully loaded
var loaded = false;

fn load(_: *sdk.IServerPluginCallbacks, interfaceFactory: sdk.CreateInterfaceFn, gameServerFactory: sdk.CreateInterfaceFn) callconv(Method) bool {
    _ = interfaceFactory;
    _ = gameServerFactory;

    init() catch |err| {
        std.log.err("Error initializing Wormhole: {s}", .{@errorName(err)});
        return false;
    };

    loaded = true;

    return true;
}

fn unload(_: *sdk.IServerPluginCallbacks) callconv(Method) void {
    if (!loaded) return;
    deinit();
}

fn pause(_: *sdk.IServerPluginCallbacks) callconv(Method) void {}

fn unpause(_: *sdk.IServerPluginCallbacks) callconv(Method) void {}

fn getPluginDescription(_: *sdk.IServerPluginCallbacks) callconv(Method) [*:0]const u8 {
    return "Wormhole: a mod loader for Portal 2";
}

fn levelInit(_: *sdk.IServerPluginCallbacks, map_name: [*:0]const u8) callconv(Method) void {
    _ = map_name;
}

fn serverActivate(_: *sdk.IServerPluginCallbacks, edict_list: [*]sdk.Edict, edict_count: c_int, client_max: c_int) callconv(Method) void {
    _ = edict_list;
    _ = edict_count;
    _ = client_max;
}

fn gameFrame(_: *sdk.IServerPluginCallbacks, simulating: bool) callconv(Method) void {
    _ = simulating;
}

fn levelShutdown(_: *sdk.IServerPluginCallbacks) callconv(Method) void {}

fn clientActive(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict) callconv(Method) void {
    _ = entity;
}

fn clientFullyConnect(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict) callconv(Method) void {
    _ = entity;
}

fn clientDisconnect(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict) callconv(Method) void {
    _ = entity;
}

fn clientPutInServer(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict, player_name: [*:0]const u8) callconv(Method) void {
    _ = entity;
    _ = player_name;
}

fn setCommandClient(_: *sdk.IServerPluginCallbacks, index: c_int) callconv(Method) void {
    _ = index;
}

fn clientSettingsChanged(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict) callconv(Method) void {
    _ = entity;
}

fn clientConnect(_: *sdk.IServerPluginCallbacks, allow: *bool, entity: *sdk.Edict, name: [*:0]const u8, addr: [*:0]const u8, reject: [*:0]u8, max_reject_len: c_int) callconv(Method) c_int {
    _ = allow;
    _ = entity;
    _ = name;
    _ = addr;
    _ = reject;
    _ = max_reject_len;
    return 0;
}

fn clientCommand(_: *sdk.IServerPluginCallbacks, entity: *sdk.Edict, args: *const sdk.CCommand) callconv(Method) c_int {
    _ = entity;
    _ = args;
    return 0;
}

fn networkIdValidated(_: *sdk.IServerPluginCallbacks, user_name: [*:0]const u8, network_id: [*:0]const u8) callconv(Method) c_int {
    _ = user_name;
    _ = network_id;
    return 0;
}

fn onQueryCvarValueFinished(_: *sdk.IServerPluginCallbacks, cookie: sdk.QueryCvarCookie, player: *sdk.Edict, status: sdk.QueryCvarValueStatus, name: [*:0]const u8, val: [*:0]const u8) callconv(Method) void {
    _ = cookie;
    _ = player;
    _ = status;
    _ = name;
    _ = val;
}

fn onEdictAllocated(_: *sdk.IServerPluginCallbacks, edict: *sdk.Edict) callconv(Method) void {
    _ = edict;
}

fn onEdictFreed(_: *sdk.IServerPluginCallbacks, edict: *const sdk.Edict) callconv(Method) void {
    _ = edict;
}

// Automatically generates the IServerPluginCallbacks vtable from the
// functions defined in this file
var callbacks = sdk.IServerPluginCallbacks{ .data = .{
    ._vt = &blk: {
        var vt: sdk.IServerPluginCallbacks.Vtable = undefined;
        for (std.meta.fieldNames(@TypeOf(vt))) |name| {
            @field(vt, name) = &@field(@This(), name);
        }
        break :blk vt;
    },
} };

// The function we expose to the game!
export fn CreateInterface(name: [*:0]u8, ret: ?*c_int) ?*anyopaque {
    if (!std.mem.eql(u8, std.mem.span(name), "ISERVERPLUGINCALLBACKS003")) {
        if (ret) |r| r.* = 0;
        return &callbacks;
    }

    if (ret) |r| r.* = 1;
    return null;
}
