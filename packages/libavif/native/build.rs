use std::collections::hash_map::DefaultHasher;
use std::env;
use std::fs;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};

fn main() {
    let manifest_dir =
        PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let source_dir = manifest_dir.join("vendor/libavif");
    let target = env::var("TARGET").expect("TARGET");
    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR"));
    let cmake_out_dir = if target.contains("windows") {
        let mut key = DefaultHasher::new();
        out_dir.hash(&mut key);
        env::temp_dir()
            .join("libavif-cmake")
            .join(format!("{:016x}", key.finish()))
    } else {
        out_dir.clone()
    };

    let mut config = cmake::Config::new(&source_dir);
    config.out_dir(&cmake_out_dir);
    config
        .define("BUILD_SHARED_LIBS", "OFF")
        .define("AVIF_ENABLE_WERROR", "OFF")
        .define("AVIF_BUILD_APPS", "OFF")
        .define("AVIF_BUILD_TESTS", "OFF")
        .define("AVIF_GTEST", "OFF")
        .define("AVIF_CODEC_AOM", "OFF")
        .define("AVIF_CODEC_AOM_DECODE", "OFF")
        .define("AVIF_CODEC_AOM_ENCODE", "OFF")
        .define("AVIF_CODEC_DAV1D", "LOCAL")
        .define("AVIF_CODEC_LIBGAV1", "OFF")
        .define("AVIF_CODEC_RAV1E", "OFF")
        .define("AVIF_CODEC_SVT", "OFF")
        .define("AVIF_CODEC_AVM", "OFF")
        .define("AVIF_LIBYUV", "LOCAL")
        .define("AVIF_LIBSHARPYUV", "OFF")
        .define("AVIF_ZLIBPNG", "OFF")
        .define("AVIF_JPEG", "OFF")
        .define("CMAKE_INSTALL_LIBDIR", "lib")
        .define("FETCHCONTENT_FULLY_DISCONNECTED", "ON")
        .profile(if env::var("PROFILE").expect("PROFILE") == "release" {
            "Release"
        } else {
            "Debug"
        });

    if target.ends_with("apple-darwin") {
        config.define("CMAKE_OSX_DEPLOYMENT_TARGET", "11.0");
    }
    if target.contains("apple-ios") {
        config.define("CMAKE_OSX_DEPLOYMENT_TARGET", "13.0");
    }
    if target.contains("android") {
        let android_abi = env::var("LAVIF_ANDROID_ABI")
            .expect("LAVIF_ANDROID_ABI must be set for Android builds");
        let android_api = env::var("LAVIF_ANDROID_NDK_API")
            .expect("LAVIF_ANDROID_NDK_API must be set for Android builds");
        config
            .define("ANDROID_ABI", android_abi)
            .define("ANDROID_PLATFORM", format!("android-{android_api}"));
    }

    let installed = config.build();
    let dav1d_archive = find_library_recursive(&cmake_out_dir, "libdav1d.a")
        .unwrap_or_else(|| {
            panic!(
                "The local dav1d build did not produce {} under {}",
                "libdav1d.a",
                cmake_out_dir.display()
            )
        });
    let dav1d_library = if target.contains("msvc") {
        let normalized = installed.join("lib/dav1d.lib");
        fs::copy(&dav1d_archive, &normalized)
            .expect("Could not prepare the dav1d archive for MSVC linking");
        normalized
    } else {
        dav1d_archive.clone()
    };
    let libyuv_library = find_library_recursive(&cmake_out_dir, libyuv_library_name(&target))
        .unwrap_or_else(|| {
            panic!(
                "The local libyuv build did not produce {} under {}",
                libyuv_library_name(&target),
                cmake_out_dir.display()
            )
        });

    let mut bridge = cc::Build::new();
    bridge
        .file("src/bridge.c")
        .include(source_dir.join("include"))
        .include(source_dir.join("ext/libyuv/include"))
        .warnings(true);
    if target.ends_with("apple-darwin") {
        bridge.flag("-mmacosx-version-min=11.0");
    }
    bridge.compile("libavif_bridge");

    println!(
        "cargo:rustc-link-search=native={}",
        installed.join("lib").display()
    );
    println!("cargo:rustc-link-lib=static=avif");
    println!(
        "cargo:rustc-link-search=native={}",
        libyuv_library
            .parent()
            .expect("libyuv library parent")
            .display()
    );
    println!("cargo:rustc-link-lib=static=yuv");
    println!(
        "cargo:rustc-link-search=native={}",
        dav1d_library.parent().expect("dav1d library parent").display()
    );
    println!("cargo:rustc-link-lib=static=dav1d");
    if target.contains("msvc") {
        for archive in [installed.join("lib/avif.lib"), libyuv_library, dav1d_archive] {
            println!("cargo:rerun-if-changed={}", archive.display());
        }
    }
    println!("cargo:rerun-if-changed=src/bridge.c");
    println!("cargo:rerun-if-changed=src/bridge.h");
    println!("cargo:rerun-if-changed=vendor/libavif");
}

fn libyuv_library_name(target: &str) -> &'static str {
    if target.contains("msvc") {
        "yuv.lib"
    } else {
        "libyuv.a"
    }
}

fn find_library_recursive(directory: &Path, name: &str) -> Option<PathBuf> {
    let entries = fs::read_dir(directory).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() && path.file_name().is_some_and(|file_name| file_name == name) {
            return Some(path);
        }
        if path.is_dir() {
            if let Some(found) = find_library_recursive(&path, name) {
                return Some(found);
            }
        }
    }
    None
}
