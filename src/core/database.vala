/*
 * Copyright (c) 2022-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Ft.Database
{
    private const uint VERSION = 4;
    private const string MIGRATIONS_URI = "resource:///io/github/focustimerhq/FocusTimer/migrations";
    private const string DATE_FORMAT = "%Y-%m-%d";

    private Gom.Adapter? adapter = null;
    private Gom.Repository? repository = null;

    public unowned Gom.Repository? get_repository ()
    {
        return Ft.Database.repository;
    }

    private void make_directory_with_parents (GLib.File directory)
    {
        if (!directory.query_exists ())
        {
            try {
                directory.make_directory_with_parents ();
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to create directory: %s", error.message);
            }
        }
    }

    /**
     * Convenience function to execute multiline SQL.
     *
     * `Gom.Adapter.execute_sql` is limited to single line queries.
     *
     * This MUST be called from within a write transaction using
     * Gom.Adapter.queue_write().
     */
    private void execute_sql (Gom.Adapter adapter,
                              string      sql)
                              throws GLib.Error
    {
        unowned var database = adapter.get_handle ();
        string error_message;

        if (database.exec (sql, null, out error_message) != Sqlite.OK) {
            throw new Gom.Error.COMMAND_SQLITE (error_message);
        }
    }

    private bool is_migration_applied (Gom.Repository repository,
                                       Gom.Adapter    adapter,
                                       uint           version)
    {
        try {
            Gom.Cursor? cursor = null;
            var check_command = (Gom.Command) GLib.Object.@new (typeof (Gom.Command),
                                                                adapter: adapter);
            check_command.set_sql ("SELECT 1 FROM _gom_version WHERE version = ? LIMIT 1;");
            check_command.set_param_uint (0U, version);

            check_command.execute (out cursor);

            if (cursor != null && cursor.next ()) {
                return true;
            }
        }
        catch (GLib.Error error) {
        }

        return false;
    }

    // public because it's used in tests
    public bool migrate_repository (Gom.Repository repository,
                                    Gom.Adapter    adapter,
                                    uint           version)
                                    throws GLib.Error
    {
        var is_test = Ft.is_test ();

        // Gom tries to re-apply last migration (bug in Gom?).
        if (is_migration_applied (repository, adapter, version))
        {
            if (!is_test) {
                GLib.info ("Migration version %u already applied, skipping", version);
            }

            return true;
        }

        uint8[] file_contents;

        var file = File.new_for_uri (@"$(MIGRATIONS_URI)/version-$(version).sql");
        file.load_contents (null, out file_contents, null);

        try {
            if (!is_test) {
                GLib.info ("Migrating database to version %u", version);
            }

            Ft.Database.execute_sql (adapter, (string) file_contents);
        }
        catch (GLib.Error error) {
            throw error;
        }

        return true;
    }

    /**
     * Check database health using PRAGMA `quick_check`.
     *
     * This function internally uses queue_read to run the check in the
     * GOM worker thread, then blocks the calling thread until the result
     * is available (similar to how `open_sync` / `close_sync` work).
     *
     * `quick_check` is faster than `integrity_check`. Should be good enough for most cases.
     */
    private bool check_health (Gom.Adapter adapter)
    {
        var result_queue = new GLib.AsyncQueue<bool?> ();

        adapter.queue_read (() => {
            var is_healthy = true;  // be forgiving by default

            unowned Sqlite.Database db = adapter.get_handle ();
            Sqlite.Statement statement;

            if (db.prepare_v2 ("PRAGMA quick_check;", -1, out statement) != Sqlite.OK) {
                GLib.warning ("Failed to prepare database health check: %s", db.errmsg ());
            }
            else if (statement.step () != Sqlite.ROW) {
                GLib.warning ("Database health check returned no results.");
            }
            else {
                unowned var result = statement.column_text (0);
                if (result == "ok") {
                    is_healthy = true;
                }
                else {
                    GLib.warning ("Database health check failed: %s", result);
                    is_healthy = false;
                }
            }

            result_queue.push (is_healthy);
        });

        // Block until result is available
        return result_queue.pop ();
    }

    private void rename_corrupted_file (GLib.File database_file) throws GLib.Error
    {
        var stamp = new GLib.DateTime.now_local ().format ("%Y-%m-%d");
        var destination_path = @"$(database_file.get_path()).corrupted-$(stamp)";
        var destination_file = GLib.File.new_for_path (destination_path);

        database_file.move (destination_file, GLib.FileCopyFlags.OVERWRITE);
    }

    private void restore_database_file (GLib.File database_file) throws GLib.Error
    {
        var backup_path = @"$(database_file.get_path()).backup";
        var backup_file = GLib.File.new_for_path (backup_path);

        backup_file.copy (database_file, GLib.FileCopyFlags.OVERWRITE);
    }

    private string build_database_path ()
    {
        var directory_path = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (),
                                                       Config.PACKAGE_NAME);
        return GLib.Path.build_filename (directory_path, "database.sqlite");
    }

    private string build_backup_path ()
    {
        return @"$(build_database_path()).backup";
    }

    private void delete_file_if_exists (string path)
    {
        var file = GLib.File.new_for_path (path);

        try {
            if (file.query_exists ()) {
                file.delete ();
            }
        }
        catch (GLib.Error error) {
        }
    }

    /**
     * Create database backup using SQLite's Backup API.
     *
     * This function internally uses queue_read to run the backup in the
     * GOM worker thread, then blocks the calling thread until completion.
     *
     * The backup is created as a temporary file (backup_path~) and only
     * moved to the final location after successful completion, ensuring
     * we never overwrite a good backup with a broken one.
     */
    private void create_backup (string backup_path)
    {
        if (Ft.Database.adapter == null) {
            return;
        }

        Ft.Database.adapter.queue_read (
            (adapter) => {
                var temp_backup_path = @"$(backup_path)~";
                var success = false;

                unowned Sqlite.Database db = adapter.get_handle ();
                Sqlite.Database backup_db;

                delete_file_if_exists (temp_backup_path);

                if (Sqlite.Database.open (temp_backup_path, out backup_db) != Sqlite.OK) {
                    GLib.warning ("Failed to open temporary backup database: %s",
                                  backup_db.errmsg ());
                    return;
                }

                Sqlite.Backup? backup = new Sqlite.Backup (backup_db, "main", db, "main");

                if (backup == null) {
                    GLib.warning ("Failed to initialize backup");
                    return;
                }

                // Perform backup in a single step
                var result = backup.step (-1);

                if (result == Sqlite.DONE)
                {
                    try {
                        var temp_backup_file = GLib.File.new_for_path (temp_backup_path);
                        var backup_file = GLib.File.new_for_path (backup_path);

                        temp_backup_file.move (backup_file, GLib.FileCopyFlags.OVERWRITE);
                        success = true;
                    }
                    catch (GLib.Error error) {
                        GLib.warning ("Failed to move temporary backup to final location: %s",
                                      error.message);
                    }
                }
                else {
                    GLib.warning ("Backup failed with error code: %d", result);
                }

                if (!success) {
                    delete_file_if_exists (temp_backup_path);
                }
            });
    }

    private bool should_create_backup (string backup_path)
    {
        var backup_file = GLib.File.new_for_path (backup_path);

        if (!backup_file.query_exists ()) {
            return true;
        }

        try {
            var info = backup_file.query_info (GLib.FileAttribute.TIME_MODIFIED,
                                               GLib.FileQueryInfoFlags.NONE);
            var modification_datetime = info.get_modification_date_time ();
            var now = new GLib.DateTime.now_local ();

            return modification_datetime == null ||
                   modification_datetime.get_year () != now.get_year () ||
                   modification_datetime.get_month () != now.get_month () ||
                   modification_datetime.get_day_of_month () != now.get_day_of_month ();
        }
        catch (GLib.Error error) {
            GLib.warning ("Failed to check last backup time: %s", error.message);
            return true;
        }
    }

    public void schedule_backup ()
    {
        if (Ft.is_test ()) {
            return;
        }

        GLib.Idle.add (() => {
            var backup_path = build_backup_path ();

            if (should_create_backup (backup_path)) {
                create_backup (backup_path);
            }

            return GLib.Source.REMOVE;
        }, GLib.Priority.LOW);
    }

    private void open_repository (GLib.File?          database_file,
                                  out Gom.Adapter?    adapter,
                                  out Gom.Repository? repository)
    {
        adapter = new Gom.Adapter ();
        repository = null;

        try {
            if (database_file != null) {
                make_directory_with_parents (database_file.get_parent ());
                adapter.open_sync (database_file.get_uri ());
            }
            else {
                adapter.open_sync (":memory:");
            }
        }
        catch (GLib.Error error) {
            GLib.critical ("Failed to open database '%s': %s",
                           database_file?.get_uri (),
                           error.message);
            // XXX: try recovery?

            return;
        }

        // Check database health after opening.
        // Restore from backup if the file is corrupt.
        if (database_file != null && !Ft.is_test () && !check_health (adapter))
        {
            try {
                adapter.close_sync ();
                adapter = null;
            }
            catch (GLib.Error error) {
                GLib.warning ("Error closing corrupted database: %s", error.message);
            }

            // Move corrupted file aside
            try {
                rename_corrupted_file (database_file);
            }
            catch (GLib.Error error) {
                GLib.critical ("Could not rename corrupted database: %s", error.message);
                return;
            }

            // Try to restore from backup
            var has_backup = false;
            try {
                restore_database_file (database_file);
                has_backup = true;
            }
            catch (GLib.Error error) {
            }

            // Reopen (either with restored backup or create fresh database)
            try {
                adapter = new Gom.Adapter ();
                adapter.open_sync (database_file.get_uri ());

                if (has_backup) {
                    GLib.info ("Restored database from backup");
                }
                else {
                    GLib.info ("No backup available, created a fresh database");
                }
            }
            catch (GLib.Error error) {
                GLib.critical ("Failed to open new database: %s", error.message);
                return;
            }
        }

        adapter.queue_write (
            (_adapter) => {
                try {
                    _adapter.execute_sql ("PRAGMA foreign_keys = ON;");
                }
                catch (GLib.Error error) {
                    GLib.warning ("Failed to enable 'foreign_keys': %s", error.message);
                }
            });

        try {
            repository = new Gom.Repository (adapter);
            repository.migrate_sync (Ft.Database.VERSION,
                                     Ft.Database.migrate_repository);
        }
        catch (GLib.Error error) {
            GLib.error ("Failed to migrate database: %s", error.message);
        }
    }

    public void open ()
    {
        GLib.File? database_file = null;

        if (Ft.Database.repository != null) {
            return;
        }

        if (!Ft.is_test ())
        {
            var database_path = build_database_path ();
            database_file = GLib.File.new_for_path (database_path);

            var directory_file = database_file.get_parent ();
            if (directory_file != null && !directory_file.query_exists ()) {
                make_directory_with_parents (directory_file);
            }

            // Import database from the old app
            // XXX: let users migrate their data, but remove this at some point
            string old_database_path;

            if (Ft.is_flatpak ()) {
                old_database_path = GLib.Path.build_filename (GLib.Environment.get_home_dir (),
                                                              ".local",
                                                              "share",
                                                              "gnome-pomodoro",
                                                              "database.sqlite");
            }
            else {
                old_database_path = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (),
                                                              "gnome-pomodoro",
                                                              "database.sqlite");
            }

            var old_database_file = GLib.File.new_for_path (old_database_path);

            if (!database_file.query_exists () && old_database_file.query_exists ())
            {
                try {
                    old_database_file.copy (database_file, GLib.FileCopyFlags.NONE, null, null);
                    GLib.info ("Imported database from %s to %s", old_database_path, database_path);
                }
                catch (GLib.Error error) {
                    GLib.warning ("Failed to import database: %s", error.message);
                }
            }
        }

        open_repository (database_file,
                         out Ft.Database.adapter,
                         out Ft.Database.repository);
    }

    private void close_repository (Gom.Repository repository)
    {
        var adapter = repository.adapter;

        try {
            adapter.close_sync ();
        }
        catch (GLib.Error error) {
            GLib.warning ("Error while closing database: %s", error.message);
        }
    }

    public void close ()
    {
        if (Ft.Database.repository == null) {
            return;
        }

        close_repository (Ft.Database.repository);

        Ft.Database.repository = null;
        Ft.Database.adapter = null;
    }

    public string serialize_date (GLib.Date date)
    {
        return date.valid ()
                ? Ft.DateUtils.format_date (date, DATE_FORMAT)
                : "";
    }

    /**
     * Remove leading zeros from a string
     */
    private inline string chug_zeros (string str)
    {
        var index = 0;

        while (str.@get (index) == '0') {
            index++;
        }

        return index > 0
                ? str.substring (index)
                : str;
    }

    public GLib.Date parse_date (string date_string)
    {
        var parts = date_string.split ("-");
        var date = GLib.Date ();

        if (parts.length == 3)
        {
            var year  = uint.parse (chug_zeros (parts[0]));
            var month = uint.parse (chug_zeros (parts[1]));
            var day   = uint.parse (chug_zeros (parts[2]));

            date.set_dmy ((GLib.DateDay) day,
                          (GLib.DateMonth) month,
                          (GLib.DateYear) year);
        }

        return date;
    }
}
