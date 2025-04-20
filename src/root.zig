const std = @import("std");
const Allocator = std.mem.Allocator;

const math = struct {
    pub usingnamespace @import("ghmath");
    pub usingnamespace std.math;
};

/// In `ReleaseFast` and `ReleaseSmall` builds: If `ok` is `false`, it is **undefined behavior**.
///
/// In `Debug` and `ReleaseSafe` builds: If `ok` is `false`, panics with an error message defined by `fail_fmt` and `fail_fmt_args`.
///
/// This function is basically `std.debug.assert`, but with custom assertion failed message.
pub fn assert(ok: bool, comptime fail_fmt: []const u8, fail_fmt_args: anytype) void {
    const builtin = @import("builtin");

    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        if (!ok) std.debug.panic(fail_fmt, fail_fmt_args);
    } else {
        if (!ok) unreachable; // Assertion failed
    }
}

const Vec2 = math.Vec2;
const Vec4 = math.Vec4;

/// There are 5 ways to create a grid:
///
/// - The first one (and the simplest) is to construct the grid from existing elements array. **The grid will reference the data for its entire lifetime.** To do it, pass elements slice to the `Grid(...).fromElements(...)` function.
/// - The second one is to allocate all the element data in binary's static memory. `Grid(...).static(...)` function can help with that. Size of such grid must be known at compile time.
/// - The third one is to allocate all the element data dynamically, using an allocator. `Grid(...).alloc(...)` function is used in that case. Use `Grid.free(...)` to deinitialize a dynamically allocated grid.
/// - The fourth, and the most interesting one, is to create a grid that is a view into other grid. `Grid(...).view(...)` function can be used to create a view. **A view will reference original's grid data, so be careful with lifetimes.**
/// - The fifth is to create an empty grid, using `Grid(...).empty(...)` function. This will create a grid with both width and height set to zeroes. If grid's width or grid's height is zero, is is considered an empty grid.
pub fn GridEx(
    comptime Element: type,
    comptime Extension: ?fn (comptime T: type) type,
) type {
    return struct {
        elements: []Element,
        size: Vec2(u32),
        parent_width: u32,

        /// Returns an *empty grid* with `size` set to `.{0, 0}`.
        pub fn empty() @This() {
            return @This(){ .elements = &.{}, .size = .{ 0, 0 }, .parent_width = 0 };
        }

        /// Construct a grid from `elements` slice with specified size. Result will reference data pointed by `elements`.
        pub fn fromElements(elements: []Element, size: Vec2(u32)) @This() {
            return @This(){ .elements = elements, .size = size, .parent_width = size[0] };
        }

        /// Construct a grid which data is static. Size must be comptime known. All the elements are initialized to `fill_with`.
        pub fn static(comptime size: Vec2(u32), comptime fill_with: Element) @This() {
            return @This(){
                .elements = &(struct {
                    pub var elements: [size[0] * size[1]]Element = [1]Element{fill_with} ** size[0] ** size[1];
                }.elements),
                .size = size,
                .parent_width = size[0],
            };
        }

        /// Construct a grid which data is dynamically allocated using specified allocator. All the elements are initialized to `undefined`. Use `Grid.free(...)` to deinitialize such grid.
        pub fn alloc(allocator: Allocator, size: Vec2(u32)) Allocator.Error!@This() {
            return @This(){
                .elements = try allocator.alloc(Element, size[0] * size[1]),
                .size = size,
                .parent_width = size[0],
            };
        }

        /// Deinitialize a grid constructed with `GridEx(...).alloc(...)`. **It is not valid to use this method with a grid that is constructed in a different than `GridEx(...).alloc(...)` way.**
        pub fn free(grid: *const @This(), allocator: Allocator) void {
            allocator.free(grid.elements);
        }

        /// Returns `true` if `grid` is an *empty grid*. An empty grid is a grid with `size[0]` and/or `size[1]` set to 0.
        pub fn isEmpty(grid: @This()) bool {
            return grid.size[0] == 0 or grid.size[1] == 0;
        }

        /// Get a view into `grid`. The view is a grid that references part of element data of `grid` defined by `pos` and `size`.
        pub fn view(grid: *const @This(), pos: Vec2(i32), size: Vec2(u32)) @This() {
            if (size[0] == 0 or size[1] == 0) return empty();

            const size_i32: Vec2(i32) = @intCast(size);

            if (!grid.inBounds(pos) or !(grid.inBounds(pos + size_i32 - Vec2(i32){ 1, 1 }))) return empty();

            return @This(){
                .elements = @as([*]Element, @ptrCast(grid.at(pos)))[0 .. size[1] * grid.parent_width],
                .size = size,
                .parent_width = grid.parent_width,
            };
        }

        // pub fn clip(grid: *const @This(), pos: Vec2(i32), size: Vec2(u32)) @This() {
        //     const offset_x =

        //     const new_size = @min(size, @as(Vec2(u32), @intCast(@max(Vec2(u32){ 0, 0 }, grid.size -| @abs(pos) +| size))));

        //     return grid.view(@max(Vec2(i32){ 0, 0 }, pos), new_size);
        // }

        pub fn rowPtr(grid: *const @This(), index: i32) [*]Element {
            assert(index >= 0 and index < grid.size[1],
                \\Attempt to get a grid row pointer with index out of bounds:
                \\Grid size: {}
                \\Row index: {}
            , .{ grid.size, index }); // Row index out of bounds

            return @ptrCast(&grid.elements[grid.parent_width * @as(u32, @intCast(index))]);
        }

        pub fn rowPtrOrNull(grid: *const @This(), index: i32) ?[*]Element {
            if (index < 0 or index >= grid.size[1]) return null;

            return grid.rowPtr(index);
        }

        pub fn row(grid: *const @This(), index: i32) []Element {
            assert(index >= 0 and index < grid.size[1],
                \\Attempt to get a grid row slice with index out of bounds:
                \\Grid size: {}
                \\Row index: {}
            , .{ grid.size, index }); // Row index out of bounds

            return grid.rowPtr(index)[0..grid.size[0]];
        }

        pub fn rowOrNull(grid: *const @This(), index: i32) ?[]Element {
            if (index < 0 or index >= grid.size[1]) return null;

            return grid.row(index);
        }

        pub fn inBounds(grid: *const @This(), pos: Vec2(i32)) bool {
            return (pos[0] >= 0) and (pos[1] >= 0) and (pos[0] < grid.size[0]) and (pos[1] < grid.size[1]);
        }

        pub fn at(grid: *const @This(), pos: Vec2(i32)) *Element {
            assert(grid.inBounds(pos),
                \\Attempt to access an element using `Grid(...).at(pos)` when `pos` is out of bounds
                \\Grid size: {}
                \\Element pos: {}
            , .{ grid.size, pos });

            return &grid.elements[@as(u32, @intCast(pos[1])) * grid.parent_width + @as(u32, @intCast(pos[0]))];
        }

        pub fn atOrNull(grid: *const @This(), pos: Vec2(i32)) ?*Element {
            if (!grid.inBounds(pos)) return null;

            return grid.at(pos);
        }

        pub fn isLinear(grid: *const @This()) bool {
            return grid.size[0] == grid.parent_width;
        }

        /// Set every grid element to `element`.
        pub fn fill(grid: *const @This(), element: Element) *const @This() {
            if (grid.isLinear()) {
                @memset(grid.elements, element);
            } else {
                for (0..grid.size[1]) |y| {
                    @memset(grid.row(@intCast(y)), element);
                }
            }

            return grid;
        }

        pub fn zero(grid: *const @This()) *const @This() {
            return grid.fill(std.mem.zeroes(Element));
        }

        // -- Drawing functions --

        /// Draw an element at `pos`.
        pub fn draw(grid: *const @This(), pos: Vec2(i32), element: Element) *const @This() {
            if (grid.atOrNull(pos)) |e| e.* = element;

            return grid;
        }

        /// Draw an element at `pos`. Asserts that `grid.inBounds(pos)`.
        pub fn drawUnsafe(grid: *const @This(), pos: Vec2(i32), element: Element) *const @This() {
            grid.at(pos).* = element;

            return grid;
        }

        /// Length can be negative.
        pub fn drawHLine(grid: *const @This(), origin: Vec2(i32), length: i32, element: Element) *const @This() {
            if (length == 0 or grid.isEmpty() or origin[1] < 0 or origin[1] >= grid.size[1]) return grid;

            const start_x: u32 = @intCast(std.math.clamp(@min(origin[0], origin[0] + length) + @intFromBool(length < 0), 0, @as(i32, @intCast(grid.size[0]))));
            const end_x: u32 = @intCast(std.math.clamp(@max(origin[0], origin[0] + length) + @intFromBool(length < 0), 0, @as(i32, @intCast(grid.size[0]))));

            @memset(grid.row(origin[1])[start_x..end_x], element);

            return grid;
        }

        /// Length can be negative.
        pub fn drawVLine(grid: *const @This(), origin: Vec2(i32), length: i32, element: Element) *const @This() {
            if (length == 0 or grid.isEmpty() or origin[0] < 0 or origin[0] >= grid.size[0]) return grid;

            const start_y: i32 = std.math.clamp(@min(origin[1], origin[1] + length) + @intFromBool(length < 0), 0, @as(i32, @intCast(grid.size[1])));
            const end_y: i32 = std.math.clamp(@max(origin[1], origin[1] + length) + @intFromBool(length < 0), 0, @as(i32, @intCast(grid.size[1])));

            var y: i32 = start_y;
            while (y < end_y) : (y += 1) {
                grid.at(.{ origin[0], y }).* = element;
            }

            return grid;
        }

        pub fn drawLine(grid: *const @This(), from: Vec2(i32), to: Vec2(i32), element: Element) *const @This() {
            var current_pos = from;

            const dx: i32 = @intCast(@abs(to[0] - from[0]));
            const dy: i32 = @intCast(@abs(to[1] - from[1]));

            const sx: i32 = if (from[0] < to[0]) 1 else -1;
            const sy: i32 = if (from[1] < to[1]) 1 else -1;

            var err = dx - dy;

            while (true) {
                _ = grid.draw(current_pos, element);

                if (current_pos[0] == to[0] and current_pos[1] == to[1]) break;

                const e2: i32 = 2 * err;

                if (e2 > -dy) {
                    err -= dy;
                    current_pos[0] += sx;
                }

                if (e2 < dx) {
                    err += dx;
                    current_pos[1] += sy;
                }
            }

            return grid;
        }

        pub fn drawRect(grid: *const @This(), pos: Vec2(i32), size: Vec2(i32), element: Element) *const @This() {
            if (grid.isEmpty()) return grid;

            _ = grid.drawHLine(pos, size[0] * @intFromBool(size[1] != 0), element);
            _ = grid.drawHLine(pos + math.Vec2i32{ 0, size[1] - math.sign(size[1]) }, size[0] * @intFromBool(size[1] != 0), element);
            _ = grid.drawVLine(pos, size[1] * @intFromBool(size[0] != 0), element);
            _ = grid.drawVLine(pos + math.Vec2i32{ size[0] - math.sign(size[0]), 0 }, size[1] * @intFromBool(size[0] != 0), element);

            return grid;
        }

        pub fn fillRect(grid: *const @This(), pos: Vec2(i32), size: Vec2(i32), element: Element) *const @This() {
            if (grid.isEmpty()) return grid;

            const start_i32: Vec2(i32) = @min(pos, pos + size);
            const end_i32: Vec2(i32) = @max(pos, pos + size);

            const start_u32: Vec2(u32) = @intCast(math.clamp(start_i32 + Vec2(i32){ @intFromBool(size[0] < 0), @intFromBool(size[1] < 0) }, Vec2(i32){ 0, 0 }, @as(Vec2(i32), @intCast(grid.size))));
            const end_u32: Vec2(u32) = @intCast(math.clamp(end_i32 + Vec2(i32){ @intFromBool(size[0] < 0), @intFromBool(size[1] < 0) }, Vec2(i32){ 0, 0 }, @as(Vec2(i32), @intCast(grid.size))));

            for (start_u32[1]..end_u32[1]) |y| {
                @memset(grid.rowPtr(@intCast(y))[start_u32[0]..end_u32[0]], element);
            }

            return grid;
        }

        pub fn borderEx(grid: *const @This(), upper_left_thickness: Vec2(u32), bottom_right_thickness: Vec2(u32), element: Element) *const @This() {
            _ = grid.fillRect(.{ 0, 0 }, Vec2(i32){ @intCast(grid.size[0]), @intCast(upper_left_thickness[1]) }, element);
            _ = grid.fillRect(.{ 0, 0 }, Vec2(i32){ @intCast(upper_left_thickness[0]), @intCast(grid.size[1]) }, element);
            _ = grid.fillRect(Vec2(i32){ 0, @as(i32, @intCast(grid.size[1] -| bottom_right_thickness[1])) }, Vec2(i32){ @intCast(grid.size[0]), @intCast(bottom_right_thickness[1]) }, element);
            _ = grid.fillRect(Vec2(i32){ @as(i32, @intCast(grid.size[0] -| bottom_right_thickness[0])), 0 }, Vec2(i32){ @intCast(bottom_right_thickness[0]), @intCast(grid.size[1]) }, element);

            return grid;
        }

        pub fn border(grid: *const @This(), thickness: u32, element: Element) *const @This() {
            _ = grid.fillRect(.{ 0, 0 }, Vec2(i32){ @intCast(grid.size[0]), @intCast(thickness) }, element);
            _ = grid.fillRect(.{ 0, 0 }, Vec2(i32){ @intCast(thickness), @intCast(grid.size[1]) }, element);
            _ = grid.fillRect(Vec2(i32){ 0, @as(i32, @intCast(grid.size[1] -| thickness)) }, Vec2(i32){ @intCast(grid.size[0]), @intCast(thickness) }, element);
            _ = grid.fillRect(Vec2(i32){ @as(i32, @intCast(grid.size[0] -| thickness)), 0 }, Vec2(i32){ @intCast(thickness), @intCast(grid.size[1]) }, element);

            return grid;
        }

        pub fn pad(grid: *const @This(), offset: u32) @This() {
            return grid.view(@splat(@intCast(offset)), grid.size -| @as(Vec2(u32), @splat(offset * 2)));
        }

        pub fn padEx(grid: *const @This(), upper_left_offset: Vec2(u32), bottom_right_offset: Vec2(u32)) @This() {
            return grid.view(@intCast(upper_left_offset), grid.size -| bottom_right_offset -| upper_left_offset);
        }

        pub usingnamespace if (Extension != null) Extension.?(@This()) else struct {};
    };
}

/// There are 5 ways to create a grid:
///
/// - The first one (and the simplest) is to construct the grid from existing elements array. **The grid will reference the data for its entire lifetime.** To do it, pass elements slice to the `Grid(...).fromElements(...)` function.
/// - The second one is to allocate all the element data in binary's static memory. `Grid(...).static(...)` function can help with that. Size of such grid must be known at compile time.
/// - The third one is to allocate all the element data dynamically, using an allocator. `Grid(...).alloc(...)` function is used in that case. Use `Grid.free(...)` to deinitialize a dynamically allocated grid.
/// - The fourth, and the most interesting one, is to create a grid that is a view into other grid. `Grid(...).view(...)` function can be used to create a view. **A view will reference original's grid data, so be careful with lifetimes.**
/// - The fifth is to create an empty grid, using `Grid(...).empty(...)` function. This will create a grid with both width and height set to zeroes. If grid's width or grid's height is zero, is is considered an empty grid.
pub fn Grid(comptime Element: type) type {
    return GridEx(Element, null);
}
