/*
 * Copyright (c) 2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Portal
{
    private uint                                   next_request_id = 1U;
    private GLib.HashTable<string, Portal.Request> requests = null;


    public delegate void RequestCallback (uint32       response,
                                          GLib.Variant results);


    public async string create_request (GLib.DBusConnection    connection,
                                        Portal.RequestCallback callback) throws GLib.Error
    {
        var request_id     = next_request_id;
        var handle_token   = "focustimer_" + request_id.to_string ();
        var sender         = connection.get_unique_name ();
        var sender_escaped = sender.replace (":", "").replace (".", "_");

        next_request_id++;

        var request_proxy = yield connection.get_proxy<Portal.Request> (
                "org.freedesktop.portal.Desktop",
                @"/org/freedesktop/portal/desktop/request/$(sender_escaped)/$(handle_token)");
        request_proxy.response.connect (
            (response, results) => {
                Portal.destroy_request (handle_token);

                callback (response, results);
            });

        if (requests == null) {
            requests = new GLib.HashTable<string, Portal.Request> (GLib.str_hash,
                                                                   GLib.str_equal);
        }

        requests.insert (handle_token, request_proxy);

        return handle_token;
    }


    public bool close_request (string handle_token)
    {
        var request = requests != null ? requests.lookup (handle_token) : null;

        if (request == null) {
            return false;
        }

        request.close.begin ((obj, res) => {
            try {
                request.close.end (res);
            }
            catch (GLib.Error error) {
                GLib.debug ("Failed to close portal request: %s", error.message);
            }
        });

        return Portal.destroy_request (handle_token);
    }


    public bool destroy_request (string handle_token)
    {
        return requests != null
            ? requests.remove (handle_token)
            : false;
    }
}
