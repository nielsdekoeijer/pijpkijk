const std = @import("std");

fn addSlangCompileVertShaderStep(b: *std.Build, src: []const u8, out: []const u8) *std.Build.Step.Run {
    const slangc = b.addSystemCommand(&.{
        "slangc",
        src,
        "-target",
        "spirv",
        "-profile",
        "glsl_450",
        "-capability",
        "glsl_spirv_1_0",
        "-entry",
        "main",
        "-stage",
        "vertex",
        "-o",
        out,
    });
    return slangc;
}
fn addSlangCompileFragShaderStep(b: *std.Build, src: []const u8, out: []const u8) *std.Build.Step.Run {
    const slangc = b.addSystemCommand(&.{
        "slangc",
        src,
        "-target",
        "spirv",
        "-profile",
        "glsl_450",
        "-capability",
        "glsl_spirv_1_0",
        "-entry",
        "main",
        "-stage",
        "fragment",
        "-o",
        out,
    });
    return slangc;
}

fn addMsdfAtlasGenStep(b: *std.Build, font_src: []const u8, out_png: []const u8, out_json: []const u8) *std.Build.Step.Run {
    const msdf = b.addSystemCommand(&.{
        "msdf-atlas-gen",
        "-font",
        font_src,
        "-type",
        "mtsdf",
        "-format",
        "png",
        "-imageout",
        out_png,
        "-json",
        out_json,
        "-size",
        "32",
        "-pxrange",
        "4",
    });
    return msdf;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const slang_step = b.step("compile-shaders", "Compile shaders");

    const vert_shaders = .{
        .{
            .slang_path = "src/shaders/quad.vert.slang",
            .spirv_path = "src/shaders/quad.vert.spirv",
        },
        .{
            .slang_path = "src/shaders/bezier.vert.slang",
            .spirv_path = "src/shaders/bezier.vert.spirv",
        },
        .{
            .slang_path = "src/shaders/text.vert.slang",
            .spirv_path = "src/shaders/text.vert.spirv",
        },
    };

    inline for (vert_shaders) |shader| {
        slang_step.dependOn(&addSlangCompileVertShaderStep(
            b,
            shader.slang_path,
            shader.spirv_path,
        ).step);
    }

    const frag_shaders = .{
        .{
            .slang_path = "src/shaders/quad.frag.slang",
            .spirv_path = "src/shaders/quad.frag.spirv",
        },
        .{
            .slang_path = "src/shaders/bezier.frag.slang",
            .spirv_path = "src/shaders/bezier.frag.spirv",
        },
        .{
            .slang_path = "src/shaders/text.frag.slang",
            .spirv_path = "src/shaders/text.frag.spirv",
        },
    };

    inline for (frag_shaders) |shader| {
        slang_step.dependOn(&addSlangCompileFragShaderStep(
            b,
            shader.slang_path,
            shader.spirv_path,
        ).step);
    }

    b.getInstallStep().dependOn(slang_step);

    const msdf_step = b.step("compile-fonts", "Compile fonts to MSDF atlases");

    const fonts = .{
        .{
            .src_path = "src/fonts/RobotoMono-Regular.ttf",
            .png_path = "src/fonts/RobotoMono-Regular.png",
            .json_path = "src/fonts/RobotoMono-Regular.json",
        },
    };

    inline for (fonts) |font| {
        msdf_step.dependOn(&addMsdfAtlasGenStep(
            b,
            font.src_path,
            font.png_path,
            font.json_path,
        ).step);
    }

    b.getInstallStep().dependOn(msdf_step);

    const mod = b.addModule("pijpkijk", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
    });
    mod.linkSystemLibrary("sdl3", .{
        .needed = true,
        .preferred_link_mode = .dynamic,
        .use_pkg_config = .yes,
    });
    mod.linkSystemLibrary("SDL3_image", .{
        .needed = true,
        .preferred_link_mode = .dynamic,
        .use_pkg_config = .yes,
    });
    mod.linkSystemLibrary("vulkan", .{
        .needed = true,
        .preferred_link_mode = .dynamic,
        .use_pkg_config = .yes,
    });
    mod.linkSystemLibrary("pipewire-0.3", .{
        .needed = true,
        .preferred_link_mode = .dynamic,
        .use_pkg_config = .yes,
    });
    mod.addIncludePath(
        b.path("./src/"),
    );

    const exe = b.addExecutable(.{
        .name = "pijpkijk",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pijpkijk", .module = mod },
            },
        }),
    });

    exe.step.dependOn(slang_step);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
