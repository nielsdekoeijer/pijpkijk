const c = @import("c.zig").c;

/// Return type helper to determine the return type of the handleError function
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
        inline c_int => {
            if (err >= 0) {
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
