const std = @import("std");

fn findModule(comptime module_name: []const u8, gpa: std.mem.Allocator) !?[][]const u8 {
    var ret = std.ArrayList([]const u8).init(gpa);
    defer ret.deinit();

    switch (@import("builtin").os.tag) {
        .linux => try std.os.dl_iterate_phdr(&ret, anyerror, struct {
            fn cb(info: *std.os.dl_phdr_info, size: usize, ctx: *std.ArrayList([]const u8)) !void {
                _ = size;
                if (!std.mem.endsWith(u8, std.mem.span(info.dlpi_name).?, "/" ++ module_name ++ ".so")) return;
                for (info.dlpi_phdr[0..info.dlpi_phnum]) |phdr| {
                    const base: usize = info.dlpi_addr + phdr.p_paddr;
                    const mem = @as([*]const u8, @ptrFromInt(base))[0..phdr.p_memsz];
                    try ctx.append(mem);
                }
            }
        }.cb),
        .windows => {
            // Fucking hell Microsoft, why is this so hard
            const windows = std.os.windows;

            const process_handle = windows.kernel32.GetCurrentProcess();

            var modules: [512]windows.HMODULE = undefined;
            var bytes: windows.DWORD = undefined;
            if (windows.kernel32.K32EnumProcessModules(
                process_handle,
                &modules,
                modules.len * @sizeOf(windows.DWORD),
                &bytes,
            ) == 0) bytes = 0;

            const nmods = bytes / @sizeOf(windows.DWORD);

            for (modules[0..nmods]) |module| {
                var name_buf: [std.c.PATH_MAX:0]u8 = undefined;
                const name_len = windows.kernel32.K32GetModuleFileNameExA(
                    process_handle,
                    module,
                    &name_buf,
                    std.c.PATH_MAX,
                );

                if (name_len < 0) continue;

                var info: windows.MODULEINFO = undefined;
                if (windows.kernel32.K32GetModuleInformation(
                    process_handle,
                    module,
                    &info,
                    @sizeOf(@TypeOf(info)),
                ) == 0) continue;

                if (std.mem.endsWith(u8, name_buf[0..name_len], "\\" ++ module_name ++ ".dll")) {
                    try ret.append(@as([*]const u8, @ptrCast(info.lpBaseOfDll))[0..info.SizeOfImage]);
                }
            }
        },
        else => @compileError("Unsupported OS"),
    }

    return if (ret.items.len == 0) null else try ret.toOwnedSlice();
}

pub fn getVersion(gpa: std.mem.Allocator) !u16 {
    const engine_mems = try findModule("engine", gpa) orelse return error.UnknownEngineBuild;
    for (engine_mems) |mem| {
        const idx = std.mem.indexOf(u8, mem, "Exe build:") orelse continue;
        const date_str = mem[idx + 20 .. idx + 31];

        const mons = [_][]const u8{
            "Jan", "Feb", "Mar", "Apr",
            "May", "Jun", "Jul", "Aug",
            "Sep", "Oct", "Nov", "Dec",
        };

        const mon_days = [_]u8{
            31, 28, 31, 30,
            31, 30, 31, 31,
            30, 31, 30, 31,
        };

        var d: u8 = 0;
        var m: u8 = 0;
        var y: u16 = 0;
        while (m < 11) : (m += 1) {
            if (std.mem.eql(u8, date_str[0..3], mons[m])) break;
            d += mon_days[m];
        }

        if (date_str[4] == ' ') {
            d += (date_str[5] - '0') - 1;
        } else {
            d += (date_str[4] - '0') * 10 + (date_str[5] - '0') - 1;
        }

        y = (std.fmt.parseInt(u16, date_str[7..11], 10) catch 0) - 1900;

        var build_num: u16 = @intFromFloat(@as(f32, @floatFromInt(y - 1)) * 365.25);
        build_num += d;
        if (y % 4 == 0 and m > 1) build_num += 1;
        build_num -= 35739;

        return build_num;
    }

    return error.UnknownEngineBuild;
}
