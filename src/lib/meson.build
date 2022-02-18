add_project_arguments('-DFUSE_USE_VERSION=26', language: 'c')

dependencies = [
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gio-2.0'),
    dependency('gee-0.8'),
    dependency('libpeer'),
    dependency('json-glib-1.0'),
    meson.get_compiler('vala').find_library('posix'),
    meson.get_compiler('vala').find_library('uuid', dirs: vapi_dir),
    meson.get_compiler('c').find_library('uuid'),
    meson.get_compiler('vala').find_library('libsodium', dirs: vapi_dir),
    meson.get_compiler('c').find_library('sodium'),
    meson.get_compiler('c').find_library('m')
]

sources = files('Controller/Controller.vala')
sources += files('Controller/PeerGroup.vala')
sources += files('Metadata/AuthTable.vala')
sources += files('Metadata/MemoryAuthTable.vala')
sources += files('Metadata/FilesystemAuthTable.vala')
sources += files('Metadata/File.vala')
sources += files('Metadata/Folder.vala')
sources += files('Metadata/Metadata.vala')
sources += files('Metadata/ResourceIdentifier.vala')
sources += files('Protocol/Instance.vala')
sources += files('Protocol/Peer.vala')
sources += files('Protocol/CommandStatus.vala')
sources += files('Publishing/PublisherKey.vala')
sources += files('Publishing/PublishingKey.vala')
sources += files('Store/Store.vala')
sources += files('Store/FilesystemStore.vala')
sources += files('Store/MemoryStore.vala')
sources += files('Util/Binary.vala')
sources += files('Util/Encoding.vala')
sources += files('Util/Hashing.vala')

downlink = shared_library('libdownlink', sources,
    name_prefix: '',
    dependencies: dependencies,
    install: true,
    vala_gir: 'Downlink-1.0.gir',
    install_dir: [true, true, true, true]
)
downlink_dep = declare_dependency(link_with: downlink, include_directories: include_directories('.'))

pkg = import('pkgconfig')
pkg.generate(downlink,
    version : '0.1',
    name : 'libdownlink',)
    
g_ir_compiler = find_program('g-ir-compiler')
custom_target('downlink typelib', command: [g_ir_compiler, '--shared-library=libdownlink.so', '--output', '@OUTPUT@', meson.current_build_dir() / 'Downlink-1.0.gir'],
              output: 'Downlink-1.0.typelib',
              depends: downlink,
              install: true,
              install_dir: get_option('libdir') / 'girepository-1.0')