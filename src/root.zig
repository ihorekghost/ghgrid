const std = @import("std");
const Allocator = std.mem.Allocator;

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

pub fn Vec2(comptime Element: type) type {
    return @Vector(2, Element);
}

/// There are 5 ways to create a grid:
///
/// - The first one (and the simplest) is to construct the grid from existing elements array. **The grid will reference the data for its entire lifetime.** To do it, pass elements slice to the `Grid(...).fromElements(...)` function.
/// - The second one is to allocate all the element data in binary's static memory. `Grid(...).static(...)` function can help with that. Size of such grid must be known at compile time.
/// - The third one is to allocate all the element data dynamically, using an allocator. `Grid(...).alloc(...)` function is used in that case. Use `Grid.free(...)` to deinitialize a dynamically allocated grid.
/// - The fourth, and the most interesting one, is to create a grid that is a view into other grid. `Grid(...).view(...)` function can be used to create a view. **A view will reference original's grid data, so be careful with lifetimes.**
/// - The fifth is to create an empty grid, using `Grid(...).empty(...)` function. This will create a grid with both width and height set to zeroes. If grid's width or grid's height is zero, is is considered an empty grid.
pub fn GridEx(comptime Element: type, isAlpha: ?fn (element: Element) bool) type {
    return struct {
        elements: []Element,
        size: Vec2(u32),
        parent_width: u32,

        pub fn empty() @This() {
            return @This(){ .elements = &.{}, .size = .{ 0, 0 }, .parent_width = 0 };
        }

        pub fn fromElements(elements: []Element, size: Vec2(u32)) @This() {
            return @This(){ .elements = elements, .size = size, .parent_width = size[0] };
        }

        ///All the elements are initialized to `fill_with`.
        pub fn static(comptime size: Vec2(u32), comptime fill_with: Element) @This() {
            return @This(){
                .elements = &(struct {
                    pub var elements: [size[0] * size[1]]Element = [1]Element{fill_with} ** size[0] ** size[1];
                }.elements),
                .size = size,
                .parent_width = size[0],
            };
        }

        ///Dynamically allocate a grid. All the elements are initialized to `undefined`. Use `Grid.free(...)` to deinitialize a dynamically allocated grid.
        pub fn alloc(allocator: Allocator, size: Vec2(u32)) Allocator.Error!@This() {
            return @This(){
                .elements = try allocator.alloc(Element, size[0] * size[1]),
                .size = size,
                .parent_width = size[0],
            };
        }

        ///Free dynamically allocated grid's elements data.
        pub fn free(grid: *const @This(), allocator: Allocator) void {
            allocator.free(grid.elements);
        }

        ///Get a view into `grid`. The view is a grid that references part of element data of `grid` selected by `pos` and `size`.
        pub fn view(grid: *const @This(), pos: Vec2(i32), size: Vec2(u32)) @This() {
            if (size[0] == 0 or size[1] == 0) return empty();

            assert(grid.inBounds(pos),
                \\Attempt to create a view that is out of bounds:
                \\Original size: {}
                \\View metrics: {}, {}
            , .{ grid.size, pos, size });
            assert(grid.inBounds(pos + @as(Vec2(i32), @intCast(size - @as(Vec2(u32), @splat(1))))),
                \\Attempt to create a view that is out of bounds:
                \\Original size: {}
                \\View metrics: {}, {}
            , .{ grid.size, pos, size });

            return @This(){
                .elements = @as([*]Element, @ptrCast(grid.at(pos)))[0 .. size[1] * grid.parent_width],
                .size = size,
                .parent_width = grid.parent_width,
            };
        }

        pub fn viewOrEmpty(grid: *const @This(), pos: Vec2(i32), size: Vec2(u32)) @This() {
            if (size[0] == 0 or size[1] == 0) return empty();

            if (!grid.inBounds(pos) or !(grid.inBounds(pos + (size - @as(Vec2(u32), @splat(1)))))) return empty();

            return grid.view(pos, size);
        }

        pub fn isEmpty(grid: @This()) bool {
            return grid.size[0] == 0 or grid.size[1] == 0;
        }

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
        pub fn drawHLineUnsafe(grid: *const @This(), origin: Vec2(i32), length: i32, element: Element) *const @This() {
            assert(grid.inBounds(origin),
                \\`drawHLineUnsafe(...)` failed: Origin is out of bounds
                \\Grid size: {}
                \\Origin: {}
            , .{ grid.size, origin });

            assert((origin[0] + length) >= 0 and (origin[0] + length) <= grid.size[0],
                \\`drawHLineUnsafe(...)` failed: Line end is out of bounds
                \\Grid size: {}
                \\Origin: {}
                \\Length: {}
                \\Line end: {}
            , .{ grid.size, origin, length, (origin[0] + length) });

            const start_x: u32 = @intCast(@min(origin[0], origin[0] + length));
            const end_x: u32 = @intCast(@max(origin[0], origin[0] + length));

            @memset(grid.row(origin[1])[start_x..end_x], element);

            return grid;
        }

        /// Length can be negative.
        pub fn drawHLine(grid: *const @This(), origin: Vec2(i32), length: i32, element: Element) *const @This() {
            if (length == 0 or grid.isEmpty() or origin[1] < 0 or origin[1] >= grid.size[1]) return grid;

            const start_x: u32 = @intCast(std.math.clamp(@min(origin[0], origin[0] + length), 0, @as(i32, @intCast(grid.size[0]))));
            const end_x: u32 = @intCast(std.math.clamp(@max(origin[0], origin[0] + length), 0, @as(i32, @intCast(grid.size[0]))));

            @memset(grid.row(origin[1])[start_x..end_x], element);

            return grid;
        }

        pub fn drawVLineUnsafe(grid: *const @This(), origin: Vec2(i32), length: i32, element: Element) *const @This() {
            if (grid.isEmpty()) return grid;

            const start_y: i32 = @min(origin[1], origin[1] + length);
            const end_y: i32 = @max(origin[1], origin[1] + length);

            assert(grid.inBounds(origin),
                \\`drawVLineUnsafe(...)` failed: Origin is out of bounds
                \\Grid size: {}
                \\Origin: {}
            , .{ grid.size, origin });

            assert((origin[1] + length) >= 0 and (origin[1] + length) <= grid.size[1],
                \\`drawVLineUnsafe(...)` failed: Line end is out of bounds
                \\Grid size: {}
                \\Line end: {}
            , .{ grid.size, (origin[1] + length) });

            var y: i32 = start_y;
            while (y < end_y) : (y += 1) {
                grid.at(.{ origin[0], y }).* = element;
            }

            return grid;
        }
        pub fn drawVLine(grid: *const @This(), origin: Vec2(i32), length: i32, element: Element) *const @This() {
            if (length == 0 or grid.isEmpty() or origin[0] < 0 or origin[0] >= grid.size[0]) return grid;

            const start_y: i32 = std.math.clamp(@min(origin[1], origin[1] + length), 0, @as(i32, @intCast(grid.size[1])));
            const end_y: i32 = std.math.clamp(@max(origin[1], origin[1] + length), 0, @as(i32, @intCast(grid.size[1])));

            var y: i32 = start_y;
            while (y < end_y) : (y += 1) {
                grid.at(.{ origin[0], y }).* = element;
            }

            return grid;
        }

        pub fn drawLineUnsafe(grid: *const @This(), from: Vec2(i32), to: Vec2(i32), element: Element) *const @This() {
            var current_pos = from;

            const dx: i32 = @intCast(@abs(to[0] - from[0]));
            const dy: i32 = @intCast(@abs(to[1] - from[1]));

            const sx: i32 = if (from[0] < to[0]) 1 else -1;
            const sy: i32 = if (from[1] < to[1]) 1 else -1;

            var err = dx - dy;

            while (true) {
                grid.at(current_pos).* = element;

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

        pub fn drawCircleUnsafe(grid: *const @This(), center: Vec2(i32), radius: u32, element: Element) *const @This() {
            var x: i32 = 0;
            var y: i32 = @intCast(radius);
            var d: i32 = 3 - 2 * @as(i32, @intCast(radius));

            _ = grid.drawUnsafe(.{ center[0] + x, center[1] + y }, element);
            _ = grid.drawUnsafe(.{ center[0] - x, center[1] + y }, element);
            _ = grid.drawUnsafe(.{ center[0] + x, center[1] - y }, element);
            _ = grid.drawUnsafe(.{ center[0] - x, center[1] - y }, element);
            _ = grid.drawUnsafe(.{ center[0] + y, center[1] + x }, element);
            _ = grid.drawUnsafe(.{ center[0] - y, center[1] + x }, element);
            _ = grid.drawUnsafe(.{ center[0] + y, center[1] - x }, element);
            _ = grid.drawUnsafe(.{ center[0] - y, center[1] - x }, element);

            while (y >= x) {
                x += 1;

                if (d > 0) {
                    y -= 1;
                    d = d + 4 * (x - y) + 10;
                } else {
                    d = d + 4 * x + 6;
                }

                _ = grid.drawUnsafe(.{ center[0] + x, center[1] + y }, element);
                _ = grid.drawUnsafe(.{ center[0] - x, center[1] + y }, element);
                _ = grid.drawUnsafe(.{ center[0] + x, center[1] - y }, element);
                _ = grid.drawUnsafe(.{ center[0] - x, center[1] - y }, element);
                _ = grid.drawUnsafe(.{ center[0] + y, center[1] + x }, element);
                _ = grid.drawUnsafe(.{ center[0] - y, center[1] + x }, element);
                _ = grid.drawUnsafe(.{ center[0] + y, center[1] - x }, element);
                _ = grid.drawUnsafe(.{ center[0] - y, center[1] - x }, element);
            }

            return grid;
        }

        pub fn drawCircle(grid: *const @This(), center: Vec2(i32), radius: u32, element: Element) *const @This() {
            var x: i32 = 0;
            var y: i32 = @intCast(radius);
            var d: i32 = 3 - 2 * @as(i32, @intCast(radius));

            _ = grid.draw(.{ center[0] + x, center[1] + y }, element);
            _ = grid.draw(.{ center[0] - x, center[1] + y }, element);
            _ = grid.draw(.{ center[0] + x, center[1] - y }, element);
            _ = grid.draw(.{ center[0] - x, center[1] - y }, element);
            _ = grid.draw(.{ center[0] + y, center[1] + x }, element);
            _ = grid.draw(.{ center[0] - y, center[1] + x }, element);
            _ = grid.draw(.{ center[0] + y, center[1] - x }, element);
            _ = grid.draw(.{ center[0] - y, center[1] - x }, element);

            while (y >= x) {
                x += 1;

                if (d > 0) {
                    y -= 1;
                    d = d + 4 * (x - y) + 10;
                } else {
                    d = d + 4 * x + 6;
                }

                _ = grid.draw(.{ center[0] + x, center[1] + y }, element);
                _ = grid.draw(.{ center[0] - x, center[1] + y }, element);
                _ = grid.draw(.{ center[0] + x, center[1] - y }, element);
                _ = grid.draw(.{ center[0] - x, center[1] - y }, element);
                _ = grid.draw(.{ center[0] + y, center[1] + x }, element);
                _ = grid.draw(.{ center[0] - y, center[1] + x }, element);
                _ = grid.draw(.{ center[0] + y, center[1] - x }, element);
                _ = grid.draw(.{ center[0] - y, center[1] - x }, element);
            }

            return grid;
        }

        fn distanceSquared(from: Vec2(f32), to: Vec2(f32)) f32 {
            const pos_difference = Vec2(f32){ to[0] - from[0], to[1] - from[1] };

            return pos_difference[0] * pos_difference[0] + pos_difference[1] * pos_difference[1];
        }

        fn distance(from: Vec2(i32), to: Vec2(i32)) f32 {
            return @sqrt(distanceSquared(from, to));
        }

        pub fn fillCircleUnsafe(grid: *const @This(), center: Vec2(i32), radius: f32, element: Element) void {
            const bounds_rect_top_left: Vec2(i32) = @intFromFloat(@as(Vec2(f32), @floatFromInt(center)) - Vec2(f32){ radius, radius });
            const bounds_rect_bottom_right: Vec2(i32) = @intFromFloat(@as(Vec2(f32), @floatFromInt(center)) + Vec2(f32){ radius, radius });

            assert(grid.inBounds(bounds_rect_top_left),
                \\`fillCircleUnsafe(...)` failed: Circle's bounding box is out of grid's bounds - top left corner
                \\Grid size: {}
                \\Circle center: {}
                \\Circle radius: {d}
                \\Top left corner: {}
            , .{ grid.size, center, radius, bounds_rect_top_left });

            assert(grid.inBounds(bounds_rect_bottom_right),
                \\`fillCircleUnsafe(...)` failed: Circle's bounding box is out of grid's bounds - bottom right corner
                \\Grid size: {}
                \\Circle center: {}
                \\Circle radius: {d}
                \\Bottom right corner: {}
            , .{ grid.size, center, radius, bounds_rect_bottom_right });

            for (@as(usize, @intCast(bounds_rect_top_left[1]))..@as(usize, @intCast(bounds_rect_bottom_right[1]))) |y| {
                for (@as(usize, @intCast(bounds_rect_top_left[0]))..@as(usize, @intCast(bounds_rect_bottom_right[0]))) |x| {
                    if (distanceSquared(@as(Vec2(f32), @floatFromInt(Vec2(usize){ x, y })) + Vec2(f32){ 0.5, 0.5 }, @floatFromInt(center)) <= (radius * radius)) {
                        _ = grid.drawUnsafe(@intCast(Vec2(usize){ x, y }), element);
                    }
                }
            }
        }

        //pub fn fillCircle(grid: *const @This(), center: Vec2(i32), radius: u32, element: Element) void {}

        // pub fn drawRectUnsafe(grid: *const @This()) void {}
        // pub fn drawRect(grid: *const @This()) void {}
        // pub fn fillRectUnsafe(grid: *const @This()) void {}
        // pub fn fillRect(grid: *const @This()) void {}

        pub usingnamespace if (isAlpha) |isAlpha_| struct {
            comptime {
                _ = isAlpha_;
            }
        } else struct {};
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
