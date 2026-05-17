const c = @import("c.zig").c;

/// Return type helper
fn ValidReturnType(comptime ErrorType: type) type {
    const info = @typeInfo(ErrorType);
    switch (ErrorType) {
        c.VkResult => return void,
        inline else => switch (info) {
            inline .bool => return void,
            inline .optional => return info.optional.child,
            inline else => return ErrorType,
        },
    }
}

/// SDL error Helper. Maps booleans, nullptrs, etc. to Zig error types
pub fn handleError(err: anytype) !ValidReturnType(@TypeOf(err)) {
    switch (@TypeOf(err)) {
        inline bool => if (err == false) return error.CError,
        inline c.VkResult => {
            if (err >= c.VK_SUCCESS) {
                return;
            } else {
                return error.CError;
            }
        },
        inline else => switch (@typeInfo(@TypeOf(err))) {
            inline .optional => {
                if (err) |unwrapped| {
                    return unwrapped;
                } else {
                    return error.CError;
                }
            },
            inline else => unreachable,
        },
    }
}
