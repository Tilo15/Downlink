project('Downlink', 'vala', 'c')
vapi_dir = meson.current_source_dir() / 'vapi'

add_project_arguments(['--disable-warnings', '--enable-checking','--vapidir', vapi_dir], language: 'vala')


subdir('lib')

dependencies += downlink_dep

subdir('tools')

dependencies += dependency('fuse')
subdir('fuse')
