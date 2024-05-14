const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const allocator = std.heap.page_allocator;

const Payload = union(enum) {
    string: []const u8,
    int: i64,
    list: std.ArrayList(Payload),
    dict: std.StringArrayHashMap(Payload),
};

pub fn stringify(payload: Payload) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    switch (payload) {
        .string => |s| {
            try std.fmt.format(result.writer(), "\"{s}\"", .{s});
        },
        .int => |i| {
            var buf = std.ArrayList(u8).init(allocator);
            defer buf.deinit();
            try std.fmt.format(result.writer(), "{d}", .{i});
        },
        .list => |l| {
            try std.fmt.format(result.writer(), "[", .{});
            var i: usize = 0;
            for (l.items) |item| {
                try std.fmt.format(result.writer(), "{s}", .{try stringify(item)});
                if (i < l.items.len - 1) {
                    try std.fmt.format(result.writer(), ",", .{});
                }
                i += 1;
            }
            try std.fmt.format(result.writer(), "]", .{});
        },
        .dict => |d| {
            try std.fmt.format(result.writer(), "{{", .{});
            var i: usize = 0;
            for (d.keys()) |key| {
                try std.fmt.format(result.writer(), "\"{s}\":{s}", .{ key, try stringify(d.get(key).?) });
                if (i < d.keys().len - 1) {
                    try std.fmt.format(result.writer(), ",", .{});
                }
                i += 1;
            }
            try std.fmt.format(result.writer(), "}}", .{});
        },
    }
    return result.toOwnedSlice();
}

const DecodeResult = struct {
    payload: Payload,
    next: usize,
};

pub fn decodeBencode(encodedValue: []const u8, start: usize) !DecodeResult {
    if (encodedValue[start] >= '0' and encodedValue[start] <= '9') {
        // <length>:<string>
        return decodeString(encodedValue, start);
    } else if (encodedValue[start] == 'i') {
        //integers, i<number>e
        return decodeNumber(encodedValue, start);
    } else if (encodedValue[start] == 'l') {
        //lists, l<contents>e
        return decodeList(encodedValue, start);
    } else if (encodedValue[start] == 'd') {
        //dicts, d<key1><value1><key2><value2>...e
        return decodeDict(encodedValue, start);
    } else {
        try stderr.print("Unrecognized Type, the string to parse is {s}\n", .{encodedValue[start..]});
        std.process.exit(1);
    }
}

pub fn decodeNumber(encodedValue: []const u8, start: usize) !DecodeResult {
    if (encodedValue[start] != 'i') {
        return error.InvalidArgument;
    }
    const e_char_maybe = std.mem.indexOf(u8, encodedValue[start..], "e");
    if (e_char_maybe == null) {
        return error.InvalidArgument;
    }
    const e_char_index = start + e_char_maybe.?;
    return DecodeResult{
        .payload = Payload{
            .int = try std.fmt.parseInt(i64, encodedValue[start + 1 .. e_char_index], 10),
        },
        .next = start + e_char_maybe.? + 1,
    };
}

pub fn decodeString(encodedValue: []const u8, start: usize) !DecodeResult {
    if (encodedValue[start] > '9' or encodedValue[start] < '0') {
        return error.InvalidArgument;
    }
    const firstColonMaybe = std.mem.indexOf(u8, encodedValue[start..], ":");
    if (firstColonMaybe == null) {
        return error.InvalidArgument;
    }
    const firstColon = start + firstColonMaybe.?;
    const length = try std.fmt.parseInt(usize, encodedValue[start..firstColon], 10);
    return DecodeResult{
        .payload = Payload{
            .string = encodedValue[firstColon + 1 .. firstColon + 1 + length],
        },
        .next = firstColon + 1 + length,
    };
}

pub fn decodeList(encodedValue: []const u8, start: usize) anyerror!DecodeResult {
    if (encodedValue[start] != 'l') {
        return error.InvalidArgument;
    }
    var next = start + 1;
    var list = std.ArrayList(Payload).init(allocator);
    while (encodedValue[next] != 'e') {
        const result = try decodeBencode(encodedValue, next);
        try list.append(result.payload);
        next = result.next;
    }
    return DecodeResult{
        .payload = Payload{
            .list = list,
        },
        .next = next + 1,
    };
}

pub fn decodeDict(encodedValue: []const u8, start: usize) anyerror!DecodeResult {
    if (encodedValue[start] != 'd') {
        return error.InvalidArgument;
    }
    var next = start + 1;
    var dict = std.StringArrayHashMap(Payload).init(allocator);
    while (encodedValue[next] != 'e') {
        const keyResult = try decodeString(encodedValue, next);
        const key = keyResult.payload.string;
        next = keyResult.next;
        const valueResult = try decodeBencode(encodedValue, next);
        try dict.put(key, valueResult.payload);
        next = valueResult.next;
    }
    return DecodeResult{
        .payload = Payload{
            .dict = dict,
        },
        .next = next + 1,
    };
}
