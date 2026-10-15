//! A real bootstrap on the Tor network. It needs the Internet and takes a minute, so it
//! is ignored: `cargo test -p celaut-tor --test real_tor -- --ignored --nocapture`.

use std::time::Duration;

use celaut_net::{route, Route};
use celaut_tor::{Manager, Mode, State};

#[tokio::test]
#[ignore = "needs the Internet"]
async fn the_embedded_client_gives_a_tor_exit_to_the_http_clients_of_the_app() {
    let dir = std::env::temp_dir().join(format!("celaut-tor-real-{}", std::process::id()));
    let manager = Manager::new();
    manager.set_mode(Mode::Embedded {
        state_dir: dir.join("state"),
        cache_dir: dir.join("cache"),
    });
    assert!(matches!(route(), Route::Blocked(_)));

    let started = std::time::Instant::now();
    let mut last = 0;
    loop {
        match manager.status().state {
            State::Ready => break,
            State::Failed(reason) => panic!("Tor did not start: {reason}"),
            State::Starting { percent } => {
                if percent != last {
                    println!("bootstrap {percent}% after {:?}", started.elapsed());
                    last = percent;
                }
            }
            State::Off => panic!("off"),
        }
        assert!(started.elapsed() < Duration::from_secs(300), "too slow");
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    println!("ready after {:?}", started.elapsed());
    assert!(matches!(route(), Route::Socks(_)));

    // The service of the Tor Project says if the request came from Tor.
    let answer = wallet_net::http::client()
        .get("https://check.torproject.org/api/ip")
        .timeout(Duration::from_secs(120))
        .send()
        .await
        .expect("the request through Tor")
        .text()
        .await
        .unwrap();
    println!("{answer}");
    assert!(answer.contains("\"IsTor\":true"), "{answer}");

    // The same through the connection to a node: the TCP dial goes through Tor.
    let stream = celaut_net::connect("check.torproject.org", 443).await;
    assert!(stream.is_ok(), "{:?}", stream.err());

    manager.set_mode(Mode::Off);
    assert_eq!(route(), Route::Direct);
    let _ = std::fs::remove_dir_all(&dir);
}
