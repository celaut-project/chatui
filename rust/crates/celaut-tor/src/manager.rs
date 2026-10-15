use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use celaut_net::{set_route, Route, Socks5};
use tokio::net::TcpStream;
use tokio::task::JoinHandle;

use crate::arti;

/// What the user chose.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Mode {
    /// Direct connections.
    Off,
    /// An Arti client inside the app. The directories are in the private storage of the
    /// app: the state (keys and guards) and the cache (the directory of the network).
    Embedded {
        state_dir: PathBuf,
        cache_dir: PathBuf,
    },
    /// An external SOCKS5 proxy, for example Orbot (`127.0.0.1:9050`). The app trusts
    /// that it is a Tor proxy.
    Socks { addr: SocketAddr },
}

/// The mode without its settings.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ModeKind {
    Off,
    Embedded,
    Socks,
}

impl Mode {
    pub fn kind(&self) -> ModeKind {
        match self {
            Mode::Off => ModeKind::Off,
            Mode::Embedded { .. } => ModeKind::Embedded,
            Mode::Socks { .. } => ModeKind::Socks,
        }
    }
}

/// Where the proxy is.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum State {
    /// No proxy: direct connections.
    Off,
    /// The proxy starts. The percent is the bootstrap of Tor, 0 to 100. Every connection
    /// fails meanwhile.
    Starting { percent: u8 },
    /// The connections go through the proxy.
    Ready,
    /// The proxy did not start, or it stopped. Every connection fails. The text is the
    /// reason, in English.
    Failed(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Status {
    pub mode: ModeKind,
    pub state: State,
}

struct Inner {
    kind: ModeKind,
    state: State,
    /// Each `set_mode` makes a new number. A task of an older mode that ends late does
    /// not change the state of the new one.
    generation: u64,
    tasks: Vec<JoinHandle<()>>,
}

/// The one place that decides the route of the app. See the crate text.
pub struct Manager {
    inner: Arc<Mutex<Inner>>,
}

const SOCKS_CHECK_TIMEOUT: Duration = Duration::from_secs(5);

impl Manager {
    pub fn new() -> Manager {
        Manager {
            inner: Arc::new(Mutex::new(Inner {
                kind: ModeKind::Off,
                state: State::Off,
                generation: 0,
                tasks: Vec::new(),
            })),
        }
    }

    pub fn status(&self) -> Status {
        let inner = lock(&self.inner);
        Status {
            mode: inner.kind,
            state: inner.state.clone(),
        }
    }

    /// Tor is on (`kind` is `Embedded` or `Socks`) but its settings cannot be used. Stop
    /// the proxy of the old mode and block every connection, with `reason` as the error.
    /// The app does not go direct because the settings are wrong.
    pub fn block(&self, kind: ModeKind, reason: String) {
        let mut inner = lock(&self.inner);
        for task in inner.tasks.drain(..) {
            task.abort();
        }
        inner.generation += 1;
        inner.kind = kind;
        inner.state = State::Failed(reason.clone());
        set_route(Route::Blocked(reason));
    }

    /// Change the mode. It stops the proxy of the old mode. With Tor on, the route is
    /// blocked when this returns, and it becomes the proxy when the proxy is ready: see
    /// [`Manager::status`]. It must run inside a Tokio runtime.
    pub fn set_mode(&self, mode: Mode) {
        let mut inner = lock(&self.inner);
        for task in inner.tasks.drain(..) {
            task.abort();
        }
        inner.generation += 1;
        let generation = inner.generation;
        inner.kind = mode.kind();
        match mode {
            Mode::Off => {
                inner.state = State::Off;
                set_route(Route::Direct);
            }
            Mode::Socks { addr } => {
                inner.state = State::Starting { percent: 0 };
                set_route(Route::Blocked(format!(
                    "checking the SOCKS5 proxy at {addr}"
                )));
                let shared = self.inner.clone();
                inner.tasks.push(tokio::spawn(async move {
                    let reached = tokio::time::timeout(SOCKS_CHECK_TIMEOUT, TcpStream::connect(addr))
                        .await;
                    match reached {
                        Ok(Ok(_)) => publish(
                            &shared,
                            generation,
                            State::Ready,
                            Route::Socks(Socks5 { addr, auth: None }),
                        ),
                        _ => fail(
                            &shared,
                            generation,
                            format!("the SOCKS5 proxy at {addr} does not answer"),
                        ),
                    }
                }));
            }
            Mode::Embedded {
                state_dir,
                cache_dir,
            } => {
                inner.state = State::Starting { percent: 0 };
                set_route(Route::Blocked("Tor is starting".to_string()));
                let shared = self.inner.clone();
                inner.tasks.push(tokio::spawn(async move {
                    let mut tasks = Vec::new();
                    let progress = {
                        let shared = shared.clone();
                        move |percent: u8| {
                            let mut inner = lock(&shared);
                            if inner.generation == generation
                                && matches!(inner.state, State::Starting { .. })
                            {
                                inner.state = State::Starting { percent };
                            }
                        }
                    };
                    match arti::start(state_dir, cache_dir, progress, &mut tasks).await {
                        Ok(running) => {
                            // The tasks of the client and of the proxy live as long as
                            // this mode.
                            let mut inner = lock(&shared);
                            if inner.generation == generation {
                                inner.tasks.append(&mut tasks);
                                inner.state = State::Ready;
                                set_route(Route::Socks(running.proxy));
                            } else {
                                for task in tasks {
                                    task.abort();
                                }
                            }
                        }
                        Err(reason) => {
                            for task in tasks {
                                task.abort();
                            }
                            fail(&shared, generation, reason);
                        }
                    }
                }));
            }
        }
    }
}

impl Default for Manager {
    fn default() -> Self {
        Manager::new()
    }
}

fn lock(inner: &Mutex<Inner>) -> std::sync::MutexGuard<'_, Inner> {
    inner.lock().unwrap_or_else(|e| e.into_inner())
}

/// Set the state and the route together, if the mode is still the same.
fn publish(shared: &Mutex<Inner>, generation: u64, state: State, route: Route) {
    let mut inner = lock(shared);
    if inner.generation == generation {
        inner.state = state;
        set_route(route);
    }
}

/// The proxy failed: every connection fails, and the app does not go direct.
fn fail(shared: &Mutex<Inner>, generation: u64, reason: String) {
    publish(
        shared,
        generation,
        State::Failed(reason.clone()),
        Route::Blocked(reason),
    );
}

/// The manager of the app.
pub fn manager() -> &'static Manager {
    static MANAGER: OnceLock<Manager> = OnceLock::new();
    MANAGER.get_or_init(Manager::new)
}
