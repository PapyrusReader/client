# Vendored unrar_file 1.1.0

Source: https://pub.dev/packages/unrar_file/versions/1.1.0
Upstream: https://github.com/syedecryptr/unrar_file
License: Apache-2.0, retained in LICENSE.

The upstream Android plugin predates AGP namespaces and imports the removed
Flutter v1 Registrar API. The release build failed on both. This copy retains
the Dart decoder, channel implementation and iOS implementation unchanged, except
for removing that unused Java import. The Android module declares its namespace,
removes the obsolete manifest package attribute, uses the host's Gradle plugin
and repositories, and compiles against API 36/Java 11/minimum API 24. The Dart SDK
range allows the existing null-safe code on the pinned Dart 3 toolchain.

No archive parsing or extraction behavior is changed. This is a reviewed,
repository-owned compatibility patch, not a mutation of a developer's pub cache.
Replace with an upstream compatible release when available.

The host app supplies an SLF4J 1.7 NOP binding for Junrar, so R8 resolves its
optional StaticLoggerBinder without disabling shrinking or hiding missing classes.
