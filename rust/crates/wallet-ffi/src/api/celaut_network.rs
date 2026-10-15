//! Optional Tor for the outbound connections of the app (milestone M5,
//! `docs/celaut-plan.md`).
//!
//! The user chooses: no Tor, the Arti client inside the app, or an external SOCKS5 proxy
//! (Orbot). With Tor on, the app never falls back to a direct connection: while the
//! proxy starts, and when it fails, every connection to a node and to the explorer
//! fails with a clear error (`celaut_tor`, `celaut_net`).

use std::net::SocketAddr;
use std::path::PathBuf;

use celaut_tor::{manager, Mode, ModeKind, State};

use super::celaut::{CelautError, CelautErrorKind};

/// What the user chose.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetworkChoice {
    /// Direct connections.
    Off,
    /// The Tor client inside the app.
    Embedded,
    /// An external SOCKS5 proxy.
    Socks,
}

/// Where the proxy is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetworkState {
    /// No proxy: direct connections.
    Off,
    /// The proxy starts. Every connection fails meanwhile.
    Starting,
    /// The connections go through the proxy.
    Ready,
    /// The proxy failed. Every connection fails.
    Failed,
}

/// The state of the network route.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkStatusView {
    pub choice: NetworkChoice,
    pub state: NetworkState,
    /// The bootstrap of Tor in percent, 0 to 100. Only while `state` is `Starting`.
    pub percent: u8,
    /// The reason, in English. Only when `state` is `Failed`.
    pub error: String,
}

fn invalid(message: impl Into<String>) -> CelautError {
    CelautError {
        kind: CelautErrorKind::InvalidInput,
        message: message.into(),
    }
}

/// The mode that a choice means, or why the settings cannot be used.
fn mode_of(
    choice: NetworkChoice,
    socks_address: Option<String>,
    data_dir: &str,
) -> Result<Mode, CelautError> {
    match choice {
        NetworkChoice::Off => Ok(Mode::Off),
        NetworkChoice::Embedded => {
            if data_dir.trim().is_empty() {
                return Err(invalid("the Tor client needs a directory for its state"));
            }
            let root = PathBuf::from(data_dir).join("tor");
            Ok(Mode::Embedded {
                state_dir: root.join("state"),
                cache_dir: root.join("cache"),
            })
        }
        NetworkChoice::Socks => {
            let text = socks_address.unwrap_or_default();
            let addr: SocketAddr = text
                .trim()
                .parse()
                .map_err(|_| invalid(format!("not an IP address and port: {text}")))?;
            Ok(Mode::Socks { addr })
        }
    }
}

/// Change the network route. With `Embedded` or `Socks`, every connection is blocked
/// from the moment that this returns until the proxy is ready: see
/// [`celaut_network_status`]. `socks_address` is `host:port` of the proxy, for `Socks`
/// only, and it must be an IP address (for example `127.0.0.1:9050`). `data_dir` is a
/// private directory of the app, for the state of the Tor client.
///
/// If the settings cannot be used, this returns the error and, with Tor on, the route is
/// blocked: the app does not go direct because of a wrong setting.
#[flutter_rust_bridge::frb]
pub async fn celaut_set_network(
    choice: NetworkChoice,
    socks_address: Option<String>,
    data_dir: String,
) -> Result<(), CelautError> {
    match mode_of(choice, socks_address, &data_dir) {
        Ok(mode) => manager().set_mode(mode),
        Err(error) => {
            let kind = match choice {
                NetworkChoice::Embedded => ModeKind::Embedded,
                _ => ModeKind::Socks,
            };
            manager().block(kind, error.message.clone());
            super::clear_node_clients();
            return Err(error);
        }
    }
    // The clients to the Ergo nodes that were made before keep their old route.
    super::clear_node_clients();
    Ok(())
}

/// The state of the network route now.
#[flutter_rust_bridge::frb(sync)]
pub fn celaut_network_status() -> NetworkStatusView {
    view_of(manager().status())
}

fn view_of(status: celaut_tor::Status) -> NetworkStatusView {
    let choice = match status.mode {
        ModeKind::Off => NetworkChoice::Off,
        ModeKind::Embedded => NetworkChoice::Embedded,
        ModeKind::Socks => NetworkChoice::Socks,
    };
    let (state, percent, error) = match status.state {
        State::Off => (NetworkState::Off, 0, String::new()),
        State::Starting { percent } => (NetworkState::Starting, percent, String::new()),
        State::Ready => (NetworkState::Ready, 0, String::new()),
        State::Failed(reason) => (NetworkState::Failed, 0, reason),
    };
    NetworkStatusView {
        choice,
        state,
        percent,
        error,
    }
}

#[cfg(test)]
mod tests {
    //! These tests do not change the route of the process: other tests of this crate
    //! make HTTP requests. The change of the route is tested in `celaut-tor`.

    use super::*;
    use celaut_tor::Status;

    #[test]
    fn a_bad_socks_address_and_a_missing_directory_are_refused() {
        for bad in ["", "localhost:9050", "127.0.0.1", "127.0.0.1:99999"] {
            let error = mode_of(NetworkChoice::Socks, Some(bad.into()), "").unwrap_err();
            assert_eq!(error.kind, CelautErrorKind::InvalidInput, "{bad}");
        }
        assert!(mode_of(NetworkChoice::Socks, None, "").is_err());
        let error = mode_of(NetworkChoice::Embedded, None, "  ").unwrap_err();
        assert_eq!(error.kind, CelautErrorKind::InvalidInput);
    }

    #[test]
    fn a_good_choice_is_a_mode() {
        assert_eq!(mode_of(NetworkChoice::Off, None, "").unwrap(), Mode::Off);
        assert_eq!(
            mode_of(NetworkChoice::Socks, Some(" 127.0.0.1:9050 ".into()), "").unwrap(),
            Mode::Socks { addr: "127.0.0.1:9050".parse().unwrap() }
        );
        assert_eq!(
            mode_of(NetworkChoice::Embedded, None, "/data/app").unwrap(),
            Mode::Embedded {
                state_dir: PathBuf::from("/data/app/tor/state"),
                cache_dir: PathBuf::from("/data/app/tor/cache"),
            }
        );
    }

    #[test]
    fn the_view_of_each_state() {
        let view = |mode, state| view_of(Status { mode, state });
        let off = view(ModeKind::Off, State::Off);
        assert_eq!((off.choice, off.state, off.percent), (NetworkChoice::Off, NetworkState::Off, 0));
        let starting = view(ModeKind::Embedded, State::Starting { percent: 42 });
        assert_eq!(
            (starting.choice, starting.state, starting.percent),
            (NetworkChoice::Embedded, NetworkState::Starting, 42)
        );
        let ready = view(ModeKind::Socks, State::Ready);
        assert_eq!((ready.choice, ready.state), (NetworkChoice::Socks, NetworkState::Ready));
        let failed = view(ModeKind::Embedded, State::Failed("no network".into()));
        assert_eq!((failed.state, failed.error.as_str()), (NetworkState::Failed, "no network"));
    }
}
