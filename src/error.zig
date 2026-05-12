/// Return type helper
fn ValidReturnType(comptime ErrorType: type) type {
    switch (@typeInfo(ErrorType)) {
        inline .bool => return void,
        inline .optional => return ErrorType,
        inline else => return ErrorType,
    }
}

/// SDL error Helper
pub fn handleSDLError(err: anytype) !ValidReturnType(@TypeOf(err)) {
    switch (@TypeOf(err)) {
        inline bool => if (err == false) return error.SDLError,
        inline else => switch (@typeInfo(@TypeOf(err))) {
            inline .optional => return (err orelse return error.SDLError),
            inline else => unreachable,
        },
    }
}
