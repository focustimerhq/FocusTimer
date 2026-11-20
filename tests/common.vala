/*
 * Copyright (c) 2014 focus-timer contributors
 *
 * This code is partly borrowed from libgee's test suite,
 * at https://git.gnome.org/browse/libgee and from gnome-break-timer
 * https://git.gnome.org/browse/gnome-break-timer
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

using GLib;


namespace Tests
{
    public delegate void TestCaseFunc ();

    private string str_to_representation (string value)
    {
        return @"\"$value\"";
    }

    private string strv_to_representation (string[] value)
    {
        var string_builder = new GLib.StringBuilder ("[");
        var length = value.length;

        for (var index = 0; index < length; index++)
        {
            if (index > 0) {
                string_builder.append (", ");
            }
            string_builder.append (str_to_representation (value[index]));
        }

        string_builder.append ("]");

        return string_builder.str;
    }

    public void assert_cmpstrv (string[] value,
                                string[] expected)
    {
        if (GLib.Test.failed ()) {
            return;
        }

        var length = value.length;

        if (length != expected.length)
        {
            GLib.Test.message (
                "Arrays have different length: %s != %s",
                strv_to_representation (value),
                strv_to_representation (expected)
            );
            GLib.Test.fail ();
            return;
        }

        for (var index = 0; index < length; index++)
        {
            if (value[index] != expected[index])
            {
                GLib.Test.message (
                    "Arrays are not equal: %s != %s",
                    strv_to_representation (value),
                    strv_to_representation (expected)
                );
                GLib.Test.fail ();
                return;
            }
        }
    }

    public void wait_for_object_finalized (owned GLib.Object object)
    {
        void* weak_object = object;

        object.add_weak_pointer (&weak_object);
        object = null;

        assert_null (weak_object);
    }


    private class TestCase
    {
        public string name;

        private Tests.TestCaseFunc func;
        private Tests.TestSuite    test_suite;

        public TestCase (string                   name,
                         owned Tests.TestCaseFunc test_case_func,
                         Tests.TestSuite          test_suite)
        {
            this.name       = name;
            this.func       = (owned) test_case_func;
            this.test_suite = test_suite;
        }

        public void setup (void* fixture)
        {
            this.test_suite.setup ();
        }

        public void run (void* fixture)
        {
            this.func ();
        }

        public void teardown (void* fixture)
        {
            this.test_suite.teardown ();
        }

        public GLib.TestCase get_g_test_case ()
        {
            return new GLib.TestCase (this.name,
                                      this.setup,
                                      this.run,
                                      this.teardown);
        }
    }


    public abstract class TestSuite : GLib.Object
    {
        private GLib.TestSuite   g_test_suite;
        private Tests.TestCase[] test_cases;

        construct
        {
            this.g_test_suite = new GLib.TestSuite (this.get_name ());
            this.test_cases = new Tests.TestCase[0];
        }

        public string get_name ()
        {
            return this.get_type ().name ();
        }

        public GLib.TestSuite get_g_test_suite ()
        {
            return this.g_test_suite;
        }

        public void add_test (string                   name,
                              owned Tests.TestCaseFunc func)
        {
            var test_case = new TestCase (name, (owned) func, this);

            this.test_cases += test_case;
            this.g_test_suite.add (test_case.get_g_test_case ());
        }

        public virtual void setup ()
        {
        }

        public virtual void teardown ()
        {
        }
    }


    public abstract class MainLoopTestSuite : TestSuite
    {
        private uint timeout_id = 0;

        protected GLib.MainLoop? main_loop;

        protected bool run_main_loop (uint timeout = 1000)
                                      requires (this.timeout_id == 0)
        {
            var success = true;

            this.timeout_id = GLib.Timeout.add (timeout, () => {
                this.timeout_id = 0;
                this.main_loop.quit ();

                success = false;

                return GLib.Source.REMOVE;
            });

            this.main_loop.run ();

            return success;
        }

        protected void quit_main_loop ()
        {
            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            this.main_loop.quit ();
        }

        public override void setup ()
        {
            base.setup ();

            this.main_loop = new GLib.MainLoop ();
        }

        public override void teardown ()
        {
            base.teardown ();

            this.main_loop = null;
        }
    }


    public class DBus : GLib.Object
    {
        private GLib.TestDBus bus;
        private uint          registration_id;

        public GLib.DBusConnection connection {
            get;
            private set;
        }

        public DBus ()
        {
            this.bus = new GLib.TestDBus (GLib.TestDBusFlags.NONE);
            this.bus.up ();

            // Address the test bus directly. A cached session connection can
            // still be the desktop bus and would own the name there.
            try {
                this.connection = new GLib.DBusConnection.for_address_sync (
                        this.bus.get_bus_address (),
                        GLib.DBusConnectionFlags.AUTHENTICATION_CLIENT |
                        GLib.DBusConnectionFlags.MESSAGE_BUS_CONNECTION);
            }
            catch (GLib.Error error) {
                GLib.error ("Private bus failed: %s", error.message);
            }
        }

        ~DBus ()
        {
            if (this.registration_id != 0) {
                this.connection.unregister_object (this.registration_id);
                this.registration_id = 0;
            }

            this.bus.down ();
        }

        public void register_object<T> (string bus_name,
                                        string object_path,
                                        T      service)
        {
            try {
                var reply = this.connection.call_sync (
                        "org.freedesktop.DBus",
                        "/org/freedesktop/DBus",
                        "org.freedesktop.DBus",
                        "RequestName",
                        new GLib.Variant ("(su)", bus_name, 0U),
                        new GLib.VariantType ("(u)"),
                        GLib.DBusCallFlags.NONE,
                        -1);
                uint32 result;
                reply.get ("(u)", out result);

                if (result != 1U) {
                    GLib.error ("Failed to own %s", bus_name);
                }

                this.registration_id = this.connection.register_object (object_path, service);
            }
            catch (GLib.Error error) {
                GLib.error ("Private bus failed: %s", error.message);
            }
        }
    }


    public static void init (string[] args)
    {
        GLib.Test.init (ref args);

        // Undo changes made by Test.init(), don't make warnings fatal.
        GLib.Log.set_always_fatal (GLib.LogLevelFlags.LEVEL_ERROR | GLib.LogLevelFlags.LEVEL_CRITICAL);
    }


    public static int run (Tests.TestSuite test_suite, ...)
    {
        var arguments_list = va_list ();
        var root_suite = GLib.TestSuite.get_root ();

        root_suite.add_suite (test_suite.get_g_test_suite ());

        while (true)
        {
            Tests.TestSuite? extra_test_suite = arguments_list.arg ();

            if (extra_test_suite != null) {
                root_suite.add_suite (extra_test_suite.get_g_test_suite ());
            }
            else {
                // End of the list.
                break;
            }
        }

        return GLib.Test.run ();
    }
}
