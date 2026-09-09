use crate::app::WaylandSurface;
use wayland_client::backend::{Backend, ObjectId};
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::wl_registry::WlRegistry;
use wayland_client::protocol::wl_surface::WlSurface;
use wayland_client::{Connection, Dispatch, Proxy, QueueHandle};
use wayland_protocols::wp::idle_inhibit::zv1::client::{
    zwp_idle_inhibit_manager_v1::ZwpIdleInhibitManagerV1,
    zwp_idle_inhibitor_v1::ZwpIdleInhibitorV1,
};

/// Minimal dispatch sink. We only ever send requests (bind, create_inhibitor,
/// destroy); none of these objects emit events we care about.
struct State;

impl Dispatch<WlRegistry, GlobalListContents> for State {
    fn event(_: &mut Self, _: &WlRegistry, _: <WlRegistry as Proxy>::Event,
        _: &GlobalListContents, _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZwpIdleInhibitManagerV1, ()> for State {
    fn event(_: &mut Self, _: &ZwpIdleInhibitManagerV1,
        _: <ZwpIdleInhibitManagerV1 as Proxy>::Event, _: &(),
        _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZwpIdleInhibitorV1, ()> for State {
    fn event(_: &mut Self, _: &ZwpIdleInhibitorV1,
        _: <ZwpIdleInhibitorV1 as Proxy>::Event, _: &(),
        _: &Connection, _: &QueueHandle<Self>) {}
}

/// All fields are Send (wayland-client sys objects are Send+Sync). The shell
/// hands over the raw handles; getting those is what must happen on the GUI
/// thread, and it has already happened by the time we are called.
pub struct WaylandInhibitor {
    _conn: Connection,
    inhibitor: ZwpIdleInhibitorV1,
}

impl WaylandInhibitor {
    /// Build an inhibitor over the shell's own wl_display and wl_surface.
    /// Upstream dug these out of GDK; the shell hands them over directly.
    fn build(surface_handles: WaylandSurface) -> Option<Self> {
        let display_ptr = surface_handles.display;
        let surface_ptr = surface_handles.surface;
        if display_ptr.is_null() || surface_ptr.is_null() {
            log::warn!("shell reported no wl_display/wl_surface");
            return None;
        }

        let backend = unsafe { Backend::from_foreign_display(display_ptr as *mut _) };
        let conn = Connection::from_backend(backend);

        let (globals, mut queue) = registry_queue_init::<State>(&conn).ok()?;
        let qh = queue.handle();
        let manager: ZwpIdleInhibitManagerV1 = match globals.bind::<ZwpIdleInhibitManagerV1, _, _>(&qh, 1..=1, ()) {
            Ok(m) => m,
            Err(e) => {
                log::warn!("compositor has no zwp_idle_inhibit_manager_v1: {e}");
                return None;
            }
        };

        let id = unsafe {
            ObjectId::from_ptr(WlSurface::interface(), surface_ptr as *mut _).ok()?
        };
        let surface = WlSurface::from_id(&conn, id).ok()?;

        let inhibitor = manager.create_inhibitor(&surface, &qh, ());
        let _ = queue.flush();
        let mut state = State;
        let _ = queue.roundtrip(&mut state);
        log::info!("Wayland idle inhibitor created");

        Some(Self { _conn: conn, inhibitor })
    }

    /// Public entry. The handles come from the shell, which read them on its
    /// GUI thread, so there is no thread hop left to make here.
    pub fn start(surface_handles: Option<WaylandSurface>) -> Option<Self> {
        Self::build(surface_handles?)
    }

    pub fn stop(self) {
        self.inhibitor.destroy();
        log::info!("Wayland idle inhibitor destroyed");
    }
}
