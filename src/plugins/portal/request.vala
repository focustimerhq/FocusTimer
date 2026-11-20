/*
 * Copyright (c) 2025-2026 focus-timer contributors
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


    /**
     * Create a request_handle that will identify the request.
     *
     * It will close the request if we won't get response in set `timeout`.
     * and call the callback with `Portal.Response.OTHER`.
     */
    public async string create_request (GLib.DBusConnection    connection,
                                        Portal.RequestCallback callback)
                                        throws GLib.Error
    {
        var request_id     = next_request_id;
        var handle_token   = "focustimer_" + request_id.to_string ();
        var sender         = connection.get_unique_name ();
        var sender_escaped = sender.replace (":", "").replace (".", "_");

        next_request_id++;

        var request_proxy = yield GLib.Bus.get_proxy<Portal.Request> (
                GLib.BusType.SESSION,
                "org.freedesktop.portal.Desktop",
                @"/org/freedesktop/portal/desktop/request/$(sender_escaped)/$(handle_token)");
        request_proxy.response.connect (
            (response, results) => {
                if (Portal.destroy_request (handle_token)) {
                    callback (response, results);
                }
            });

        if (requests == null) {
            requests = new GLib.HashTable<string, Portal.Request> (GLib.str_hash,
                                                                   GLib.str_equal);
        }

        requests.insert (handle_token, request_proxy);

        return handle_token;
    }


    public async void close_request (string handle_token) throws GLib.Error
    {
        if (requests == null) {
            return;
        }

        var request = requests.lookup (handle_token);

        if (request != null) {
            requests.remove (handle_token);
            yield request.close ();
        }
    }


    public bool destroy_request (string handle_token)
    {
        return requests != null
            ? requests.remove (handle_token)
            : false;
    }
}
