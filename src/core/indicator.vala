/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    public interface IndicatorProvider : Ft.Provider
    {
        public abstract bool visible { get; }
    }


    /**
     * A helper primitive to ensure only one indicator is enabled at a time.
     *
     * Also, to run the app in background when an indicator is available.
     */
    [SingleInstance]
    public class Indicator : Ft.ProvidedObject<Ft.IndicatorProvider>
    {
        private Ft.BackgroundManager?   background_manager = null;
        private uint                    background_hold_id = 0U;

        private void update_background_hold ()
        {
            if (this.provider != null &&
                this.provider.enabled &&
                this.provider.visible)
            {
                if (this.background_hold_id == 0U) {
                    this.background_hold_id = this.background_manager.hold ();
                }
            }
            else {
                if (this.background_hold_id != 0U) {
                    this.background_manager.release (this.background_hold_id);
                    this.background_hold_id = 0U;
                }
            }
        }

        private void on_notify_visible (GLib.Object    obj,
                                        GLib.ParamSpec pspec)
        {
            this.update_background_hold ();
        }

        protected override void initialize ()
        {
            this.background_manager = new Ft.BackgroundManager ();
        }

        protected override void setup_providers ()
        {
        }

        protected override void provider_enabled (Ft.IndicatorProvider provider)
        {
            provider.notify["visible"].connect (this.on_notify_visible);

            this.update_background_hold ();
        }

        protected override void provider_disabled (Ft.IndicatorProvider provider)
        {
            provider.notify["visible"].disconnect (this.on_notify_visible);

            this.update_background_hold ();
        }

        public override void dispose ()
        {
            if (this.background_hold_id != 0U) {
                this.background_manager.release (this.background_hold_id);
                this.background_hold_id = 0U;
            }

            this.background_manager = null;

            base.dispose ();
        }
    }
}
