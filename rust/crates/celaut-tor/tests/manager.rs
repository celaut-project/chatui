//! The manager and the route. The route is one value for the whole process, so these
//! cases are in one test function and the manager is a new one in each.

use std::net::SocketAddr;
use std::time::Duration;

use celaut_net::socks::listen_loopback;
use celaut_net::{route, Route};
use celaut_tor::{Manager, Mode, ModeKind, State};

async fn wait_for(manager: &Manager, done: impl Fn(&State) -> bool) -> State {
    for _ in 0..200 {
        let state = manager.status().state;
        if done(&state) {
            return state;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    panic!("the state did not come: {:?}", manager.status());
}

#[tokio::test]
async fn the_route_follows_the_mode_and_never_goes_direct_by_mistake() {
    // Off: direct.
    let manager = Manager::new();
    assert_eq!(manager.status().mode, ModeKind::Off);
    assert_eq!(manager.status().state, State::Off);
    manager.set_mode(Mode::Off);
    assert_eq!(route(), Route::Direct);

    // An external proxy that answers: blocked at once, then the proxy.
    let (listener, addr) = listen_loopback().await.unwrap();
    tokio::spawn(async move {
        loop {
            let _ = listener.accept().await;
        }
    });
    manager.set_mode(Mode::Socks { addr });
    assert!(
        matches!(route(), Route::Blocked(_)),
        "the route is blocked when set_mode returns"
    );
    assert_eq!(manager.status().mode, ModeKind::Socks);
    wait_for(&manager, |s| *s == State::Ready).await;
    assert!(matches!(route(), Route::Socks(p) if p.addr == addr && p.auth.is_none()));

    // Back to off.
    manager.set_mode(Mode::Off);
    assert_eq!(route(), Route::Direct);
    assert_eq!(manager.status().state, State::Off);

    // An external proxy that does not answer: failed, and blocked, never direct.
    let (listener, dead) = listen_loopback().await.unwrap();
    drop(listener);
    manager.set_mode(Mode::Socks { addr: dead });
    let state = wait_for(&manager, |s| matches!(s, State::Failed(_))).await;
    let State::Failed(reason) = state else { unreachable!() };
    assert!(reason.contains(&dead.to_string()), "{reason}");
    assert!(matches!(route(), Route::Blocked(r) if r == reason));

    // A late end of an old mode does not change the new mode: the check of the dead
    // proxy is slow to fail on some systems, and the user has turned Tor off.
    manager.set_mode(Mode::Socks { addr: dead });
    manager.set_mode(Mode::Off);
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(route(), Route::Direct);
    assert_eq!(manager.status().state, State::Off);

    // Settings that cannot be used: blocked with the reason, never direct.
    manager.block(ModeKind::Socks, "not an IP address and port: x".into());
    assert_eq!(manager.status().mode, ModeKind::Socks);
    assert_eq!(
        manager.status().state,
        State::Failed("not an IP address and port: x".into())
    );
    assert!(matches!(route(), Route::Blocked(r) if r.contains("not an IP address")));

    // An embedded client that cannot start (the directory is a file): failed and blocked.
    let file = std::env::temp_dir().join(format!("celaut-tor-test-{}", std::process::id()));
    std::fs::write(&file, b"a file, not a directory").unwrap();
    manager.set_mode(Mode::Embedded {
        state_dir: file.join("state"),
        cache_dir: file.join("cache"),
    });
    assert!(matches!(route(), Route::Blocked(_)));
    let state = wait_for(&manager, |s| matches!(s, State::Failed(_))).await;
    assert!(matches!(state, State::Failed(_)));
    assert!(matches!(route(), Route::Blocked(_)));
    manager.set_mode(Mode::Off);
    assert_eq!(route(), Route::Direct);
    let _ = std::fs::remove_file(&file);
    let _ = SocketAddr::from(([127, 0, 0, 1], 0));
}
