const std: type = @import("std");

pub fn Matrix(comptime width: usize, comptime height: usize) type {
    if (width < 2 or height < 2 or width > 4 or height > 4) @panic("Only matrices 2x2..4x4 are allowed");

    return struct {
        data: @Vector(width * height, f32) align(16),

        pub const init: @This() = .{
            .data = std.mem.zeroes(@Vector(width * height, f32))
        };

        pub fn clone(self: @This()) @This() {
            return self;
        }

        const Axis: type = enum { x, y, z };

        // ---------------- Column-major multiplication ----------------
        pub fn multiply(self: @This(), operand: @This()) @This() {
            const N = width; // square matrix
            var result: Matrix(width, width) = .init;

            // Column-major multiplication: result[col,row] = sum_k self[k,row]*operand[col,k]
            for (0..N) |col| {
                for (0..N) |row| {
                    var sum: f32 = 0.0;
                    for (0..N) |k| {
                        sum += self.data[row + k*N] * operand.data[k + col*N];
                    }
                    result.data[row + col*N] = sum;
                }
            }
            return result;
        }

        // ---------------- Column-major translation ----------------
        pub fn translate(self: @This(), position: @Vector(3,f32)) @This() {
            var result = self;
            // last column indices: col 3
            result.data[0 + 3*4] += position[0]; // X
            result.data[1 + 3*4] += position[1]; // Y
            result.data[2 + 3*4] += position[2]; // Z
            return result;
        }

        // ---------------- Column-major rotation ----------------
        pub fn rotate(self: @This(), angle: f32, axis: Axis) @This() {
            if (width != height) @panic("Only square matrices supported");

            var result = self.clone();
            const c = @cos(std.math.degreesToRadians(angle));
            const s = @sin(std.math.degreesToRadians(angle));

            var R: [16]f32 = undefined;
            // Start identity
            for (0..4) |i| {
                for (0..4) |j| R[i + j*4] = if (i == j) 1 else 0;
            }

            switch (axis) {
                .x => { R[1 + 1*4] = c; R[2 + 1*4] = -s; R[1 + 2*4] = s; R[2 + 2*4] = c; },
                .y => { R[0 + 0*4] = c; R[2 + 0*4] = s; R[0 + 2*4] = -s; R[2 + 2*4] = c; },
                .z => { R[0 + 0*4] = c; R[1 + 0*4] = s; R[0 + 1*4] = -s; R[1 + 1*4] = c; }
            }

            result = result.multiply(.{ .data = R });
            return result;
        }

        pub fn format(self: @This(), writer: *std.io.Writer) !void {
            for (0..height) |row| {
                try writer.print("{s}",.{if (row==0) "⎡" else if (row==height-1) "⎣" else "⎢"});
                for (0..width) |col| {
                    const e = self.data[row + col*width]; // column-major access
                    try writer.print(" {d}",.{e});
                }
                try writer.print("{s}",.{if (row==0) "⎤\n" else if (row==height-1) "⎦\n" else "⎢\n"});
            }
        }
    };
}

// ---------------- Column-major Scale ----------------
pub fn ScaleMatrix(factor: f32) Matrix(4,4) {
    var matrix: Matrix(4,4) = .init;
    for (0..4) |i| matrix.data[i + i*4] = factor;
    return matrix;
}

// ---------------- Column-major View Matrix ----------------
pub fn ViewMatrix(eye: @Vector(3,f32), target: @Vector(3,f32), up: @Vector(3,f32)) Matrix(4,4) {
    var matrix: Matrix(4,4) = .init;

    const f = normalize(3,f32,target - eye);
    const r = normalize(3,f32,cross(3,f32,f,up));
    const u = cross(3,f32,r,f);

    // column-major
    matrix.data = .{
        r[0], u[0], -f[0], 0,
        r[1], u[1], -f[1], 0,
        r[2], u[2], -f[2], 0,
        -dot(3,f32,r,eye), -dot(3,f32,u,eye), dot(3,f32,f,eye), 1
    };

    return matrix;
}

// ---------------- Column-major Projection Matrix ----------------
pub fn ProjectionMatrix(fov: f32, aspectRatio: f32, near: f32, far: f32) Matrix(4,4) {
    var matrix: Matrix(4,4) = .init;
    const f: f32 = 1 / @tan(std.math.degreesToRadians(fov)*0.5);

    matrix.data = .{
        f / aspectRatio, 0, 0, 0,
        0, f, 0, 0,
        0, 0, (far+near)/(near-far), -1,
        0, 0, (2*far*near)/(near-far), 0
    };
    return matrix;
}

// ---------------- Vector helpers ----------------
pub fn dot(comptime N: usize, T: type, vector1: @Vector(N,T), vector2: @Vector(N,T)) T {
    var sum: T = 0;
    for (0..N) |i| sum += vector1[i]*vector2[i];
    return sum;
}

pub fn normalize(comptime N: usize, T: type, v: @Vector(N,T)) @Vector(N,T) {
    var length_sq: T = 0;
    for (0..N) |i| length_sq += v[i]*v[i];
    const length = @sqrt(length_sq);
    if (length==0) return v;
    var result: @Vector(N,T) = v;
    for (0..N) |i| result[i] = v[i]/length;
    return result;
}

pub fn cross(comptime N: usize, T: type, a: @Vector(N,T), b: @Vector(N,T)) @Vector(N,T) {
    return .{
        a[1]*b[2]-a[2]*b[1],
        a[2]*b[0]-a[0]*b[2],
        a[0]*b[1]-a[1]*b[0],
    };
}
