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

/// Generic error handler, mapping from c to zig error
pub fn handleError(err: anytype) !ValidReturnType(@TypeOf(err)) {
    const err_type = @TypeOf(err);
    const err_typeinfo = @typeInfo(err_type);
    switch (err_type) {
        // NOTE: flaw here, VkResult is just c_int, so this here is retarded
        inline c.VkResult => {
            if (err >= c.VK_SUCCESS) {
                return;
            } else {
                return error.CError;
            }
        },

        // For generic types (e.g. pointers, optionals)
        inline else => switch (err_typeinfo) {
            inline .optional => {
                if (err) |unwrapped| {
                    return unwrapped;
                } else {
                    return error.CError;
                }
            },

            inline .pointer => |ptr_info| {
                _ = ptr_info;
                if (err == null) {
                    return error.CError;
                }
                return err;
            },

            inline else => {
                comptime unreachable;
            },
        },
    }
}
