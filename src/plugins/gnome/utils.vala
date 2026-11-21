/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Gnome
{
    private inline int parse_version_part (string part)
    {
        int value;

        return int.try_parse (part, out value)
                ? value
                : 0;
    }


    public bool is_version_at_least (string current_version,
                                     string required_version)
    {
        var current_parts = current_version.split (".");
        var required_parts = required_version.split (".");
        var length = int.max (current_parts.length, required_parts.length);

        for (var index = 0; index < length; index++)
        {
            var current_part = index < current_parts.length
                    ? parse_version_part (current_parts[index])
                    : 0;
            var required_part = index < required_parts.length
                    ? parse_version_part (required_parts[index])
                    : 0;

            if (current_part != required_part) {
                return current_part > required_part;
            }
        }

        return true;
    }
}
