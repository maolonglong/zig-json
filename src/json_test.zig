const std = @import("std");
const testing = std.testing;
const json = @import("./json.zig");

test "parseBool_true" {
    const a = testing.allocator;

    var s = std.io.fixedBufferStream(
        \\true
    );

    const v = try json.parse(a, s.reader());
    try testing.expect(v == .Bool);
    try testing.expect(v.Bool);
}

test "parseNull_null" {
    const a = testing.allocator;

    var s = std.io.fixedBufferStream(
        \\null
    );

    const v = try json.parse(a, s.reader());
    try testing.expect(v == .Null);
}

test "parseBool_false" {
    const a = testing.allocator;

    var s = std.io.fixedBufferStream(
        \\false
    );

    const v = try json.parse(a, s.reader());
    try testing.expect(v == .Bool);
    try testing.expect(!v.Bool);
}

test "parseBool_fal" {
    const a = testing.allocator;

    var s = std.io.fixedBufferStream(
        \\fal
    );

    const result = json.parse(a, s.reader());
    try testing.expectError(error.SyntaxError, result);
}

test "parseNumber_interger" {
    const a = testing.allocator;

    var s = std.io.fixedBufferStream(
        \\123
    );

    const v = try json.parse(a, s.reader());
    try testing.expect(v == .Number);
    try testing.expectEqual(@as(f64, 123), v.Number);
}

test "parseNumber_float" {
    const a = testing.allocator;

    var s = std.io.fixedBufferStream(
        \\1.5
    );

    const v = try json.parse(a, s.reader());
    try testing.expect(v == .Number);
    try testing.expectEqual(@as(f64, 1.5), v.Number);
}

test "parseObject" {
    const a = testing.allocator;

    var s = std.io.fixedBufferStream(
        \\{"name": "foo", "name2": "bar", "age": 10}
    );

    var v = try json.parse(a, s.reader());
    defer v.deinit(a);
    try testing.expect(v == .Object);
    try testing.expectEqualStrings("foo", v.Object.get("name").?.String.items);
    try testing.expectEqualStrings("bar", v.Object.get("name2").?.String.items);
    try testing.expectEqual(@as(f64, 10), v.Object.get("age").?.Number);
}

test "parseArray" {
    const a = testing.allocator;

    var s = std.io.fixedBufferStream(
        \\["123", 456]
    );

    var v = try json.parse(a, s.reader());
    defer v.deinit(a);
    try testing.expect(v == .Array);
    try testing.expectEqual(@as(usize, 2), v.Array.items.len);
    try testing.expectEqualStrings("123", v.Array.items[0].String.items);
    try testing.expectEqual(@as(f64, 456), v.Array.items[1].Number);
}

fn parseTestFile(allocator: std.mem.Allocator, comptime name: []const u8) !json.Value {
    var s = std.io.fixedBufferStream(@embedFile("./testdata/" ++ name));

    return json.parse(allocator, s.reader());
}

test "twitter" {
    const a = testing.allocator;

    var v = try parseTestFile(a, "twitter.json");
    defer v.deinit(a);

    try testing.expect(v == .Object);
    const search_metadata = v.Object.get("search_metadata").?;
    try testing.expect(search_metadata == .Object);
    try testing.expectEqualStrings("505874924095815681", search_metadata.Object.get("max_id_str").?.String.items);

    const statuses = v.Object.get("statuses").?;
    try testing.expect(statuses == .Array);
    const last_status = statuses.Array.getLast();
    try testing.expect(last_status == .Object);
    try testing.expectEqual(@as(f64, 505874847260352500), last_status.Object.get("id").?.Number);
}

test "citm_catalog" {
    const a = testing.allocator;

    var v = try parseTestFile(a, "citm_catalog.json");
    defer v.deinit(a);
}

test "canada" {
    const a = testing.allocator;

    var v = try parseTestFile(a, "canada.json");
    defer v.deinit(a);
}
