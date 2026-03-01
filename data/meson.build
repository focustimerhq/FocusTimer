# D-Bus
dbus_conf = configuration_data()
dbus_conf.set('BINDIR', get_option('prefix') / get_option('bindir'))
dbus_conf.set('APPLICATION_ID', application_id)

configure_file(
  input: 'io.github.focustimerhq.FocusTimer.service.in',
  output: '@0@.service'.format(application_id),
  configuration: dbus_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1/services',
)

install_data(
  'io.github.focustimerhq.FocusTimer.xml',
  'io.github.focustimerhq.FocusTimer.Session.xml',
  'io.github.focustimerhq.FocusTimer.Timer.xml',
  install_dir: get_option('datadir') / 'dbus-1/interfaces',
)

# Desktop file
desktop_conf = configuration_data()
desktop_conf.set('APPLICATION_ID', application_id)
desktop_conf.set('APPLICATION_NAME', application_name)

desktop_file = i18n.merge_file(
  input: configure_file(
    input: 'io.github.focustimerhq.FocusTimer.desktop.in.in',
    output: '@0@.desktop.in'.format(application_id),
    configuration: desktop_conf
  ),
  output: '@0@.desktop'.format(application_id),
  type: 'desktop',
  po_dir: '../po',
  install: true,
  install_dir: get_option('datadir') / 'applications'
)

desktop_file_validate = find_program('desktop-file-validate', required:false)
if desktop_file_validate.found()
  test (
    'Validate .desktop',
    desktop_file_validate,
    args: [desktop_file.full_path()],
    depends: [desktop_file],
  )
endif

# Appdata
appdata = i18n.merge_file(
  input: 'io.github.focustimerhq.FocusTimer.metainfo.xml.in',
  output: '@BASENAME@',
  install: true,
  install_dir: get_option('datadir') / 'metainfo',
  po_dir: '../po',
)

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test(
    'Validate .metainfo.xml',
    appstreamcli,
    args: [
      'validate', '--no-net', '--explain', appdata.full_path()
    ],
    depends: [appdata],
  )
endif

# GSchema
install_data(
  'io.github.focustimerhq.FocusTimer.gschema.xml',
  install_dir: gschema_dir,
)

compile_schemas = find_program('glib-compile-schemas', required: false)
if compile_schemas.found()
  test('Validate schema file', compile_schemas,
    args: ['--strict', '--dry-run', meson.current_source_dir()]
  )
endif

compiled_schemas = gnome.compile_schemas(
  depend_files: 'io.github.focustimerhq.FocusTimer.gschema.xml'
)

# Run required post-install steps
gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)

# Assets
subdir('icons')
subdir('sounds')
