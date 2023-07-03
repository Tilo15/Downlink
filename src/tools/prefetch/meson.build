

sources = files('prefetch.vala')

dependencies += meson.get_compiler('vala').find_library('linux')

executable('downlink-prefetch', sources, dependencies: dependencies)
