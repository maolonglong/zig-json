const std = @import("std");

const fifo = std.fifo;
const fmt = std.fmt;
const io = std.io;
const mem = std.mem;

const assert = std.debug.assert;
const Allocator = mem.Allocator;

pub const Error = fmt.ParseFloatError || Allocator.Error || error{
    SyntaxError,
    EndOfStream,
};

pub const Value = union(enum) {
    const Self = @This();

    Null,
    Object: std.StringHashMapUnmanaged(Value),
    Array: std.ArrayListUnmanaged(Value),
    String: std.ArrayListUnmanaged(u8),
    Number: f64,
    Bool: bool,

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.deallocate(allocator);
        self.* = undefined;
    }

    fn deallocate(self: *Self, allocator: Allocator) void {
        switch (self.*) {
            .Object => {
                var it = self.Object.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                self.Object.deinit(allocator);
            },
            .Array => {
                for (self.Array.items) |*item| {
                    item.deinit(allocator);
                }
                self.Array.deinit(allocator);
            },
            .String => self.String.deinit(allocator),
            else => {},
        }
    }
};

fn StreamError(comptime stream_type: type) type {
    return switch (@typeInfo(stream_type)) {
        .Pointer => |p| p.child.Error,
        .Struct => stream_type.Error,
        else => unreachable,
    };
}

fn ParseResult(comptime stream_type: type, comptime T: type) type {
    return (StreamError(stream_type) || Error)!T;
}

pub fn parse(allocator: Allocator, io_reader: anytype) ParseResult(@TypeOf(io_reader), Value) {
    var stream = io.peekStream(1, io_reader);
    return parseValue(allocator, &stream);
}

fn parseValue(allocator: Allocator, stream: anytype) ParseResult(@TypeOf(stream), Value) {
    skipSpace(stream);

    const v = switch (try peekByte(stream)) {
        'n' => Value{ .Null = try parseNull(allocator, stream) },
        '{' => Value{ .Object = try parseObject(allocator, stream) },
        '[' => Value{ .Array = try parseArray(allocator, stream) },
        '"' => Value{ .String = try parseString(allocator, stream) },
        '0'...'9', '-', 'e', '.' => Value{ .Number = try parseNumber(allocator, stream) },
        't' => Value{ .Bool = try parseBool(allocator, stream) },
        'f' => Value{ .Bool = try parseBool(allocator, stream) },
        else => return error.SyntaxError,
    };

    skipSpace(stream);
    return v;
}

fn parseNull(allocator: Allocator, stream: anytype) ParseResult(@TypeOf(stream), void) {
    _ = allocator;

    const r = stream.reader();
    var buf = [_]u8{0} ** 4;
    var i: usize = 0;

    loop: while (true) {
        const b = r.readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        switch (b) {
            'n', 'u', 'l' => {
                buf[i] = b;
                i += 1;
                if (i == 4) {
                    break :loop;
                }
            },
            else => {
                stream.putBackByte(b) catch unreachable;
                break :loop;
            },
        }
    }

    if (!std.mem.eql(u8, buf[0..i], "null"))
        return error.SyntaxError;
}

fn parseObject(allocator: Allocator, stream: anytype) ParseResult(@TypeOf(stream), std.StringHashMapUnmanaged(Value)) {
    const r = stream.reader();
    var b = r.readByte() catch unreachable;
    assert(b == '{');

    var m = std.StringHashMapUnmanaged(Value){};
    errdefer {
        var v = Value{ .Object = m };
        v.deinit(allocator);
    }

    skipSpace(stream);
    b = try r.readByte();
    if (b == '}') {
        return m;
    } else {
        stream.putBackByte(b) catch unreachable;
    }

    while (true) {
        skipSpace(stream);
        var key = try parseString(allocator, stream);
        defer key.deinit(allocator);
        skipSpace(stream);
        b = try r.readByte();
        if (b != ':') return error.SyntaxError;
        const value = try parseValue(allocator, stream);
        try m.put(allocator, try key.toOwnedSlice(allocator), value);
        b = try r.readByte();
        if (b == '}') {
            break;
        } else if (b != ',') {
            return error.SyntaxError;
        }
    }

    return m;
}

fn parseArray(allocator: Allocator, stream: anytype) ParseResult(@TypeOf(stream), std.ArrayListUnmanaged(Value)) {
    const r = stream.reader();
    var b = r.readByte() catch unreachable;
    assert(b == '[');

    var a = std.ArrayListUnmanaged(Value){};
    errdefer {
        var v = Value{ .Array = a };
        v.deinit(allocator);
    }

    skipSpace(stream);
    b = try r.readByte();
    if (b == ']') {
        return a;
    } else {
        stream.putBackByte(b) catch unreachable;
    }

    while (true) {
        const value = try parseValue(allocator, stream);
        try a.append(allocator, value);
        b = try r.readByte();
        if (b == ']') {
            break;
        } else if (b != ',') {
            return error.SyntaxError;
        }
    }

    return a;
}

fn parseString(allocator: Allocator, stream: anytype) ParseResult(@TypeOf(stream), std.ArrayListUnmanaged(u8)) {
    const r = stream.reader();
    var b = r.readByte() catch unreachable;
    assert(b == '"');

    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);

    while (true) {
        b = try r.readByte();
        if (b == '\\') {
            b = switch (try r.readByte()) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '"' => '"',
                '\\' => '\\',
                else => return error.SyntaxError,
            };
        } else if (b == '"') {
            break;
        }
        try buf.append(allocator, b);
    }
    return buf;
}

fn parseBool(allocator: Allocator, stream: anytype) ParseResult(@TypeOf(stream), bool) {
    _ = allocator;

    const r = stream.reader();
    var buf = [_]u8{0} ** 5;
    var i: usize = 0;

    loop: while (true) {
        const b = r.readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        switch (b) {
            't', 'r', 'u', 'e', 'f', 'a', 'l', 's' => {
                buf[i] = b;
                i += 1;
                if (i == 5) {
                    break :loop;
                }
            },
            else => {
                stream.putBackByte(b) catch unreachable;
                break :loop;
            },
        }
    }

    if (std.mem.eql(u8, buf[0..i], "true")) return true;
    if (std.mem.eql(u8, buf[0..i], "false")) return false;
    return error.SyntaxError;
}

fn parseNumber(allocator: Allocator, stream: anytype) ParseResult(@TypeOf(stream), f64) {
    const r = stream.reader();
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    loop: while (true) {
        const b = r.readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        switch (b) {
            '0'...'9', '-', 'e', '.' => {
                try buf.append(b);
            },
            else => {
                stream.putBackByte(b) catch unreachable;
                break :loop;
            },
        }
    }

    return try std.fmt.parseFloat(f64, buf.items);
}

fn skipSpace(stream: anytype) void {
    const r = stream.reader();
    loop: while (true) {
        switch (r.readByte() catch 0) {
            ' ', '\t', '\r', '\n' => {},
            else => |b| {
                if (b != 0) stream.putBackByte(b) catch unreachable;
                break :loop;
            },
        }
    }
}

fn peekByte(stream: anytype) (StreamError(@TypeOf(stream)) || error{EndOfStream})!u8 {
    const b = try stream.reader().readByte();
    stream.putBackByte(b) catch unreachable;
    return b;
}
